#!/usr/bin/env bash
# ==============================================================================
# sign_with_yubikey.sh
# Signs a Certificate Signing Request (CSR) using a YubiKey-backed Root CA
#
# Usage:
#   ./scripts/sign_with_yubikey.sh <input_csr> <output_crt> [days] [type]
#
# Examples:
#   # Sign server certificate (e.g. vault.ratlab.dev) for 2 years (730 days):
#   ./scripts/sign_with_yubikey.sh files/certs/openbao.csr files/certs/openbao.crt 730 server
#
#   # Sign intermediate CA for 5 years:
#   ./scripts/sign_with_yubikey.sh files/certs/intermediate.csr files/certs/intermediate.crt 1825 intermediate
# ==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INPUT_CSR="${1:-}"
OUTPUT_CRT="${2:-}"
DAYS="${3:-730}" # Default: 2 years (730 days)
TYPE="${4:-server}" # "server" or "intermediate"

if [[ -z "${INPUT_CSR}" || -z "${OUTPUT_CRT}" ]]; then
    echo -e "${RED}[ERROR]${NC} Usage: $0 <input_csr> <output_crt> [days] [type: server|intermediate]"
    exit 1
fi

if [[ ! -f "${INPUT_CSR}" ]]; then
    echo -e "${RED}[ERROR]${NC} CSR file not found: ${INPUT_CSR}"
    exit 1
fi

# Locate Root CA certificate
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CA_CRT=""
CANDIDATE_CAS=(
    "${REPO_ROOT}/files/certs/ratlab-root-ca.crt"
    "${REPO_ROOT}/../hobby-projects/yubikey-based-keys/root_ca.crt"
    "${REPO_ROOT}/../hobby-projects/vault-intermediary-ca/yubikey/root_ca.crt"
    "/Users/naugustin/work/hobby-projects/yubikey-based-keys/root_ca.crt"
)

for c in "${CANDIDATE_CAS[@]}"; do
    if [[ -f "$c" ]]; then
        CA_CRT="$c"
        break
    fi
done

if [[ -z "${CA_CRT}" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Root CA certificate not found on disk. Fetching from connected YubiKey..."
    if "${SCRIPT_DIR}/fetch_root_ca_from_yubikey.sh" "${REPO_ROOT}/files/certs/ratlab-root-ca.crt"; then
        CA_CRT="${REPO_ROOT}/files/certs/ratlab-root-ca.crt"
    fi
fi

if [[ -z "${CA_CRT}" || ! -f "${CA_CRT}" ]]; then
    echo -e "${RED}[ERROR]${NC} Root CA certificate (root_ca.crt / ratlab-root-ca.crt) not found and could not be retrieved from YubiKey."
    exit 1
fi

# Generate temporary OpenSSL PKCS#11 configuration
TEMP_CONF=$(mktemp /tmp/yubikey_openssl.XXXXXX.cnf)
TEMP_EXT=$(mktemp /tmp/yubikey_ext.XXXXXX.cnf)
trap 'rm -f "${TEMP_CONF}" "${TEMP_EXT}"' EXIT

cat << 'EOF' > "${TEMP_CONF}"
openssl_conf = openssl_init

[openssl_init]
engines = engine_section

[engine_section]
pkcs11 = pkcs11_section

[pkcs11_section]
engine_id = pkcs11
dynamic_path = /opt/homebrew/lib/engines-3/pkcs11.dylib
MODULE_PATH = /usr/local/lib/libykcs11.dylib
init = 0

[ req ]
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
EOF

if [[ "${TYPE}" == "intermediate" ]]; then
    cat << 'EOF' > "${TEMP_EXT}"
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
extendedKeyUsage = critical, serverAuth, clientAuth
nameConstraints = critical, permitted;DNS:ratlab.dev, permitted;DNS:.ratlab.dev
EOF
    EXT_SECTION="-extfile ${TEMP_EXT} -extensions v3_intermediate_ca"
else
    cat << 'EOF' > "${TEMP_EXT}"
[ v3_server ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF
    EXT_SECTION="-extfile ${TEMP_EXT} -extensions v3_server -copy_extensions copyall"
fi

echo -e "${BLUE}[INFO]${NC} Signing ${INPUT_CSR} using YubiKey Root CA..."
echo -e "${BLUE}[INFO]${NC} Target validity: ${DAYS} days (~$((DAYS / 365)) year(s))."
echo -e "${BLUE}[INFO]${NC} Using Root CA: ${CA_CRT}"
echo -e "${YELLOW}[ACTION REQUIRED]${NC} Please ensure your YubiKey is plugged in."

mkdir -p "$(dirname "${OUTPUT_CRT}")"

PIN_PARAM=""
if [[ -n "${YUBIKEY_PIN:-}" ]]; then
    KEY_URI="pkcs11:id=%02;type=private;pin-value=${YUBIKEY_PIN}"
else
    KEY_URI="pkcs11:id=%02;type=private"
    echo -e "${YELLOW}[NOTE]${NC} You will be prompted to enter your YubiKey PIV PIN below:"
fi

# Execute OpenSSL PKCS#11 signing
OPENSSL_CONF="${TEMP_CONF}" openssl x509 \
    -engine pkcs11 \
    -CA "${CA_CRT}" \
    -CAform PEM \
    -CAkey "${KEY_URI}" \
    -CAkeyform engine \
    -req -in "${INPUT_CSR}" \
    -out "${OUTPUT_CRT}" \
    -days "${DAYS}" \
    ${EXT_SECTION}

if [[ $? -eq 0 && -s "${OUTPUT_CRT}" ]]; then
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "${OUTPUT_CRT}" | cut -d= -f2)
    echo -e "${GREEN}[SUCCESS]${NC} Certificate signed successfully!"
    echo -e "${GREEN}[SUCCESS]${NC} Saved to: ${OUTPUT_CRT}"
    echo -e "${GREEN}[SUCCESS]${NC} Valid until: ${EXPIRY_DATE}"
else
    echo -e "${RED}[ERROR]${NC} Signing failed. Verify that YubiKey is connected, slot 9c is initialized, and PIN is correct."
    exit 1
fi
