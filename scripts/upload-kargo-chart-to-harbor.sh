#!/usr/bin/env bash
# ==============================================================================
# Download official Kargo Helm chart and upload to Harbor OCI Registry
# ==============================================================================

set -euo pipefail

export PATH="/usr/local/bin:$PATH"

HELM_BIN="${HELM_BIN:-$(which helm 2>/dev/null || echo /usr/local/bin/helm)}"
if ! command -v "${HELM_BIN}" >/dev/null 2>&1 && [ ! -x "${HELM_BIN}" ]; then
  echo "Error: Helm CLI is not installed or not executable at '${HELM_BIN}'." >&2
  exit 127
fi

CHART_VERSION="${1:-1.12.5}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-registry.ratlab.dev:8443}"
HARBOR_PROJECT="${HARBOR_PROJECT:-library}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-admin}"

TMP_DIR=$(mktemp -d /tmp/kargo-helm-XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "=== [1/3] Downloading official Kargo chart from GHCR OCI ==="
cd "${TMP_DIR}"
if [ -n "${CHART_VERSION}" ]; then
  "${HELM_BIN}" pull oci://ghcr.io/akuity/kargo-charts/kargo --version "${CHART_VERSION}"
else
  "${HELM_BIN}" pull oci://ghcr.io/akuity/kargo-charts/kargo
fi

CHART_PACKAGE=$(ls kargo-*.tgz 2>/dev/null || true)
if [ -z "${CHART_PACKAGE}" ]; then
  echo "Error: Failed to find downloaded chart package." >&2
  exit 1
fi
echo "Downloaded: ${CHART_PACKAGE}"

echo "=== [2/3] Authenticating with Harbor OCI registry (${HARBOR_REGISTRY}) ==="
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

echo "=== [3/3] Uploading Kargo chart to Harbor OCI (oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}) ==="
"${HELM_BIN}" push "${CHART_PACKAGE}" "oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}" --insecure-skip-tls-verify

echo "[OK] Successfully published Kargo Helm chart (${CHART_PACKAGE}) to oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}/kargo"
