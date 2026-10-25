#!/usr/bin/env bash
# PreToolUse guard: deny Bash commands that would call a cloud provider API, reach a
# remote cluster or control plane, hit the instance metadata service, or otherwise
# perform a live action. Authoring code and local, offline validation are allowed.
#
# Defense-in-depth, same caveat as guard-credentials.sh: the real network boundary is
# the devcontainer egress firewall (L1) and the bash sandbox (L2). See SECURITY.md.
#
# Contract: reads the PreToolUse JSON on stdin, prints a decision object, exits 0.
set -euo pipefail

input="$(cat)"
[ "$(jq -r '.tool_name // empty' <<<"$input")" = "Bash" ] || exit 0
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Instance metadata service: IPv4, the ECS/task endpoint, IPv6, and the GCP name.
if printf '%s' "$cmd" | grep -Eiq '169\.254\.169\.254|169\.254\.170\.2|fd00:ec2::254|metadata\.google\.internal'; then
  deny "Blocked: the instance metadata service (169.254.169.254 and equivalents) is a credential source and is not reachable from the assistant (SECURITY.md G2)."
fi

# Program invoked at a command boundary (start, ; & | ( or && ||). The bracket
# class holds literal ; & | ( ; the trailing alternation adds && and ||.
b='(^|[;&|(]|&&|\|\|)[[:space:]]*'

# Cloud and secret-manager CLIs. All of these talk to a remote API or vault.
clouds='aws|aws-vault|az|azd|gcloud|gsutil|bq|doctl|linode-cli|scw|ibmcloud|aliyun|oci|eksctl|kubectl|oc|kubectx|argocd|flux|pulumi|vault|op|doppler|sops'
if printf '%s' "$cmd" | grep -Eiq "${b}(${clouds})([[:space:]]|$)"; then
  deny "Blocked: a cloud or secret-manager CLI (aws/az/gcloud/kubectl/vault/sops/...) was invoked. These reach a remote API or decrypt secrets. Author the definition and let CI/CD apply it with its own scoped credentials (SECURITY.md G2)."
fi

# IaC tools: authoring and offline validation are fine; live verbs are not.
if printf '%s' "$cmd" | grep -Eiq '(^|[^a-z])(terraform|tofu|terragrunt)[[:space:]]+(apply|destroy|import|state|refresh|taint|untaint|force-unlock|login|console)([[:space:]]|$)'; then
  deny "Blocked: a live Terraform/OpenTofu subcommand (apply/destroy/import/state/refresh/login/...) was invoked. fmt, validate, and 'plan -refresh=false -lock=false' are allowed (SECURITY.md G2)."
fi
if printf '%s' "$cmd" | grep -Eiq '(^|[^a-z])helm[[:space:]]+(install|upgrade|uninstall|rollback|repo[[:space:]]+add)([[:space:]]|$)'; then
  deny "Blocked: a live Helm verb was invoked. Use 'helm template' or 'helm lint' for offline rendering (SECURITY.md G2)."
fi
if printf '%s' "$cmd" | grep -Eiq '(^|[^a-z])(docker|podman|nerdctl)[[:space:]]+(push|login|pull)([[:space:]]|$)|(^|[^a-z])skopeo[[:space:]]+(copy|login)([[:space:]]|$)'; then
  deny "Blocked: pushing, pulling, or logging into a registry is a live network action (SECURITY.md G2)."
fi

# Raw outbound network tools. Build and validation are offline; the assistant must
# not fetch from arbitrary hosts even if the sandbox is not active.
if printf '%s' "$cmd" | grep -Eiq "${b}(curl|wget|nc|ncat|telnet|ssh|scp|sftp|rsync|socat)([[:space:]]|$)"; then
  deny "Blocked: outbound network tools (curl/wget/ssh/...) are not available to the assistant. Build and validation run offline (SECURITY.md G2)."
fi

exit 0
