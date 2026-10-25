#!/bin/sh
# PreToolUse guard: deny any tool call that would read or write cloud credentials,
# platform tokens, SSH/GPG keys, IaC state, or other secret material.
#
# Defense-in-depth (layer L4 in SECURITY.md): it backs the OS sandbox and the managed
# permission rules and covers the built-in Read/Edit/Write tools. It is NOT the primary
# boundary: a guard that inspects a command string can be evaded, so the guarantee rests
# on the OS layers (the file is not mounted / the kernel denies the read).
#
# Portable by construction:
#   - POSIX sh, no bash needed: runs on dash (Debian/Ubuntu), busybox ash (Alpine),
#     bash (Fedora/RHEL/Arch, macOS /bin/sh), and zsh.
#   - Every decision is one jq program, so matching uses jq's regex engine on every OS
#     and GNU-vs-BSD grep differences cannot change a result.
#   - Fails closed: if jq is missing or the input cannot be parsed, it denies.
#
# Contract: PreToolUse JSON on stdin; prints a deny decision or nothing; exits 0.
# It never prints "allow", so it can only tighten the policy, never loosen it.
set -eu

fail_closed() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 ||
  fail_closed "jq is not installed, so the credential guard cannot evaluate this call and is failing closed. Install jq (brew install jq, apt install jq, dnf install jq, apk add jq)."

# Protected paths, matched case-insensitively:
#   cloud CLIs (.aws .azure .oci .config/gcloud .kube .docker), platform API tokens
#   (.config/gh .config/glab-cli .vault-token .config/op .git-credentials), key material
#   (.ssh .gnupg id_* *.pem *.pfx *.p12, SOPS age keys in .config/sops), storage and
#   package-registry credentials (.s3cfg .boto .config/rclone .pypirc .npmrc .m2 cargo),
#   IaC state and real tfvars, dotenv, netrc, pgpass, and generic credential files.
cred_re='(^|/)\.(aws|azure|oci|docker|kube|ssh|gnupg|password-store)(/|$)'
cred_re="$cred_re"'|(^|/)\.config/(gcloud|gh|glab-cli|sops|rclone|op)(/|$)'
cred_re="$cred_re"'|(^|/)\.config/helm/repositories\.yaml$'
cred_re="$cred_re"'|(^|/)\.(vault-token|git-credentials|netrc|pgpass|npmrc|pypirc|s3cfg|boto|terraformrc)$'
cred_re="$cred_re"'|(^|/)\.m2/settings(-security)?\.xml$|(^|/)\.cargo/credentials(\.toml)?$'
cred_re="$cred_re"'|(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|\.(pem|pfx|p12|jks|keystore)$'
cred_re="$cred_re"'|\.tfstate(\.[^/]*)?$|\.tfvars(\.json)?$|(^|/)\.env(\.[^/]*)?$'
cred_re="$cred_re"'|(^|/)credentials(\.toml|\.json)?$|-credentials\.(json|ya?ml)$'
cred_re="$cred_re"'|(^|/)secrets?\.(json|ya?ml|env|txt)$|credentials\.tfrc\.json$'

input=$(cat)

# Only path-bearing fields of the file tools are checked, so a Grep for the word
# "credentials" in a source tree is allowed. Bash is checked on the whole command.
if ! out=$(printf '%s' "$input" | jq -c --arg re "$cred_re" '
  def deny($r): {hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}};
  .tool_name as $t
  | if ($t == "Read" or $t == "Edit" or $t == "Write" or $t == "MultiEdit"
        or $t == "NotebookEdit" or $t == "Glob" or $t == "Grep") then
      ([.tool_input.file_path, .tool_input.notebook_path,
        .tool_input.path, .tool_input.glob]
       | map(select(type == "string" and test($re; "i"))) | first) as $hit
      | if $hit then deny("Blocked: \($hit) is a protected credential, token, key, or state path. The assistant may not read or write credential material (SECURITY.md G1).")
        else empty end
    elif $t == "Bash" then
      if ((.tool_input.command // "") | test($re; "i"))
      then deny("Blocked: the command references a protected credential, token, key, or state path. Credential material is off-limits to the assistant (SECURITY.md G1).")
      else empty end
    else empty end'); then
  fail_closed "The credential guard could not parse this tool call and is failing closed."
fi

if [ -n "$out" ]; then
  printf '%s\n' "$out"
fi
exit 0
