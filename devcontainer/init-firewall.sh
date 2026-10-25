#!/usr/bin/env bash
# Default-deny egress for the Claude Code devcontainer (layer L1, network half).
#
# After this runs, outbound traffic is dropped except to an explicit allowlist: DNS,
# the Anthropic API, the package registries, and the git host needed to build. Every
# cloud provider API endpoint and the instance metadata service are unreachable.
#
# Run as root at container start, with NET_ADMIN (see devcontainer.json). Review the
# ALLOW_DOMAINS list before use: it must not resolve or proxy to a cloud control plane.
set -euo pipefail

# Hosts the assistant legitimately needs to build. Keep this list minimal and audited.
# Confirm the Anthropic API hostnames for your version against the official docs.
ALLOW_DOMAINS=(
  "api.anthropic.com"
  "registry.npmjs.org"
  "pypi.org"
  "files.pythonhosted.org"
  "registry.terraform.io"
  "releases.hashicorp.com"
  "github.com"
  "codeload.github.com"
  "objects.githubusercontent.com"
)

command -v iptables >/dev/null && command -v ipset >/dev/null || {
  echo "init-firewall: iptables and ipset are required" >&2; exit 1; }

# Start clean.
iptables -F
iptables -X 2>/dev/null || true
ipset destroy allowed 2>/dev/null || true
ipset create allowed hash:ip

# Explicitly reject the metadata services first, so a bug in the allowlist can never
# expose them (belt and suspenders; default-deny below would already drop them).
for meta in 169.254.169.254 169.254.170.2; do
  iptables -A OUTPUT -d "$meta" -j REJECT
done

# Loopback and already-established return traffic.
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DNS (needed to resolve the allowlist). Restrict to the container's resolver.
resolver="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
if [ -n "${resolver:-}" ]; then
  iptables -A OUTPUT -p udp --dport 53 -d "$resolver" -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -d "$resolver" -j ACCEPT
else
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
fi

# Resolve the allowlist to IPs and add them to the ipset.
for d in "${ALLOW_DOMAINS[@]}"; do
  for ip in $(getent ahostsv4 "$d" | awk '{print $1}' | sort -u); do
    ipset add allowed "$ip" 2>/dev/null || true
  done
done
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80  -m set --match-set allowed dst -j ACCEPT

# Default deny for everything else outbound.
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

echo "init-firewall: egress locked to $(ipset list allowed | grep -c '^[0-9]') allowlisted IPs; metadata services rejected."

# Smoke test: the metadata endpoint must NOT be reachable. Fail the container if it is.
if timeout 3 bash -c 'exec 3<>/dev/tcp/169.254.169.254/80' 2>/dev/null; then
  echo "init-firewall: FATAL: metadata endpoint reachable after firewall setup" >&2
  exit 1
fi
echo "init-firewall: verified metadata endpoint is unreachable."
