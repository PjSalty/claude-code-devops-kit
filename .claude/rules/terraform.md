---
description: Standards for authoring Terraform and OpenTofu
paths:
  - "**/*.tf"
  - "**/*.tofu"
  - "**/*.tfvars.example"
---

# Terraform / OpenTofu

- Pin `required_version` and every provider in `required_providers` to an exact
  version. Pin modules to an exact tag or commit. No unpinned or `>=`-only sources.
- Author only. Validate with `fmt`, `validate`, `tflint`, `checkov`. Do not run
  `apply`/`destroy`/`import`/`state`/`refresh`/`login`; those are blocked and are CI's
  job.
- Never read or write `*.tfstate`, `*.tfvars` (real ones), `~/.aws` and friends, or a
  backend's credentials. Example variables go in `*.tfvars.example` with placeholder
  values.
- Generated IAM and network rules follow least privilege: no `"*"` action or resource,
  and no `0.0.0.0/0`, without a comment stating why. Prefer scoped roles and specific
  CIDRs.
- Mark secret variables `sensitive = true` and source real values from a secret
  manager data source, never a literal in HCL.
- Keep the tree `terraform fmt`-clean.
