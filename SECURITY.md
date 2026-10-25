# Security model

This document is written for a security reviewer. It states the goal, the trust
boundary, each control and the exact mechanism that enforces it, and the residual
assumptions your deployment must satisfy for the guarantee to hold. It deliberately
does not overclaim: where a control is advisory rather than absolute, it says so.

## 1. Goal

A DevOps engineer uses Claude Code to author infrastructure-as-code and CI/CD
definitions and to run local, offline validation. The assistant must not be able to:

- **G1** read cloud credentials or other secrets (`~/.aws`, `~/.azure`,
  `~/.config/gcloud`, `~/.kube`, `~/.oci`, `~/.docker/config.json`, SSH keys,
  `*.tfvars`, `.env*`, `*.pem`, environment variables holding tokens); or
- **G2** reach a cloud provider API, the instance metadata service
  (`169.254.169.254`, `fd00:ec2::254`), or any other remote control plane.

It may: read and write source files in the workspace, and run offline build and
validation tools (`terraform fmt/validate`, `tofu`, `tflint`, `kubeconform`,
`kustomize build`, `helm template`, `hadolint`, `yamllint`, `checkov`, unit tests).

## 2. Trust boundary

The agent (the model, its built-in tools, and every subprocess it spawns) is treated
as **untrusted** with respect to G1 and G2. Controls must hold even when the model is
adversarial or steered by prompt injection embedded in a file, a cloned repo, a log,
or an API response it reads. "The model was told not to" is never a control here; it
is a convenience. Every real control below is enforced by Claude Code or the OS,
outside the model's discretion.

## 3. Controls, strongest first

### L1. Runtime isolation (primary, OS-enforced)

Run Claude Code inside the provided `devcontainer/`. The container:

- **mounts no credential material.** The workspace is bind-mounted; `~/.aws` and the
  other credential paths on the host are simply not present inside the container. A
  file that is not mounted cannot be read by any tool, sandboxed or not. (Satisfies G1
  by absence.)
- **enforces default-deny egress.** `init-firewall.sh` installs an allowlist
  (`iptables`/`ipset`) permitting only the hosts needed to build: the Anthropic API,
  the git host, and the package registries. Everything else, including every cloud API
  endpoint and `169.254.169.254`, is dropped. (Satisfies G2 at the network layer.)

This is the only layer that makes the guarantee hold against an adversarial process,
because it removes the credential files and the network routes entirely. Treat the
container, not the config files, as the boundary.

### L2. Bash sandbox (OS-enforced; primary when not containerized, defense-in-depth when containerized)

Claude Code's `sandbox` setting runs Bash-tool commands under an OS sandbox
(bubblewrap on Linux, Seatbelt on macOS). Configured here to:

- deny reads of the credential paths at the filesystem layer, and limit writes to the
  workspace; and
- default-deny network for Bash subprocesses (build and validation are offline), with
  a narrow allowlist if your package manager needs one.

This stops an indirect read or call that a string rule would miss, for example
`python3 -c "print(open('/home/u/.aws/credentials').read())"` or
`curl http://169.254.169.254/...`, because the subprocess is denied the file and the
socket by the kernel, regardless of how the command is spelled.

**Coverage limit (stated plainly):** the sandbox covers Bash-tool subprocesses. It
does **not** cover the built-in `Read`/`Edit`/`Write` tools (they run in the Claude
Code process, not a subprocess) or MCP servers. Those are covered by L3 and L4. The
guarantee is the composition of L1, L2, L3 and L4, not any single layer.

### L3. Managed permission rules (enforced by Claude Code, user-immutable)

`settings/managed-settings.json` is delivered to the managed-settings path as a
root-owned file. It sets `deny` rules that block the built-in file tools and the Bash
tool from credential paths and networked CLIs, and it disables the escape hatches:

- `Read`/`Edit`/`Write` deny on every credential, key, state, and `.env` path.
- `Bash` deny on `aws`, `az`, `gcloud`, `kubectl`, `doctl`, `terraform apply`,
  `curl`/`wget`/`nc` to arbitrary hosts, and the metadata IP.
- Bypass and loosening disabled, so neither the user nor the model can widen the policy
  at runtime (see `settings/README.md` for the exact keys and their managed-only
  semantics).

Permission rules on Bash are **string-matched**, so on their own they can be evaded by
obfuscation. That is why they are L3, backed by L1/L2, not the primary control. Their
value is auditable, declarative intent and coverage of the non-subprocess file tools.

### L4. PreToolUse hooks (deterministic deny, defense-in-depth)

`hooks/guard-credentials.sh` and `hooks/guard-cloud-cli.sh` run before every tool call
and return a structured `deny` when a Bash command or a file-tool target touches a
credential path, a cloud CLI, a secret file pattern, or the metadata endpoint. They are
delivered as managed hooks so a project or the model cannot disable them.

Hooks that inspect a command string share L3's evasion caveat and are therefore also
defense-in-depth, not the guarantee. They exist to turn the common cases into a hard,
logged denial with a clear reason, and to catch the built-in file tools before the
read happens.

### L5. MCP and context side-channels

- `managed-settings.json` ships an **empty MCP allowlist** (and the kit's project
  config uses `--strict-mcp-config` semantics): no MCP server loads unless an
  administrator vets and adds it. This closes the "an MCP tool quietly calls a cloud
  API" side-channel.
- No secret ever enters the kit. `.gitignore` blocks credential/state patterns and
  `test/verify.sh` secret-scans staged files, so credentials cannot be committed and
  then read back out of git history.

## 4. Why not "just permission rules"?

Permission `deny` on `Bash` matches the command prefix/pattern as text. A sufficiently
motivated or injection-driven model can read a file through an interpreter, a renamed
binary, or an encoded path, none of which a text rule reliably catches. We therefore
do not present rules as the boundary. The boundary is L1 (no file to read, no route to
the API) and L2 (kernel-level filesystem and network deny). L3 and L4 add auditable
intent, cover the non-subprocess tools, and make the expected-case denial fast, clear,
and logged.

## 5. Residual assumptions (the reviewer's checklist)

The guarantee holds **only** if all of these are true in your deployment:

1. `managed-settings.json` is installed at the managed path and is **root-owned and
   not writable by the engineer**. If it is user-writable, L3 and L4 are advisory.
2. Engineers run Claude Code **inside the devcontainer**, or on a host where the
   bash sandbox is enabled **and** the credential directories are not readable by the
   user running Claude Code. Running outside both leaves only L3/L4 (bypassable).
3. No cloud credentials are mounted into the container and no cloud env vars are
   passed into it. The devcontainer config mounts only the workspace and sets no cloud
   env. Verify your wrapper does not add them.
4. The egress allowlist in `init-firewall.sh` is reviewed and does not resolve to, or
   proxy to, a cloud control plane. No broad CIDR, no corporate proxy that reaches
   cloud APIs.
5. `disableBypassPermissionsMode` is in effect and `--dangerously-skip-permissions`
   is not used outside a disposable, already-isolated container.
6. The Claude Code version is pinned (`autoUpdates` disabled) and `test/verify.sh`
   has been re-run on it. Settings and sandbox schemas change between versions.
7. The MCP allowlist is empty or contains only servers your team has vetted to be
   local and offline.

## 6. Data egress to Anthropic

Claude Code sends prompts, the contents of files it reads, and tool output to the
Anthropic API to function. Treat everything the agent can read as disclosed to that
API. This is the second reason the credential controls matter: a blocked read is also
a blocked disclosure. Non-essential traffic (telemetry, error reporting, the updater)
is disabled in the shipped settings; the exact keys and the hosts Claude Code must
reach are listed in `settings/README.md`. Confirm your plan's data-retention terms
separately with Anthropic; that is a contractual control, not one this kit can set.

## 7. What this kit does not do

- It does not deploy, and it does not hold or broker credentials for deployment. Live
  changes are the job of CI/CD with its own scoped, audited, short-lived credentials.
- It does not replace network egress controls at your perimeter; it complements them.
- It does not defend against a compromised Claude Code binary or a malicious OS image.
  Supply-chain integrity of the runtime is assumed and out of scope.

## 8. Verifying the claims

`test/verify.sh` is the reproducible proof. It feeds each hook the tool-call inputs a
reviewer cares about (a read of `~/.aws/credentials`, an `aws s3 ls`, a `curl` to the
metadata IP, a benign `terraform fmt`) and asserts the deny/allow decision, and it
validates every JSON and shell file in the kit. Run it on the target image as part of
your acceptance. Results are printed per case with a PASS/FAIL and the reason string.

Report a security issue by opening a private advisory on the repository.
