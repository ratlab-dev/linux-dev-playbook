#!/usr/bin/env bash
# ==============================================================================
# Linux Devbox End-to-End Verification (scripts/verify.sh)
#
# Runs comprehensive verification tests from the Mac workstation.
#
# Usage:
#   ./scripts/verify.sh [target_ip_or_host]
# ==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TARGET="${1:-100.80.98.27}"

echo "================================================================================"
echo "                  DEVBOX REMOTE VERIFICATION SUITE                              "
echo "================================================================================"
echo "Target: ${TARGET}"
echo ""

# 1. Ping / Reachability
echo -e "${BLUE}[1/5] Testing Tailscale Reachability...${NC}"
if ping -c 1 -W 2 "${TARGET}" >/dev/null 2>&1; then
    echo -e "  ${GREEN}[PASS]${NC} ICMP ping to ${TARGET} succeeded."
else
    echo -e "  ${RED}[FAIL]${NC} Cannot ping ${TARGET}."
fi

# 2. SSH Connectivity
echo -e "${BLUE}[2/5] Testing SSH Access...${NC}"
if ssh -o BatchMode=yes -o ConnectTimeout=3 "root@${TARGET}" "echo OK" >/dev/null 2>&1; then
    echo -e "  ${GREEN}[PASS]${NC} Root SSH key access verified."
else
    echo -e "  ${RED}[FAIL]${NC} Root SSH access failed."
fi

# 3. DNS Resolution on target dnsmasq
echo -e "${BLUE}[3/5] Testing DNS Resolution on devbox (Port 53)...${NC}"
DOMAINS=("devbox.ratlab.dev" "vault.ratlab.dev" "git.ratlab.dev" "harbor.ratlab.dev" "wildcard-test.ratlab.dev")
for d in "${DOMAINS[@]}"; do
    IP=$(dig "@${TARGET}" "${d}" +short 2>/dev/null | tail -n 1 || true)
    if [[ -n "${IP}" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} ${d} -> ${IP}"
    else
        echo -e "  ${RED}[FAIL]${NC} ${d} did not resolve."
    fi
done

# 4. Root CA Trust Verification on devbox
echo -e "${BLUE}[4/5] Testing Root CA OS Trust on devbox...${NC}"
CA_CHECK=$(ssh -o BatchMode=yes "root@${TARGET}" "openssl verify /usr/local/share/ca-certificates/custom/ratlab-root-ca.crt 2>&1" || true)
if echo "${CA_CHECK}" | grep -q "OK"; then
    echo -e "  ${GREEN}[PASS]${NC} ratlab.dev Root CA is trusted in devbox system store."
else
    echo -e "  ${RED}[FAIL]${NC} Root CA trust check returned: ${CA_CHECK}"
fi

# 5. Service Status Check
echo -e "${BLUE}[5/5] Checking Services on devbox...${NC}"
SERVICES=("tailscaled" "dnsmasq" "docker" "openbao" "gitea" "harbor")
for s in "${SERVICES[@]}"; do
    STATUS=$(ssh -o BatchMode=yes "root@${TARGET}" "systemctl is-active ${s} 2>/dev/null || true" | tr -d '\r\n')
    if [[ -z "${STATUS}" ]]; then
        STATUS="inactive"
    fi
    if [[ "${STATUS}" == "active" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} Service '${s}' is active."
    else
        echo -e "  ${YELLOW}[INFO]${NC} Service '${s}' is ${STATUS}."
    fi
done

echo ""
echo "================================================================================"
echo -e "${GREEN}[DONE]${NC} Verification suite completed."
echo "================================================================================"
