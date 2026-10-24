#!/usr/bin/env bash
# ==============================================================================
# Linux Devbox Cleanup & State Reversal Orchestrator
#
# Cleans up and uninstalls all tools, binaries, systemd units, apt packages,
# and reverse proxy configurations in REVERSE order of creation:
#   (ArgoCD/Kind -> Harbor -> Gitea -> OpenBao -> Nginx -> Docker -> DNS -> hosts).
#
# DATA PRESERVATION:
#   Persistent data directories (/data/harbor, /var/lib/gitea, /var/lib/openbao,
#   /root/.kube, etc.) are PRESERVED by default.
#   To purge data explicitly, pass: --with-data or --include-data.
#
# SSH and Tailscale configurations are explicitly PRESERVED to maintain access.
#
# Usage:
#   ./scripts/cleanup-devbox.sh [step|all] [flags...]
#
# Available steps:
#   all             Run all cleanup steps in reverse order (default)
#   argocd|kind     Step 1: Revert Kind clusters, ArgoCD, K8s binaries & proxies
#   harbor          Step 2: Revert Harbor registry, systemd service & scripts
#   gitea           Step 3: Revert Gitea service, binary & user
#   openbao|vault   Step 4: Revert OpenBao service, binary, apt package & PKI
#   nginx           Step 5: Revert Nginx service, configurations & apt package
#   docker          Step 6: Revert Docker containers, service, apt package & repos
#   dns             Step 7: Revert dnsmasq service, apt package, CLI & restore stub
#   hosts           Step 8: Clean up custom ratlab.dev records from /etc/hosts
#
# Optional flags:
#   --with-data          Explicitly PURGE persistent data (/data/harbor, /var/lib/*)
#   --include-data       Alias for --with-data
#   --remote             Execute this cleanup remotely on devbox via Ansible
#   --include-tailscale  Explicitly tear down Tailscale (WARNING: drops remote SSH)
#   --include-ssh        Explicitly tear down custom SSH configuration
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET_STEP=""
REMOTE_MODE=false
INCLUDE_DATA=false
INCLUDE_TAILSCALE=false
INCLUDE_SSH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            REMOTE_MODE=true
            shift
            ;;
        --with-data|--include-data)
            INCLUDE_DATA=true
            shift
            ;;
        --include-tailscale)
            INCLUDE_TAILSCALE=true
            shift
            ;;
        --include-ssh)
            INCLUDE_SSH=true
            shift
            ;;
        -h|--help)
            sed -ne '/^#/!q;s/^# //;2,$p' "$0"
            exit 0
            ;;
        *)
            TARGET_STEP="$1"
            shift
            ;;
    esac
done

TARGET_STEP="${TARGET_STEP:-all}"

# If running on macOS (or --remote requested), delegate to target via Ansible
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$REMOTE_MODE" == true ]]; then
    echo -e "${BLUE}[INFO]${NC} Running cleanup remotely on devbox via Ansible..."
    cd "${REPO_ROOT}"

    EXTRA_VARS=()
    if [[ "$INCLUDE_DATA" == true ]]; then
        EXTRA_VARS+=("-e" "cleanup_data=true")
    fi

    TAG_ARGS=()
    case "${TARGET_STEP}" in
        argocd|kind|kind_cluster)
            TAG_ARGS+=("--tags" "k8s")
            ;;
        harbor)
            TAG_ARGS+=("--tags" "harbor")
            ;;
        gitea)
            TAG_ARGS+=("--tags" "gitea")
            ;;
        openbao|vault)
            TAG_ARGS+=("--tags" "openbao")
            ;;
        nginx)
            TAG_ARGS+=("--tags" "nginx")
            ;;
        docker)
            TAG_ARGS+=("--tags" "docker")
            ;;
        dns)
            TAG_ARGS+=("--tags" "dns")
            ;;
        hosts)
            TAG_ARGS+=("--tags" "hosts")
            ;;
        tailscale)
            TAG_ARGS+=("--tags" "tailscale")
            ;;
        ssh)
            TAG_ARGS+=("--tags" "ssh")
            ;;
        all)
            ;;
    esac

    ansible-playbook -i inventory/hosts.ini playbooks/cleanup.yml \
        ${TAG_ARGS[@]+"${TAG_ARGS[@]}"} \
        ${EXTRA_VARS[@]+"${EXTRA_VARS[@]}"}
    exit 0
fi

# ==============================================================================
# Local Execution (runs directly on devbox as root)
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This cleanup script must be run as root (or via sudo)." >&2
    exit 1
fi

log_step() {
    echo -e "\n${BLUE}======================================================================${NC}"
    echo -e "${GREEN}>> [CLEANUP] $1${NC}"
    echo -e "${BLUE}======================================================================${NC}"
}

# ------------------------------------------------------------------------------
# STEP 1: Revert ArgoCD & Kind Kubernetes Clusters
# ------------------------------------------------------------------------------
cleanup_argocd_kind() {
    log_step "Step 1: Reverting ArgoCD, Kind Clusters & K8s Binaries"

    # Delete Kind clusters in reverse order
    for cluster in app-cluster-2 app-cluster-1 tooling-cluster; do
        if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q "^${cluster}\$"; then
            echo "Deleting Kind cluster: ${cluster}..."
            kind delete cluster --name "${cluster}" || true
        fi
    done

    # Remove temporary caches and cluster manifests
    echo "Removing temporary GitOps caches and cluster configs..."
    rm -rf /tmp/gitops-init /etc/kubernetes/kind /etc/kubernetes/tls

    # Remove Kubernetes binaries
    echo "Removing Kubernetes binaries (kind, kubectl, helm, kubectx, kubens)..."
    rm -f /usr/local/bin/kind /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/kubectx /usr/local/bin/kubens

    # Remove K8s & ArgoCD Nginx reverse proxies
    echo "Removing Nginx reverse proxy configs for Kind & ArgoCD..."
    rm -f /etc/nginx/sites-enabled/k8s-*.conf /etc/nginx/sites-available/k8s-*.conf
    rm -f /etc/nginx/sites-enabled/argocd.conf /etc/nginx/sites-available/argocd.conf
    rm -f /etc/nginx/conf.d/websocket-map.conf
    rm -f /etc/dnsmasq.hosts.d/argocd.hosts
    if systemctl is-active --quiet nginx 2>/dev/null; then
        nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    fi

    # Persistent Data (explicit flag only)
    if [[ "$INCLUDE_DATA" == true ]]; then
        echo -e "${RED}[DATA] Purging Kubeconfig and persistent Kubernetes data...${NC}"
        rm -rf /root/.kube /etc/kubernetes
    else
        echo -e "${YELLOW}[DATA PRESERVED] Kubeconfig (/root/.kube) was kept intact.${NC}"
    fi

    echo -e "${GREEN}[OK] Step 1 complete: Kind clusters, ArgoCD and K8s binaries removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 2: Revert Harbor Container Registry
# ------------------------------------------------------------------------------
cleanup_harbor() {
    log_step "Step 2: Reverting Harbor Registry & Helper Scripts"

    if systemctl is-enabled --quiet harbor 2>/dev/null || systemctl is-active --quiet harbor 2>/dev/null; then
        echo "Stopping and disabling harbor.service..."
        systemctl stop harbor 2>/dev/null || true
        systemctl disable harbor 2>/dev/null || true
    fi

    if [[ -d /opt/harbor ]] && command -v docker >/dev/null 2>&1; then
        echo "Tearing down Harbor Docker Compose stack..."
        (cd /opt/harbor && docker compose down --remove-orphans 2>/dev/null || true)
    fi

    echo "Removing Harbor systemd unit and scripts..."
    rm -f /etc/systemd/system/harbor.service
    systemctl daemon-reload

    rm -rf /opt/harbor /etc/harbor /var/log/harbor
    rm -f /etc/dnsmasq.hosts.d/harbor.hosts
    rm -f /usr/local/bin/upload-metallb-chart-to-harbor
    rm -f /usr/local/bin/upload-argocd-chart-to-harbor

    # Persistent Data (explicit flag only)
    if [[ "$INCLUDE_DATA" == true ]]; then
        echo -e "${RED}[DATA] Purging Harbor registry storage (/data/harbor)...${NC}"
        rm -rf /data/harbor
    else
        echo -e "${YELLOW}[DATA PRESERVED] Harbor data (/data/harbor) was kept intact.${NC}"
    fi

    echo -e "${GREEN}[OK] Step 2 complete: Harbor service and installation removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 3: Revert Gitea Service
# ------------------------------------------------------------------------------
cleanup_gitea() {
    log_step "Step 3: Reverting Gitea Git Service & Binary"

    if systemctl is-enabled --quiet gitea 2>/dev/null || systemctl is-active --quiet gitea 2>/dev/null; then
        echo "Stopping and disabling gitea.service..."
        systemctl stop gitea 2>/dev/null || true
        systemctl disable gitea 2>/dev/null || true
    fi

    echo "Removing Gitea systemd unit and binary..."
    rm -f /etc/systemd/system/gitea.service
    rm -f /usr/local/bin/gitea
    systemctl daemon-reload

    echo "Removing Gitea configurations and host records..."
    rm -rf /etc/gitea /var/log/gitea
    rm -f /etc/dnsmasq.hosts.d/gitea.hosts

    if id git >/dev/null 2>&1; then
        echo "Removing git system user..."
        userdel git 2>/dev/null || true
        groupdel git 2>/dev/null || true
    fi

    # Persistent Data (explicit flag only)
    if [[ "$INCLUDE_DATA" == true ]]; then
        echo -e "${RED}[DATA] Purging Gitea repositories and database (/var/lib/gitea)...${NC}"
        rm -rf /var/lib/gitea
    else
        echo -e "${YELLOW}[DATA PRESERVED] Gitea repositories (/var/lib/gitea) were kept intact.${NC}"
    fi

    echo -e "${GREEN}[OK] Step 3 complete: Gitea service and binary removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 4: Revert OpenBao (Vault) & PKI
# ------------------------------------------------------------------------------
cleanup_openbao() {
    log_step "Step 4: Reverting OpenBao (Vault), Binary & APT Package"

    if systemctl is-enabled --quiet openbao 2>/dev/null || systemctl is-active --quiet openbao 2>/dev/null; then
        echo "Stopping and disabling openbao.service..."
        systemctl stop openbao 2>/dev/null || true
        systemctl disable openbao 2>/dev/null || true
    fi

    echo "Killing any lingering OpenBao processes..."
    pkill -9 -f "bao server" 2>/dev/null || pkill -9 bao 2>/dev/null || true

    echo "Removing OpenBao systemd unit and binaries..."
    rm -f /etc/systemd/system/openbao.service
    rm -f /usr/bin/bao /usr/bin/vault /usr/local/bin/issue-service-cert
    rm -f /etc/nginx/sites-enabled/vault.ratlab.dev.conf /etc/nginx/sites-available/vault.ratlab.dev.conf
    rm -f /etc/dnsmasq.hosts.d/openbao.hosts
    systemctl daemon-reload

    echo "Uninstalling OpenBao APT package and repository..."
    apt-get purge -y openbao 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/openbao.sources /etc/apt/sources.list.d/openbao.list /etc/apt/keyrings/openbao.asc

    echo "Removing OpenBao configuration and PKI certificates..."
    rm -rf /etc/openbao
    rm -f /etc/ssl/certs/ratlab_wildcard.crt /etc/ssl/private/ratlab_wildcard.key

    if id openbao >/dev/null 2>&1; then
        echo "Removing openbao system user..."
        userdel openbao 2>/dev/null || true
        groupdel openbao 2>/dev/null || true
    fi

    # Persistent Data (explicit flag only)
    if [[ "$INCLUDE_DATA" == true ]]; then
        echo -e "${RED}[DATA] Purging OpenBao data and tokens (/var/lib/openbao)...${NC}"
        rm -rf /var/lib/openbao /root/.openbao_init.json
    else
        echo -e "${YELLOW}[DATA PRESERVED] OpenBao data (/var/lib/openbao) was kept intact.${NC}"
    fi

    echo -e "${GREEN}[OK] Step 4 complete: OpenBao service, package and binaries removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 5: Revert Nginx Reverse Proxy
# ------------------------------------------------------------------------------
cleanup_nginx() {
    log_step "Step 5: Reverting Nginx Service & APT Package"

    if systemctl is-enabled --quiet nginx 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null; then
        echo "Stopping and disabling nginx.service..."
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
    fi

    echo "Purging Nginx package and configuration files..."
    apt-get purge -y nginx nginx-common nginx-core 2>/dev/null || true
    rm -rf /etc/nginx

    echo -e "${GREEN}[OK] Step 5 complete: Nginx service and package removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 6: Revert Docker CE & Tooling
# ------------------------------------------------------------------------------
cleanup_docker() {
    log_step "Step 6: Reverting Docker Containers, Services & APT Packages"

    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
        RUNNING_CONTAINERS=$(docker ps -aq 2>/dev/null || true)
        if [[ -n "${RUNNING_CONTAINERS}" ]]; then
            echo "Stopping and removing active Docker containers..."
            docker rm -f ${RUNNING_CONTAINERS} >/dev/null 2>&1 || true
        fi
        docker network prune -f >/dev/null 2>&1 || true
    fi

    echo "Stopping and disabling Docker and containerd services..."
    systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
    systemctl disable docker.socket docker.service containerd.service 2>/dev/null || true

    echo "Uninstalling Docker CE packages and removing repositories..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc /etc/docker/daemon.json

    # Persistent Data (explicit flag only)
    if [[ "$INCLUDE_DATA" == true ]]; then
        echo -e "${RED}[DATA] Purging Docker volumes and storage (/var/lib/docker)...${NC}"
        rm -rf /var/lib/docker /var/lib/containerd
    else
        echo -e "${YELLOW}[DATA PRESERVED] Docker storage (/var/lib/docker) was kept intact.${NC}"
    fi

    echo -e "${GREEN}[OK] Step 6 complete: Docker CE services, packages and configs removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 7: Revert DNS Server (dnsmasq)
# ------------------------------------------------------------------------------
cleanup_dns() {
    log_step "Step 7: Reverting dnsmasq Service, CLI Utility & APT Package"

    if systemctl is-enabled --quiet dnsmasq 2>/dev/null || systemctl is-active --quiet dnsmasq 2>/dev/null; then
        echo "Stopping and disabling dnsmasq.service..."
        systemctl stop dnsmasq 2>/dev/null || true
        systemctl disable dnsmasq 2>/dev/null || true
    fi

    echo "Removing dnsmasq configurations, ratlab-dns CLI and host records..."
    rm -rf /etc/dnsmasq.conf /etc/dnsmasq.d/10-ratlab.conf /etc/dnsmasq.hosts.d /usr/local/bin/ratlab-dns
    rm -f /etc/systemd/resolved.conf.d/no-stub.conf

    echo "Uninstalling dnsmasq package..."
    apt-get purge -y dnsmasq 2>/dev/null || true

    echo "Restoring systemd-resolved DNSStubListener..."
    if systemctl is-enabled --quiet systemd-resolved 2>/dev/null || systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        systemctl restart systemd-resolved 2>/dev/null || true
    fi

    echo -e "${GREEN}[OK] Step 7 complete: dnsmasq service, package and utility removed.${NC}"
}

# ------------------------------------------------------------------------------
# STEP 8: Revert Host Entries (/etc/hosts) & Autoremove
# ------------------------------------------------------------------------------
cleanup_hosts() {
    log_step "Step 8: Reverting custom records from /etc/hosts & Autoremoving packages"

    if [[ -f /etc/hosts ]]; then
        echo "Removing ratlab.dev, k8s, and service mappings from /etc/hosts..."
        sed -i '/ratlab\.dev/d' /etc/hosts
        sed -i '/\.k8s\.ratl/d' /etc/hosts
        sed -i '/vault\./d' /etc/hosts
        sed -i '/git\./d' /etc/hosts
        sed -i '/harbor\./d' /etc/hosts
        sed -i '/registry\./d' /etc/hosts
        sed -i '/argocd\./d' /etc/hosts
    fi

    echo "Cleaning orphan APT dependencies..."
    apt-get autoremove --purge -y 2>/dev/null || true

    echo -e "${GREEN}[OK] Step 8 complete: /etc/hosts cleaned and orphan packages removed.${NC}"
}

# ------------------------------------------------------------------------------
# OPTIONAL: Revert Tailscale (Explicit flag only)
# ------------------------------------------------------------------------------
cleanup_tailscale() {
    log_step "OPTIONAL: Reverting Tailscale Network"
    if [[ "$INCLUDE_TAILSCALE" != true ]]; then
        echo -e "${YELLOW}[PRESERVED] Skipping Tailscale to keep remote connectivity intact.${NC}"
        return 0
    fi

    echo -e "${RED}[WARNING] Disconnecting and removing Tailscale...${NC}"
    if command -v tailscale >/dev/null 2>&1; then
        tailscale down || true
    fi
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true
    apt-get remove --purge -y tailscale 2>/dev/null || true
    rm -rf /var/lib/tailscale
}

# ------------------------------------------------------------------------------
# OPTIONAL: Revert SSH (Explicit flag only)
# ------------------------------------------------------------------------------
cleanup_ssh() {
    log_step "OPTIONAL: Reverting SSH"
    if [[ "$INCLUDE_SSH" != true ]]; then
        echo -e "${YELLOW}[PRESERVED] Skipping SSH configuration to keep access intact.${NC}"
        return 0
    fi

    echo -e "${RED}[WARNING] Reverting SSH configuration...${NC}"
    rm -f /etc/ssh/sshd_config.d/00-devbox.conf
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
}

# ==============================================================================
# Main Orchestration Loop (Reverse Order)
# ==============================================================================
case "${TARGET_STEP}" in
    argocd|kind|kind_cluster)
        cleanup_argocd_kind
        ;;
    harbor)
        cleanup_harbor
        ;;
    gitea)
        cleanup_gitea
        ;;
    openbao|vault)
        cleanup_openbao
        ;;
    nginx)
        cleanup_nginx
        ;;
    docker)
        cleanup_docker
        ;;
    dns)
        cleanup_dns
        ;;
    hosts)
        cleanup_hosts
        ;;
    tailscale)
        INCLUDE_TAILSCALE=true
        cleanup_tailscale
        ;;
    ssh)
        INCLUDE_SSH=true
        cleanup_ssh
        ;;
    all)
        echo -e "${YELLOW}>> Commencing FULL devbox tooling & service cleanup in REVERSE order...${NC}"
        cleanup_argocd_kind    # Step 1: Kind clusters, ArgoCD & K8s binaries
        cleanup_harbor         # Step 2: Harbor service, stack & scripts
        cleanup_gitea          # Step 3: Gitea service & binary
        cleanup_openbao        # Step 4: OpenBao service, package, binary & PKI
        cleanup_nginx          # Step 5: Nginx reverse proxy service & package
        cleanup_docker         # Step 6: Docker CE services, packages & repos
        cleanup_dns            # Step 7: dnsmasq service, package & CLI
        cleanup_hosts          # Step 8: Clean /etc/hosts & autoremove
        cleanup_tailscale      # Preserved unless explicit flag
        cleanup_ssh            # Preserved unless explicit flag

        echo -e "\n${GREEN}======================================================================${NC}"
        echo -e "${GREEN}>> SUCCESS: Devbox tools, binaries, services, and packages removed.${NC}"
        if [[ "$INCLUDE_DATA" == true ]]; then
            echo -e "${RED}>> PERSISTENT DATA: Explicitly purged (--with-data passed).${NC}"
        else
            echo -e "${YELLOW}>> PERSISTENT DATA: PRESERVED (/data/harbor, /var/lib/*).${NC}"
            echo -e "${YELLOW}>> To purge data, rerun with: ./scripts/cleanup-devbox.sh --with-data${NC}"
        fi
        echo -e "${BLUE}======================================================================${NC}"
        ;;
    *)
        echo -e "${RED}[ERROR] Unknown step: '${TARGET_STEP}'${NC}" >&2
        echo "Valid steps: all, argocd, kind, harbor, gitea, openbao, nginx, docker, dns, hosts" >&2
        exit 1
        ;;
esac
