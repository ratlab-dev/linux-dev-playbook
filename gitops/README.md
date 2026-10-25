# Ratlab GitOps Repository

This directory contains GitOps manifests for ArgoCD.
Ansible pushes these files to Gitea at git.ratlab.dev.

## Cluster Architecture

The environment runs a single giant Kind cluster.
The cluster is named giant-cluster.
It has one control plane node and two worker nodes.
It runs both platform tools and application workloads.

## Directory Structure

### applicationsets/
- cluster-namespaces.yaml: Creates non-admin namespaces on the cluster.
- jenkins-rbac.yaml: Deploys ServiceAccount, Role, and RoleBinding for Jenkins ephemeral agents.
- tooling-apps.yaml: Deploys platform tools like vault-secret-demo.
- workload-apps.yaml: Deploys user workloads like guestbook.
- metallb-engine.yaml: Deploys the MetalLB operator from Harbor.
- metallb-config.yaml: Configures the MetalLB address pool.

### apps/
- namespaces/: Manifests for namespaces (including jenkins-agents).
- jenkins-rbac/: ServiceAccount, Role, and RoleBinding for Jenkins ephemeral agents.
- metallb/: Helm values for MetalLB.
- metallb-config/: IPAddressPool and L2Advertisement manifests.
- vault-secret-demo/: Demo application for Vault secrets.
- guestbook/: Sample guestbook application.
