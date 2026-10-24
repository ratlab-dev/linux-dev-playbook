#!/usr/bin/env bash
# ==============================================================================
# Linux Devbox Playbook Orchestrator (scripts/run.sh)
#
# Runs Ansible playbooks from the Mac workstation with clean environment checks.
#
# Usage:
#   ./scripts/run.sh [playbook|tag] [extra ansible args...]
#
# Examples:
#   ./scripts/run.sh                       # Runs default full devbox provisioning
#   ./scripts/run.sh devbox                # Runs playbooks/devbox.yml
#   ./scripts/run.sh baseline              # Runs playbooks/baseline.yml
#   ./scripts/run.sh tailscale             # Runs playbooks/tailscale_onboard.yml
#   ./scripts/run.sh dns                   # Runs devbox with --tags dns
#   ./scripts/run.sh openbao               # Runs devbox with --tags openbao
#   ./scripts/run.sh verify                # Runs devbox with --tags verify
#   ./scripts/run.sh cleanup               # Runs playbooks/cleanup.yml (tools/packages/services)
#   ./scripts/run.sh cleanup -e "cleanup_data=true"  # Runs cleanup including persistent data
#   ./scripts/run.sh check                 # Tests SSH and Tailscale connectivity
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

EXTRA_ARGS=()
TARGET="${1:-devbox}"
shift || true

# Check Ansible installation
if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} ansible-playbook is not installed on this workstation."
    echo "Install it via: brew install ansible"
    exit 1
fi

case "${TARGET}" in
    devbox|all)
        PLAYBOOK="playbooks/devbox.yml"
        EXTRA_ARGS=("$@")
        ;;
    baseline)
        PLAYBOOK="playbooks/baseline.yml"
        EXTRA_ARGS=("$@")
        ;;
    tailscale|onboard)
        PLAYBOOK="playbooks/tailscale_onboard.yml"
        EXTRA_ARGS=("$@")
        ;;
    cleanup|revert)
        PLAYBOOK="playbooks/cleanup.yml"
        EXTRA_ARGS=("$@")
        ;;
    check|ping)
        echo -e "${BLUE}[INFO]${NC} Testing connectivity to devbox..."
        ansible devbox -i inventory/hosts.ini -m ping
        exit 0
        ;;
    dns|openbao|gitea|harbor|docker|verify|ca)
        PLAYBOOK="playbooks/devbox.yml"
        EXTRA_ARGS=("--tags" "${TARGET}" "$@")
        ;;
    *)
        if [[ -f "playbooks/${TARGET}.yml" ]]; then
            PLAYBOOK="playbooks/${TARGET}.yml"
            EXTRA_ARGS=("$@")
        elif [[ -f "${TARGET}" ]]; then
            PLAYBOOK="${TARGET}"
            EXTRA_ARGS=("$@")
        else
            echo -e "${YELLOW}[NOTE]${NC} Treating '${TARGET}' as tag on devbox.yml"
            PLAYBOOK="playbooks/devbox.yml"
            EXTRA_ARGS=("--tags" "${TARGET}" "$@")
        fi
        ;;
esac

echo "================================================================================"
echo -e "${BLUE}[INFO]${NC} Executing Playbook: ${PLAYBOOK}"
if [[ ${#EXTRA_ARGS[@]:-0} -gt 0 ]]; then
    echo -e "${BLUE}[INFO]${NC} Extra Arguments:    ${EXTRA_ARGS[*]}"
fi
echo "================================================================================"

ansible-playbook -i inventory/hosts.ini "${PLAYBOOK}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
