#!/bin/sh
# PreToolUse guard: deny Bash commands that would call a cloud provider API, reach a
# remote cluster or control plane, hit the instance metadata service, use a platform
# API client, push code, or otherwise perform a live action. Authoring code and local,
# offline validation are allowed.
#
# Defense-in-depth, same caveat as guard-credentials.sh: the real network boundary is
# the devcontainer egress firewall (L1) and the bash sandbox (L2). See SECURITY.md.
#
# Portable by construction: POSIX sh (dash, busybox ash, bash, zsh), every decision in
# one jq program (same regex engine on every OS), and fail-closed on a missing jq or
# unparseable input.
#
# Contract: PreToolUse JSON on stdin; prints a deny decision or nothing; exits 0.
set -eu

fail_closed() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 ||
  fail_closed "jq is not installed, so the cloud-CLI guard cannot evaluate this call and is failing closed. Install jq (brew install jq, apt install jq, dnf install jq, apk add jq)."

# Instance metadata services: AWS/Azure/GCP/OCI IPv4, the ECS task endpoint, AWS IPv6,
# and the GCP metadata name.
meta_re='169\.254\.169\.254|169\.254\.170\.2|fd00:ec2::254|metadata\.google\.internal'

# A program at a command boundary: line start, ; & | ( or && ||, then optional space.
b='(^|[;&|(]|&&|\|\|)\s*'

# Cloud, cluster, platform-API, and secret-manager CLIs. Each one talks to a remote API
# or decrypts secrets. The trailing (\s|$) stops "az" from also matching "azure-...",
# so azcopy is listed explicitly.
clis='aws|aws-vault|az|azd|azcopy|gcloud|gsutil|bq|doctl|linode-cli|scw|ibmcloud|aliyun|oci'
clis="$clis"'|eksctl|kubectl|oc|kubectx|kubens|k9s|argocd|flux|pulumi|vault|op|doppler|sops'
clis="$clis"'|s3cmd|rclone|gh|glab'
cli_re="$b"'('"$clis"')(\s|$)'

# IaC and deploy tools: authoring and offline validation are fine, live verbs are not.
iac_re='(^|[^a-z])(terraform|tofu|terragrunt)\s+(apply|destroy|import|state|refresh|taint|untaint|force-unlock|login|console)(\s|$)'
deploy_re='(^|[^a-z])(cdk\s+(deploy|destroy|bootstrap|diff|import|watch)|sam\s+(deploy|delete|sync)|(serverless|sls)\s+(deploy|remove))(\s|$)'
helm_re='(^|[^a-z])helm\s+(install|upgrade|uninstall|rollback|push|registry\s+login|repo\s+add)(\s|$)'
reg_re='(^|[^a-z])(docker|podman|nerdctl|buildah)\s+(push|login|pull)(\s|$)|(^|[^a-z])skopeo\s+(copy|login|sync)(\s|$)'

# Pushing code is the human's step: it triggers CI, which may deploy.
push_re='(^|[^a-z])git\s+push(\s|$)'

# Raw outbound network tools. Build and validation are offline; the assistant must not
# fetch from arbitrary hosts even if the sandbox is not active.
net_re="$b"'(curl|wget|nc|ncat|netcat|telnet|ssh|scp|sftp|rsync|socat)(\s|$)'

input=$(cat)

if ! out=$(printf '%s' "$input" | jq -c \
    --arg meta "$meta_re" --arg cli "$cli_re" --arg iac "$iac_re" \
    --arg deploy "$deploy_re" --arg helm "$helm_re" --arg reg "$reg_re" \
    --arg push "$push_re" --arg net "$net_re" '
  def deny($r): {hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}};
  if .tool_name != "Bash" then empty else
    (.tool_input.command // "") as $c
    | if ($c | test($meta; "i")) then
        deny("Blocked: the instance metadata service (169.254.169.254 and equivalents) is a credential source and is not reachable from the assistant (SECURITY.md G2).")
      elif ($c | test($cli; "i")) then
        deny("Blocked: a cloud, cluster, platform-API, or secret-manager CLI (aws, az, gcloud, kubectl, gh, vault, sops, ...) was invoked. These reach a remote API or decrypt secrets. Author the definition and let CI/CD apply it with its own scoped credentials (SECURITY.md G2).")
      elif ($c | test($iac; "i")) then
        deny("Blocked: a live Terraform/OpenTofu subcommand (apply, destroy, import, state, refresh, login, ...) was invoked. fmt, validate, and plan -refresh=false -lock=false are allowed (SECURITY.md G2).")
      elif ($c | test($deploy; "i")) then
        deny("Blocked: a deploy verb (cdk deploy, sam deploy, serverless deploy, ...) was invoked. Deploys run in CI/CD, not from the assistant (SECURITY.md G2).")
      elif ($c | test($helm; "i")) then
        deny("Blocked: a live Helm verb was invoked. Use helm template or helm lint for offline rendering (SECURITY.md G2).")
      elif ($c | test($reg; "i")) then
        deny("Blocked: pushing, pulling, or logging into a registry is a live network action (SECURITY.md G2).")
      elif ($c | test($push; "i")) then
        deny("Blocked: git push is the human step. It triggers CI, which may deploy. Commit locally and let a person review and push (SECURITY.md G2).")
      elif ($c | test($net; "i")) then
        deny("Blocked: outbound network tools (curl, wget, ssh, ...) are not available to the assistant. Build and validation run offline (SECURITY.md G2).")
      else empty end
  end'); then
  fail_closed "The cloud-CLI guard could not parse this tool call and is failing closed."
fi

if [ -n "$out" ]; then
  printf '%s\n' "$out"
fi
exit 0
