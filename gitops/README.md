# Ratlab GitOps Repository

This directory contains GitOps definitions for ArgoCD Application and ApplicationSets.
It is maintained in the local playbook workspace without git tracking, and synchronized into Gitea (`git.ratlab.dev:3000/admin/gitops.git`) by Ansible.

## Directory Structure
- `applicationsets/`
  - `cluster-namespaces.yaml`: ApplicationSet targeting all clusters deploying non-admin namespaces (Sync wave 0)
  - `tooling-apps.yaml`: ApplicationSet targeting clusters labeled `cluster-role: tooling`
  - `workload-apps.yaml`: ApplicationSet targeting clusters labeled `cluster-role: workload`
  - `metallb-engine.yaml`: ArgoCD Application deploying official MetalLB Helm chart from Harbor OCI (Sync wave 1)
  - `metallb-config.yaml`: Vanilla ArgoCD Application deploying IPAddressPool and L2Advertisement (Sync wave 5)
- `apps/`
  - `namespaces/`: Declarative non-admin namespace manifests (`metallb-system`, `argocd`, `guestbook`, `vault-secret-demo`)
  - `metallb/`: Base values for the MetalLB Helm chart (Layer 1)
  - `metallb-config/`: Vanilla manifests (`IPAddressPool`, `L2Advertisement`) (Layer 2)
  - `vault-secret-demo/`: Deployment demonstrating ServiceAccount vault trust (`<ns>/<sa>` -> `/apps/secrets/<ns>_<sa>`)
  - `guestbook/`: Standard guestbook application for workload clusters
