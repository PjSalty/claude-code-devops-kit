# Compatibility

## Verified matrix

`test/verify.sh` run inside each image, with the hooks executing through that
distro's own `/bin/sh` and its packaged `jq`:

| Platform | `/bin/sh` | jq | Result |
|----------|-----------|----|--------|
| Alpine 3.20 | busybox ash | 1.7.1 | 35/35 |
| Debian 12 | dash | 1.6 | 35/35 |
| Ubuntu 24.04 | dash | 1.7 | 35/35 |
| Fedora 41 | bash | 1.7.1 | 35/35 |
| Rocky Linux 9 (RHEL family) | bash | 1.6 | 35/35 |
| Amazon Linux 2023 | bash | 1.8.1 | 35/35 |
| Arch Linux, with shellcheck | bash | 1.8.2 | 39/39 |

The four extra checks on Arch are shellcheck, which the minimal images do not ship.

The hook command strings in `.claude/settings.json` were also run through `sh`, `bash`,
and `zsh` from a project path containing a space; all three ran both hooks.

**macOS:** not executed for this release. Statically it is covered: the hooks are
POSIX `sh` (shellcheck clean in POSIX mode), every decision runs inside `jq` (the same
regex engine on every OS), and no GNU-only tool flags are used. The test harness needs
bash but no bash-4 features, so the system `/bin/bash` 3.2 works. Run
`./test/verify.sh` on a Mac as part of your acceptance.

**Windows:** use WSL2 or the devcontainer.

## Requirements

| Component | Needs |
|-----------|-------|
| Hooks (runtime) | a POSIX `/bin/sh` and `jq` 1.6 or newer. No bash. If `jq` is missing, the hooks fail closed (deny every call) and say why. |
| Tests (`verify.sh`) | `bash` (any version, including macOS 3.2), `jq`, `find`, `grep`; `shellcheck` optional. |
| Devcontainer | a Linux container runtime: Docker, Podman, or on macOS Docker Desktop, Colima, or OrbStack. |

Install `jq` with `brew install jq`, `apt install jq`, `dnf install jq`, or `apk add jq`.

## Your login shell does not matter

zsh, bash, and fish all work. Claude Code runs each hook by path, and each hook names
its own interpreter (`#!/bin/sh`). The command strings quote `$CLAUDE_PROJECT_DIR`, so
a project path with spaces works whichever shell launches them.

## Portability traps this release handles

- **jq 1.6 `-e`:** exits 0 on empty input where 1.7+ exits 4. The harness checks for
  empty output before calling `jq -e`, so an allow is never misread as a deny.
- **Unquoted paths:** `$CLAUDE_PROJECT_DIR/hooks/...` splits on a space under `sh` and
  `bash` (zsh does not split), so the command strings quote it.
- **Tool flags:** busybox `grep` lacks `-I`, and `--include`/`--exclude-dir` are GNU
  extensions, so the harness lists files with `find ... ! -path` and greps each one.
- **No bash on minimal images:** Alpine and other busybox systems have no bash, so the
  hooks use only `/bin/sh`.
