---
name: local-validation
description: Validate infrastructure code locally and offline before committing. Use when the user asks to check, lint, validate, or pre-flight Terraform/OpenTofu, Kubernetes/Kustomize/Helm, Dockerfiles, or CI pipeline files, or before opening a PR. Runs only tools that need no network and no credentials.
---

# Local, offline validation

Run the checks that apply to what changed. All are offline and need no credentials.
Report each as PASS or FAIL with the command, and show the output of any failure
rather than summarizing it as passing.

## Terraform / OpenTofu
```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
tflint --recursive
checkov -d . --compact
```
Never `apply`, `destroy`, `import`, `state`, or `refresh`. A plan, if needed, is
`terraform plan -refresh=false -lock=false` against a local/example backend only.

## Kubernetes / Kustomize / Helm
```bash
kustomize build path/ | kubeconform -strict -summary
helm template release chart/ | kubeconform -strict -summary
helm lint chart/
yamllint .
```

## Containers
```bash
hadolint Dockerfile
docker build -t localcheck:dev .   # local build only, never push/login
```

## CI pipelines
```bash
actionlint          # GitHub Actions
yamllint .gitlab-ci.yml
conftest test .     # if you keep OPA policies
```

## Before a PR
1. Run the checks above for the changed file types.
2. `git diff` and confirm the change matches the intent and nothing wider.
3. Confirm no secret, state file, or `*.tfvars` is staged (`git diff --cached --name-only`).

If a check needs a tool that is not installed, say so (mark it ENV, not PASS) rather
than skipping silently.
