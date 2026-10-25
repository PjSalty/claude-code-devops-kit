# Settings: paths, precedence, and lockdown

Three settings files ship here. They are not interchangeable; each has a different
trust level.

| File | Install to | Trust |
|------|-----------|-------|
| `../.claude/settings.json` | committed in the repo | team baseline; a developer can edit it |
| `user-settings.json` | merge into `~/.claude/settings.json` | per-user convenience and safety net; the user can edit it |
| `managed-settings.json` | the managed path below, **root-owned** | enforced; the user and the model cannot edit or override it |

Only `managed-settings.json`, delivered as a root-owned file and paired with the
devcontainer, is a control a security team should rely on. The other two are
defaults that a motivated user can change.

## Managed-settings path per OS

| OS | Path |
|----|------|
| Linux | `/etc/claude-code/managed-settings.json` |
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Windows | `C:\ProgramData\ClaudeCode\managed-settings.json` |

Deliver it via MDM (Jamf, Intune, Ansible, etc.) owned by `root`, mode `0644`, so the
engineer running Claude Code cannot modify it. Update the two hook `command` paths in
the file to wherever you install `hooks/` (the shipped value is
`/opt/claude-code-devops-kit/hooks/...`).

## Precedence

Managed settings take precedence over everything else (command-line flags, local
project settings, shared project settings, user settings). A `deny` rule in the
managed file cannot be undone by a lower layer. This is why the enforced controls
live there and not in the project file.

Reference: <https://docs.claude.com/en/docs/claude-code/settings>

## Non-essential traffic and the hosts Claude Code needs

The shipped `env` block disables telemetry, error reporting, the auto-updater, and
other non-essential traffic. With those off, Claude Code still needs to reach the
Anthropic API to function. Your egress allowlist (see `../devcontainer/init-firewall.sh`)
must permit the Anthropic API host and your package registries and git host, and
nothing else. Confirm the exact current hostnames against the docs for your version;
do not widen the allowlist to a cloud provider range.

Reference: <https://docs.claude.com/en/docs/claude-code/settings> (environment variables)

## Lockdown keys to verify and add

The enforced file ships with the keys we can stand behind for Claude Code 2.1.310.
The following additional managed-only keys **harden the lockdown further but must be
confirmed against your installed version before you rely on them** (a misspelled key
silently does nothing, which is worse than knowing it is absent). Check each in the
settings docs for your version, then add the confirmed spelling to
`managed-settings.json`:

- a key that makes **only managed hooks** run, so a project or user cannot register
  competing hooks or drop the guards;
- a key that makes **only managed permission rules** apply, so a lower layer cannot
  add `allow` rules that widen the policy;
- an **MCP server allowlist / denylist** so only administrator-vetted MCP servers can
  load (ship it empty to forbid all MCP servers);
- a **known-marketplaces** restriction so plugins can only come from a vetted source.

`disableBypassPermissionsMode: "disable"` is already set, which prevents
`--dangerously-skip-permissions` / bypass mode from loosening the policy at runtime.

Verify every key, and the whole file, by running `../test/verify.sh` and by starting
Claude Code with `claude --debug` once and confirming the managed file is loaded and
the deny rules are active.

Reference: <https://docs.claude.com/en/docs/claude-code/settings> and
<https://docs.claude.com/en/docs/claude-code/iam>
