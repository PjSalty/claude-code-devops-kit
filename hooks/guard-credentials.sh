#!/usr/bin/env bash
# PreToolUse guard: deny any tool call that would read or write cloud credentials,
# SSH keys, IaC state, or other secret material.
#
# This is defense-in-depth. It backs the OS sandbox (L2) and managed permission
# rules (L3); it is NOT the primary boundary. A guard that inspects a command
# string can be evaded by obfuscation, so the real guarantee is L1/L2 (the file is
# not present / the kernel denies the read). See SECURITY.md.
#
# Contract: reads the PreToolUse JSON on stdin, prints a decision object, exits 0.
set -euo pipefail

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

# Protected path patterns (case-insensitive). Credential stores, key material,
# IaC state, tfvars, dotenv, netrc, generic secret/credential filenames.
cred_re='(^|/)\.(aws|azure|oci)(/|$)|(^|/)\.config/gcloud(/|$)|(^|/)\.kube(/|$)|(^|/)\.docker/config\.json$|(^|/)\.ssh(/|$)|(^|/)id_(rsa|ed25519|ecdsa)|\.pem$|\.pfx$|\.p12$|(^|/)\.netrc$|\.tfstate(\.|$)|(^|/)\.env(\.[^/]*)?$|(^|/)credentials$|-credentials\.|\.tfvars$|(^|/)secrets?\.[a-z]+$|(^|/)\.terraformrc$|credentials\.tfrc\.json$|(^|/)\.pgpass$|(^|/)\.npmrc$'

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  Read|Edit|Write|NotebookEdit|Glob|Grep)
    # Only the path-bearing fields, so a Grep for the literal word "credentials"
    # is not itself denied.
    targets="$(jq -r '[.tool_input.file_path, .tool_input.notebook_path, .tool_input.path, .tool_input.glob] | map(select(. != null)) | .[]' <<<"$input" 2>/dev/null || true)"
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if printf '%s' "$t" | grep -Eiq "$cred_re"; then
        deny "Blocked: '$t' is a protected credential, key, or state path. The assistant may not read or write credential material (SECURITY.md G1)."
      fi
    done <<<"$targets"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
    if printf '%s' "$cmd" | grep -Eiq "$cred_re"; then
      deny "Blocked: the command references a protected credential, key, or state path. Credential material is off-limits to the assistant (SECURITY.md G1)."
    fi
    ;;
esac

# No objection from this guard. Stay silent; other hooks and the permission flow decide.
exit 0
