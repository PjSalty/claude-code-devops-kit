# Devcontainer (layer L1, the hard boundary)

This is the recommended runtime and the only layer that makes the core guarantee hold
against an adversarial or injection-steered session. It works by **removing the
capability**, not by asking the model not to use it:

- **No credentials to read.** Only the workspace is mounted. `~/.aws`,
  `~/.config/gcloud`, `~/.kube`, and the rest are not present inside the container, so
  no tool, sandboxed or not, can read them.
- **No route to a cloud API.** `init-firewall.sh` sets default-deny egress with a small
  audited allowlist (Anthropic API, package registries, git host). Every cloud
  provider endpoint and the instance metadata service (`169.254.169.254`) are dropped,
  and the script fails the container start if the metadata endpoint is still reachable.

## Install

1. Put `devcontainer.json` and `init-firewall.sh` in your repo's `.devcontainer/`.
2. In your image build, copy `settings/managed-settings.json` to
   `/etc/claude-code/managed-settings.json` (root-owned) and the `hooks/` scripts to
   `/opt/claude-code-devops-kit/hooks/`, so the enforced policy and guards are present.
3. Open the repo in the container. `init-firewall.sh` runs on start.

## Review checklist for this container

- [ ] `mounts` adds no credential directory, and no `remoteEnv`/`containerEnv` carries
      a cloud credential or `KUBECONFIG`.
- [ ] `ALLOW_DOMAINS` in `init-firewall.sh` is minimal and none of it resolves or
      proxies to a cloud control plane.
- [ ] `NET_ADMIN` is used only by the firewall script and not needed by the workload.
- [ ] The managed settings file is present and root-owned inside the image.
- [ ] `../test/verify.sh` passes inside the container.

## Note on `--dangerously-skip-permissions`

Anthropic's reference devcontainer is the supported place to use
`--dangerously-skip-permissions`, because the container is already isolated. Even so,
for this kit keep `disableBypassPermissionsMode: "disable"` set in managed settings:
the egress firewall and the absent credentials are the boundary, and leaving the
in-app permission layer on costs nothing and keeps the guard hooks and deny rules
active as defense-in-depth.
