# Bash sandbox (layer L2)

Claude Code can run Bash-tool commands inside an OS sandbox: **bubblewrap** on Linux,
**Seatbelt (`sandbox-exec`)** on macOS. This is layer L2 in [../SECURITY.md](../SECURITY.md).
Configured for this kit it does two things:

1. **Filesystem:** deny reads of the credential paths and limit writes to the
   workspace, so an indirect read through an interpreter
   (`python3 -c "open('.../.aws/credentials')"`) is denied by the kernel, not by a
   string rule.
2. **Network:** default-deny for Bash subprocesses, since build and validation are
   offline. An indirect `curl http://169.254.169.254/...` cannot open the socket.

## Coverage and limits (read this)

- The sandbox wraps **Bash-tool subprocesses only**. The built-in `Read`/`Edit`/`Write`
  tools run in the Claude Code process, not a subprocess, so they are **not** sandboxed;
  they are covered by the permission `deny` rules and the `guard-credentials` hook.
- MCP servers run as their own processes and are **not** covered; the kit forbids MCP
  servers in managed settings instead.
- The sandbox is therefore one layer of the composition, not the whole guarantee. When
  you need a hard boundary, run inside `../devcontainer/`, which removes the credential
  files and the network routes entirely.

## Linux prerequisites

`bubblewrap` must be installed (`bwrap --version`). User namespaces must be permitted
(`sysctl kernel.unprivileged_userns_clone=1` on distros that gate them). The kit's
devcontainer already includes bubblewrap.

## Enabling it

The `sandbox` settings block controls this. Its schema has changed across Claude Code
releases, so this kit does **not** hard-code a possibly-stale schema into the enforced
`managed-settings.json`. Instead:

1. Confirm the current `sandbox` keys for your version in the docs:
   <https://docs.claude.com/en/docs/claude-code/settings> (sandbox / bash sandboxing).
2. Enable it with the network default-denied and the credential paths read-denied.
   The filesystem read-deny should reuse the same credential paths listed in
   `../settings/managed-settings.json`.
3. Do **not** enable any "auto-allow bash if sandboxed" option in a way that would let
   the model run arbitrary commands without review just because they are sandboxed,
   unless you have accepted that trade-off; for a security-reviewed deployment prefer
   explicit allow rules.
4. Verify with a quick check that a sandboxed `cat` of a credential path and a
   sandboxed `curl` to the metadata IP both fail.

A verified, version-specific `sandbox` block for your Claude Code version belongs in
`managed-settings.json` once confirmed. Treat the devcontainer as the primary boundary
until it is.
