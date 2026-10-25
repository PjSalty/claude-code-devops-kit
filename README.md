# claude-code-devops-kit

A universal, security-hardened [Claude Code](https://docs.claude.com/en/docs/claude-code)
configuration for DevOps and platform engineers working across multiple clouds.

It ships opinionated rules, subagents, skills, and hooks for authoring
infrastructure-as-code and CI/CD, plus a layered set of controls whose single
purpose is to guarantee that the assistant can only *build*: never read a cloud
credential and never reach a cloud control plane.

The kit is cloud-agnostic and carries no organization-specific data. Drop it into
a repo or install it per-user, push the managed settings from your MDM, and every
engineer gets the same baseline.

## The core guarantee

> Claude Code may author code and run local, offline validation. It has no path to
> read cloud credentials (`~/.aws`, `~/.azure`, `~/.config/gcloud`, `~/.kube`, `~/.oci`,
> docker config, environment secrets) and no path to call a cloud provider API,
> the instance metadata service, or any remote control plane.

That guarantee is enforced in depth, not by a single toggle. The weakest layer
(string-matching rules) is backed by the strongest (OS-level filesystem and network
isolation). Read [SECURITY.md](SECURITY.md) for the full threat model, the exact
mechanism of each layer, and the residual assumptions your deployment must satisfy.

## What you get

| Area | Contents |
|------|----------|
| **Operating rules** | `.claude/CLAUDE.md` plus path-scoped `.claude/rules/` for Terraform/OpenTofu, Kubernetes, containers, and CI/CD. Build-only, offline-validation posture. |
| **Subagents** | `terraform-author`, `k8s-author`, `pipeline-author`, `iac-reviewer`, `docs-writer`, each with a least-privilege tool list. |
| **Skills** | On-demand workflows (e.g. `local-validation`) loaded only when triggered, to keep context lean. |
| **Hooks** | `PreToolUse` guards that deterministically deny credential reads and cloud-CLI / metadata-endpoint calls. |
| **Managed settings** | `settings/managed-settings.json`, the org-pushed, user-immutable deny rules and lockdowns. |
| **Sandbox** | `sandbox/`, the OS bash-sandbox config and rationale (bubblewrap / Seatbelt). |
| **Devcontainer** | `devcontainer/`, a default-deny-egress container that is the recommended runtime and the hard boundary. |
| **Verification** | `test/verify.sh`, which unit-tests each hook decision and lints every config, so a reviewer can re-run the proof. |

## Install

Three independent install surfaces; use as many as apply. Full per-OS paths and
precedence are in [settings/README.md](settings/README.md).

1. **Per-repo (team baseline):** copy `.claude/` and `hooks/` into the repo. Committed,
   so every clone inherits the rules, agents, and project hooks.
2. **Per-user (recommended defaults):** merge `settings/user-settings.json` into
   `~/.claude/settings.json`.
3. **Org-enforced (the guarantee):** deliver `settings/managed-settings.json` to the
   managed-settings path as a root-owned, user-unwritable file via your MDM, and
   run engineers inside the `devcontainer/`. Only this surface makes the guarantee hold
   against an adversarial or injection-steered session.

```bash
# Verify the controls on your machine before trusting them:
./test/verify.sh
```

## Scope and non-goals

- **In scope:** authoring IaC/pipeline code, local linting and offline validation,
  code review, documentation.
- **Out of scope by design:** `terraform apply`, `kubectl` against a live cluster,
  `aws`/`az`/`gcloud` calls, reading state from remote backends, deploying. Those are
  the job of your CI/CD system with its own scoped, audited credentials, not of a
  developer's assistant.

## Compatibility

Verified against **Claude Code 2.1.310**. Settings and sandbox schemas evolve; pin
your Claude Code version (the shipped settings disable the auto-updater) and re-run
`test/verify.sh` after any upgrade.

The hooks need only a POSIX `/bin/sh` and `jq` 1.6+. They are tested on Alpine,
Debian, Ubuntu, Fedora, Rocky Linux, Amazon Linux, and Arch, and from `sh`, `bash`, and
`zsh`. See [COMPATIBILITY.md](COMPATIBILITY.md) for the matrix and macOS notes.

## License

MIT. See [LICENSE](LICENSE).
