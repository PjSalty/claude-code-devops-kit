---
description: Standards for Dockerfiles and CI/CD pipeline definitions
paths:
  - "**/Dockerfile"
  - "**/Dockerfile.*"
  - "**/Containerfile"
  - ".github/workflows/**"
  - "**/.gitlab-ci.yml"
  - "**/azure-pipelines.yml"
  - "**/.circleci/config.yml"
---

# Containers and CI/CD

## Dockerfiles
- Pin the base image by digest (`FROM image@sha256:...`) or an exact tag.
- Multi-stage build; final stage runs as a non-root `USER` with a minimal image.
- No secret in a build arg or layer; no `curl | sh` of an unpinned script.
- Validate with `hadolint`. A local `docker build` for a syntax check is fine; never
  `push`, `login`, or `pull` from a private registry.

## Pipelines
- The pipeline is what deploys, in CI, with CI's own short-lived credentials. The
  assistant writes the pipeline; it does not run deploy steps locally.
- Pin every action/orb/image to a commit SHA or exact version.
- Prefer OIDC-federated, short-lived cloud credentials over stored long-lived keys.
- Scope job permissions to the minimum (for example GitHub `permissions:` per job,
  default `contents: read`).
- Never echo a secret, and never write one into a log, artifact, or cache.
- Validate with `actionlint` / `yamllint`; keep them clean.
