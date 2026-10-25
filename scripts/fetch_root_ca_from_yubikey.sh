#!/usr/bin/env bash
# ==============================================================================
# fetch_root_ca_from_yubikey.sh
# Reads the Root CA certificate from a connected YubiKey (PIV slot 9c or 9a)
# and writes it in PEM format to files/certs/ratlab-root-ca.crt
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_FILE="${1:-${REPO_ROOT}/files/certs/ratlab-root-ca.crt}"

mkdir -p "$(dirname "${OUTPUT_FILE}")"

# If output file already exists, is non-empty, and valid, nothing to do
if [ -s "${OUTPUT_FILE}" ]; then
  if openssl x509 -in "${OUTPUT_FILE}" -noout >/dev/null 2>&1; then
    echo "Root CA certificate already exists and is valid: ${OUTPUT_FILE}"
    exit 0
  fi
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

fetch_cert() {
  if command -v ykman >/dev/null 2>&1; then
    for slot in 9c 9a; do
      if ykman piv certificates export "$slot" - 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        ykman piv certificates export "$slot" "${OUTPUT_FILE}"
        return 0
      fi
    done
  fi

  if command -v yubico-piv-tool >/dev/null 2>&1; then
    for slot in 9c 9a; do
      if yubico-piv-tool -a read-certificate -s "$slot" 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        yubico-piv-tool -a read-certificate -s "$slot" -o "${OUTPUT_FILE}"
        return 0
      fi
    done
  fi

  return 1
}

if fetch_cert; then
  echo "Successfully fetched Root CA certificate from YubiKey to ${OUTPUT_FILE}"
  chmod 644 "${OUTPUT_FILE}"
  exit 0
else
  echo "Error: Could not fetch Root CA certificate from YubiKey. Ensure YubiKey is connected with PIV slot 9c or 9a initialized." >&2
  exit 1
fi
