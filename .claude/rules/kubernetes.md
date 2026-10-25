---
description: Standards for authoring Kubernetes manifests, Kustomize, and Helm
paths:
  - "**/*.yaml"
  - "**/*.yml"
  - "**/Chart.yaml"
  - "**/kustomization.yaml"
---

# Kubernetes / Kustomize / Helm

- Author and render offline: `kustomize build`, `helm template`, `helm lint`,
  validate with `kubeconform -strict`. Never `kubectl`/`oc`/`argocd`/`flux` or
  `helm install`/`upgrade`; those touch a cluster and are blocked.
- Never read a kubeconfig (`~/.kube`) or a cluster secret.
- Pin container images by digest or an exact tag; never `latest`.
- Every workload sets resource `requests` and `limits`, `livenessProbe` and
  `readinessProbe`, and a hardened `securityContext`: `runAsNonRoot: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, and
  `readOnlyRootFilesystem: true` where the app allows it.
- Reference secrets from a `Secret` or an external-secrets resource. Never inline a
  secret value in a manifest or a Helm values file.
- Add a `NetworkPolicy` when introducing workloads to a namespace.
