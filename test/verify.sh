#!/usr/bin/env bash
# Reproducible proof of the kit's controls. Three parts:
#   1. Lint every JSON and shell file.
#   2. Unit-test both PreToolUse guards: feed each the tool-call JSON a reviewer
#      cares about and assert the deny/allow decision.
#   3. Secret-scan the tree, so the kit ships no credential material.
# Exits non-zero if any case fails. Safe to run anywhere, including inside the
# devcontainer as an acceptance gate. It touches no real credential and no network.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cred_hook="$root/hooks/guard-credentials.sh"
cloud_hook="$root/hooks/guard-cloud-cli.sh"
pass=0 fail=0

ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

# decision <hook> <json>  ->  prints "deny" or "allow"
decision() {
  local out
  out="$(printf '%s' "$2" | "$1" 2>/dev/null)"
  # Empty output means "no objection". Test it before calling jq: jq 1.6's -e exits 0
  # on empty input (1.7+ exits 4), which would misread every allow as a deny.
  if [ -z "$out" ]; then
    echo allow
  elif printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1; then
    echo deny
  else
    echo allow
  fi
}

# expect <label> <hook> <want: deny|allow> <json>
expect() {
  local got; got="$(decision "$2" "$4")"
  if [ "$got" = "$3" ]; then ok "$1 ($3)"; else bad "$1: wanted $3, got $got"; fi
}

read_input()  { jq -n --arg t "$1" --arg p "$2" '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{file_path:$p}}'; }
bash_input()  { jq -n --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
grep_input()  { jq -n --arg p "$1" --arg q "$2" '{hook_event_name:"PreToolUse",tool_name:"Grep",tool_input:{path:$p,pattern:$q}}'; }

echo "== 1. Lint"
command -v jq >/dev/null || { echo "jq is required"; exit 2; }
while IFS= read -r f; do
  if jq -e . "$f" >/dev/null 2>&1; then ok "json valid: ${f#"$root"/}"; else bad "json invalid: ${f#"$root"/}"; fi
done < <(find "$root" -name '*.json' ! -path '*/.git/*')
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then ok "shell parses: ${f#"$root"/}"; else bad "shell parse error: ${f#"$root"/}"; fi
done < <(find "$root" -name '*.sh' ! -path '*/.git/*')
if command -v shellcheck >/dev/null; then
  while IFS= read -r f; do
    if shellcheck -S warning "$f" >/dev/null 2>&1; then ok "shellcheck clean: ${f#"$root"/}"; else bad "shellcheck findings: ${f#"$root"/}"; fi
  done < <(find "$root" -name '*.sh' ! -path '*/.git/*')
else
  echo "  (shellcheck not installed; skipping, not a failure)"
fi

echo "== 2a. guard-credentials.sh"
expect "read aws credentials"       "$cred_hook" deny  "$(read_input Read  "/home/u/.aws/credentials")"
expect "write ssh private key"      "$cred_hook" deny  "$(read_input Write "/home/u/.ssh/id_rsa")"
expect "read kubeconfig"            "$cred_hook" deny  "$(read_input Read  "/home/u/.kube/config")"
expect "read dotenv.production"     "$cred_hook" deny  "$(read_input Read  "./app/.env.production")"
expect "read tfstate"              "$cred_hook" deny  "$(read_input Read  "./infra/terraform.tfstate")"
expect "read real tfvars"           "$cred_hook" deny  "$(read_input Read  "./prod.tfvars")"
expect "bash cat of credentials"    "$cred_hook" deny  "$(bash_input 'cat ~/.aws/credentials')"
expect "read a normal source file"  "$cred_hook" allow "$(read_input Read  "./modules/vpc/main.tf")"
expect "grep word in source tree"   "$cred_hook" allow "$(grep_input "./src" "credentials")"
expect "bash terraform fmt"         "$cred_hook" allow "$(bash_input 'terraform fmt -recursive')"

echo "== 2b. guard-cloud-cli.sh"
expect "aws api call"               "$cloud_hook" deny  "$(bash_input 'aws s3 ls')"
expect "az api call"                "$cloud_hook" deny  "$(bash_input 'az vm list')"
expect "gcloud api call"            "$cloud_hook" deny  "$(bash_input 'gcloud compute instances list')"
expect "kubectl to cluster"         "$cloud_hook" deny  "$(bash_input 'kubectl get pods -A')"
expect "metadata endpoint curl"     "$cloud_hook" deny  "$(bash_input 'curl http://169.254.169.254/latest/meta-data/iam/')"
expect "terraform apply"            "$cloud_hook" deny  "$(bash_input 'terraform apply -auto-approve')"
expect "helm install"               "$cloud_hook" deny  "$(bash_input 'helm install app ./chart')"
expect "vault read secret"          "$cloud_hook" deny  "$(bash_input 'vault kv get secret/app')"
expect "docker push"                "$cloud_hook" deny  "$(bash_input 'docker push registry.example.com/app:1')"
expect "sops decrypt"               "$cloud_hook" deny  "$(bash_input 'sops -d secrets.enc.yaml')"
expect "terraform fmt (offline)"    "$cloud_hook" allow "$(bash_input 'terraform fmt -recursive')"
expect "terraform validate"         "$cloud_hook" allow "$(bash_input 'terraform validate')"
expect "kustomize build (offline)"  "$cloud_hook" allow "$(bash_input 'kustomize build overlays/prod')"
expect "helm template (offline)"    "$cloud_hook" allow "$(bash_input 'helm template app ./chart')"
expect "non-bash tool ignored"      "$cloud_hook" allow "$(read_input Read ./main.tf)"

echo "== 3. Secret scan (the kit must ship no secrets)"
# Look for private-key headers and common cloud key shapes in tracked files.
hits=0
# Portable across GNU (Linux) and BSD (macOS) tools: list files with find and grep
# each, instead of GNU-only grep --include/--exclude-dir.
pk="$(find "$root" -type f ! -path '*/.git/*' -exec grep -lE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' {} \; 2>/dev/null || true)"
if [ -n "$pk" ]; then
  echo "  FAIL  a private key is present in: $pk"; hits=$((hits+1))
fi
ak="$(find "$root" -type f ! -path '*/.git/*' -exec grep -lE -- '(AKIA|ASIA)[A-Z0-9]{16}' {} \; 2>/dev/null || true)"
if [ -n "$ak" ]; then
  echo "  FAIL  an AWS access key id is present in: $ak"; hits=$((hits+1))
fi
if [ "$hits" -eq 0 ]; then ok "no private keys or cloud key ids in the tree"; else fail=$((fail+hits)); fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
