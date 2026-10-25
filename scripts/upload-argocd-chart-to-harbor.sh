#!/usr/bin/env bash
# ==============================================================================
# Download official ArgoCD Helm chart and upload to Harbor OCI Registry
# ==============================================================================

set -euo pipefail

export PATH="/usr/local/bin:$PATH"

HELM_BIN="${HELM_BIN:-$(which helm 2>/dev/null || echo /usr/local/bin/helm)}"
if ! command -v "${HELM_BIN}" >/dev/null 2>&1 && [ ! -x "${HELM_BIN}" ]; then
  echo "Error: Helm CLI is not installed or not executable at '${HELM_BIN}'." >&2
  exit 127
fi

CHART_VERSION="${1:-}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-registry.ratlab.dev:8443}"
HARBOR_PROJECT="${HARBOR_PROJECT:-library}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-admin}"

TMP_DIR=$(mktemp -d /tmp/argocd-helm-XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "=== [1/4] Adding official Argo Helm repository ==="
"${HELM_BIN}" repo add argo https://argoproj.github.io/argo-helm
"${HELM_BIN}" repo update argo

echo "=== [2/4] Downloading ArgoCD chart ==="
cd "${TMP_DIR}"
if [ -n "${CHART_VERSION}" ]; then
  "${HELM_BIN}" pull argo/argo-cd --version "${CHART_VERSION}"
else
  "${HELM_BIN}" pull argo/argo-cd
fi

CHART_PACKAGE=$(ls argo-cd-*.tgz 2>/dev/null || true)
if [ -z "${CHART_PACKAGE}" ]; then
  echo "Error: Failed to find downloaded chart package." >&2
  exit 1
fi
echo "Downloaded: ${CHART_PACKAGE}"

ACTUAL_VERSION=$(echo "${CHART_PACKAGE}" | sed -E 's/argo-cd-(.*)\.tgz/\1/')

echo "=== [3/4] Authenticating with Harbor OCI registry (${HARBOR_REGISTRY}) ==="
MAX_RETRIES=5
for i in $(seq 1 $MAX_RETRIES); do
  if echo "${HARBOR_PASS}" | "${HELM_BIN}" registry login "${HARBOR_REGISTRY}" \
    --username "${HARBOR_USER}" \
    --password-stdin \
    --insecure; then
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "Failed to authenticate with Harbor registry after $MAX_RETRIES attempts" >&2
    exit 1
  fi
  echo "Registry authentication attempt $i failed, retrying in 3 seconds..."
  sleep 3
done

echo "=== [4/4] Uploading chart to oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT} ==="
if "${HELM_BIN}" push "${CHART_PACKAGE}" "oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}"; then
  echo ""
  echo "Successfully published argo-cd:${ACTUAL_VERSION} to oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}/argo-cd"
else
  echo ""
  echo "ArgoCD chart version ${ACTUAL_VERSION} already published or push succeeded with warning"
fi
