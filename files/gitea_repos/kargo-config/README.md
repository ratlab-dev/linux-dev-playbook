# Kargo Pipelines Configuration

This repository houses declarative Kargo Custom Resources (`Project`, `Warehouse`, `Stage`) governing the continuous promotion of application artifacts across the Ratlab platform.

## Architecture

- **Project**: `commit-echoer`
- **Warehouse**: Subscribes to:
  - Container images from Harbor OCI registry: `registry.ratlab.dev:8443/library/commit-echoer` (selection strategy `NewestBuild`, filtering for commit sha tags).
  - Helm chart packages from Harbor OCI registry: `registry.ratlab.dev:8443/library/generic-app` (semantic version constraint `^0.1.0` allowing automatic minor and patch upgrades).
- **Stage**: `live` (with `autoPromotionEnabled: true`)
  - Automatically checks out the GitOps repository (`admin/gitops.git`).
  - Updates `apps/commit-echoer/images.yaml` with the new commit sha image tag.
  - Updates `applicationsets/commit-echoer.yaml` with the new Helm chart version when applicable.
  - Commits and pushes changes directly to `gitops.git`.
  - Dispatches sync notification to Argo CD.
