#!/usr/bin/env bash
# ==============================================================================
# Download official cert-manager & trust-manager Helm charts and upload to Harbor
# ==============================================================================

set -euo pipefail

export PATH="/usr/local/bin:$PATH"

HELM_BIN="${HELM_BIN:-$(which helm 2>/dev/null || echo /usr/local/bin/helm)}"
if ! command -v "${HELM_BIN}" >/dev/null 2>&1 && [ ! -x "${HELM_BIN}" ]; then
  echo "Error: Helm CLI is not installed or not executable at '${HELM_BIN}'." >&2
  exit 127
fi

CERT_MANAGER_VERSION="${1:-v1.21.3}"
TRUST_MANAGER_VERSION="${2:-v0.26.0}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-registry.ratlab.dev:8443}"
HARBOR_PROJECT="${HARBOR_PROJECT:-library}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-admin}"

TMP_DIR=$(mktemp -d /tmp/cert-manager-helm-XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "=== [1/3] Downloading cert-manager (${CERT_MANAGER_VERSION}) & trust-manager (${TRUST_MANAGER_VERSION}) ==="
cd "${TMP_DIR}"
"${HELM_BIN}" pull oci://quay.io/jetstack/charts/cert-manager --version "${CERT_MANAGER_VERSION}"
"${HELM_BIN}" pull oci://quay.io/jetstack/charts/trust-manager --version "${TRUST_MANAGER_VERSION}"

echo "=== [2/3] Authenticating with Harbor OCI registry (${HARBOR_REGISTRY}) ==="
echo "${HARBOR_PASS}" | "${HELM_BIN}" registry login "${HARBOR_REGISTRY}" \
  --username "${HARBOR_USER}" \
  --password-stdin \
  --insecure

echo "=== [3/3] Uploading charts to Harbor OCI (oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}) ==="
for pkg in *.tgz; do
  "${HELM_BIN}" push "${pkg}" "oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}" --insecure-skip-tls-verify
  echo "[OK] Successfully pushed ${pkg}"
done
