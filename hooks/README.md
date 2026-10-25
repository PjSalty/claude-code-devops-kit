# Hooks

Two `PreToolUse` guards that return a deterministic `deny` decision before a tool
runs. They are layer L4 in [SECURITY.md](../SECURITY.md): defense-in-depth that makes
the common denials fast, logged, and clearly explained, and that covers the built-in
`Read`/`Edit`/`Write` tools (which the bash sandbox does not). They are **not** the
primary boundary; a string-inspecting guard can be evaded, so the OS layers (L1/L2)
carry the guarantee.

| Hook | Fires on | Denies |
|------|----------|--------|
| `guard-credentials.sh` | `Bash`, `Read`, `Edit`, `Write`, `NotebookEdit`, `Glob`, `Grep` | reads/writes of credential stores, SSH keys, IaC state, `*.tfvars`, `.env*`, `*.pem`, `.netrc`, generic `credentials`/`secret*` files |
| `guard-cloud-cli.sh` | `Bash` | the metadata IP, cloud/cluster/secret CLIs (`aws`/`az`/`gcloud`/`kubectl`/`vault`/`sops`/...), platform API clients (`gh`, `glab`), live IaC and deploy verbs (`terraform apply`, `cdk deploy`, `helm install`, `docker push`), `git push`, and outbound net tools (`curl`/`wget`/`ssh`/...) |

## Contract

Each hook reads the PreToolUse JSON on stdin and prints a decision:

```json
{ "hookSpecificOutput": { "hookEventName": "PreToolUse",
  "permissionDecision": "deny", "permissionDecisionReason": "..." } }
```

A silent `exit 0` with no output means "no objection", leaving the normal permission
flow to decide. The hooks never emit `allow`, so they can only tighten, never loosen,
the policy.

## Install

- **Team baseline:** the `hooks` block in `hooks.json` is already present in
  `.claude/settings.json`, referencing the scripts via `$CLAUDE_PROJECT_DIR`.
- **Enforced:** copy the same block into the root-owned `managed-settings.json`, with
  an **absolute** path to the installed hooks, and set `allowManagedHooksOnly` so a
  project or user cannot register competing hooks or drop these. See
  [../settings/README.md](../settings/README.md).

Requirements: a POSIX `/bin/sh` and `jq` 1.6 or newer; no bash. Every decision runs
inside one `jq` program, so results are identical on Linux and macOS. If `jq` is
missing or the input cannot be parsed, the hooks fail closed (deny). See
[../COMPATIBILITY.md](../COMPATIBILITY.md) for the verified platforms.

## Tuning

The patterns are deliberately strict (deny-by-default for anything that looks like a
secret or a live action). If a team needs an offline tool that trips a guard (for
example `helm repo add` against an internal mirror), narrow the pattern in the script
rather than disabling the hook, and add a test case to `../test/verify.sh` so the
change is proven and reviewed.
