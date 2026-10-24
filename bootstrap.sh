#!/usr/bin/env bash
# ==============================================================================
# Linux Devbox Minimal Bootstrap (bootstrap.sh)
#
# Fast, pure shell bootstrap with ZERO dependencies (no Python or Ansible required).
#
# What it does:
#   1. Sets machine hostname (e.g. devbox-001)
#   2. Installs and secures OpenSSH Server on Port 22
#   3. Authorizes your root SSH public key
#   4. Enables and starts the SSH service
#
# Usage:
#   sudo ./bootstrap.sh
#   DEVBOX_HOSTNAME="devbox-001" sudo -E ./bootstrap.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# Paste your SSH public key here (or leave empty and use files/authorized_keys)
# Example: BOOTSTRAP_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@macbook"
# ==============================================================================
BOOTSTRAP_SSH_PUBLIC_KEY=""

# Ensure script is executed with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] bootstrap.sh must be run as root (or via sudo)." 1>&2
   echo "Example: sudo ./bootstrap.sh" 1>&2
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "                  LINUX DEVBOX MINIMAL BOOTSTRAP                                "
echo "================================================================================"

# ------------------------------------------------------------------------------
# 1. Hostname Configuration
# ------------------------------------------------------------------------------
if [[ -z "${DEVBOX_HOSTNAME:-}" ]]; then
    echo ""
    echo ">> Hostname Configuration:"
    read -r -p "   Enter hostname for this devbox [default: devbox.ratlab.dev]: " INPUT_HOSTNAME
    DEVBOX_HOSTNAME="${INPUT_HOSTNAME:-devbox.ratlab.dev}"
fi

echo ">> Setting hostname to: ${DEVBOX_HOSTNAME}"
hostnamectl set-hostname "${DEVBOX_HOSTNAME}" 2>/dev/null || hostname "${DEVBOX_HOSTNAME}"

# Ensure /etc/hosts has local entry
SHORT_HOSTNAME="${DEVBOX_HOSTNAME%%.*}"
FQDN_HOSTNAME="${DEVBOX_HOSTNAME}"
if [[ "${FQDN_HOSTNAME}" != *.* ]]; then
    FQDN_HOSTNAME="${DEVBOX_HOSTNAME}.ratlab.dev"
fi

if ! grep -q "${SHORT_HOSTNAME}" /etc/hosts; then
    echo "127.0.1.1 ${FQDN_HOSTNAME} ${SHORT_HOSTNAME}" >> /etc/hosts
fi

# ------------------------------------------------------------------------------
# 2. Install OpenSSH Server
# ------------------------------------------------------------------------------
echo ">> Installing OpenSSH server and essential tools..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

case "$OS" in
    ubuntu|debian|pop|linuxmint)
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server curl ca-certificates
        SSH_SERVICE="ssh"
        ;;

    fedora|rhel|centos|rocky|alma)
        dnf install -y openssh-server curl ca-certificates
        SSH_SERVICE="sshd"
        ;;

    arch|manjaro)
        pacman -Sy --noconfirm openssh curl ca-certificates
        SSH_SERVICE="sshd"
        ;;

    *)
        echo "[WARNING] Unknown distribution: $OS. Assuming 'ssh' service name..."
        SSH_SERVICE="ssh"
        ;;
esac

# ------------------------------------------------------------------------------
# 3. Trust Custom Root CAs (e.g. ratlab-root-ca.crt)
# ------------------------------------------------------------------------------
CERTS_DIR="${SCRIPT_DIR}/files/certs"
if [ -d "${CERTS_DIR}" ]; then
    CA_COPIED=false
    for crt in "${CERTS_DIR}"/*.crt "${CERTS_DIR}"/*.pem; do
        if [ -f "$crt" ]; then
            echo ">> Installing Root CA: $(basename "$crt")..."
            if [ -d /usr/local/share/ca-certificates ]; then
                cp "$crt" /usr/local/share/ca-certificates/
                CA_COPIED=true
            elif [ -d /etc/pki/ca-trust/source/anchors ]; then
                cp "$crt" /etc/pki/ca-trust/source/anchors/
                CA_COPIED=true
            fi
        fi
    done
    if [ "$CA_COPIED" = true ]; then
        if command -v update-ca-certificates >/dev/null 2>&1; then
            update-ca-certificates
        elif command -v update-ca-trust >/dev/null 2>&1; then
            update-ca-trust extract
        fi
        echo ">> System CA trust store updated with custom Root CAs."
    fi
fi

# ------------------------------------------------------------------------------
# 4. Configure SSH Server (/etc/ssh/sshd_config.d/00-devbox.conf)
# ------------------------------------------------------------------------------
echo ">> Configuring OpenSSH on port 22..."

mkdir -p /etc/ssh/sshd_config.d

# Ensure the main config includes drop-in configs
if [ -f /etc/ssh/sshd_config ]; then
    if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    fi
fi

cat << 'EOF' > /etc/ssh/sshd_config.d/00-devbox.conf
# Managed by devbox bootstrap
Port 22
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2
Subsystem sftp internal-sftp
ClientAliveInterval 120
ClientAliveCountMax 3
EOF

# Validate SSH config syntax
sshd -t 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Authorize Root Public Key
# ------------------------------------------------------------------------------
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

ROOT_KEYS_FILE="${SCRIPT_DIR}/files/keys/root.keys"
FALLBACK_KEYS_FILE="${SCRIPT_DIR}/files/authorized_keys"
KEY_ADDED=false

# 1. Check BOOTSTRAP_SSH_PUBLIC_KEY defined at top of script
if [[ -n "${BOOTSTRAP_SSH_PUBLIC_KEY}" && "${BOOTSTRAP_SSH_PUBLIC_KEY}" != "YOUR_SSH_PUBLIC_KEY_HERE" ]]; then
    if ! grep -qxF "${BOOTSTRAP_SSH_PUBLIC_KEY}" /root/.ssh/authorized_keys; then
        echo ">> Installing public key from BOOTSTRAP_SSH_PUBLIC_KEY..."
        echo "${BOOTSTRAP_SSH_PUBLIC_KEY}" >> /root/.ssh/authorized_keys
        KEY_ADDED=true
    fi
fi

# 2. Check files/keys/root.keys (primary) or files/authorized_keys (fallback)
for candidate_file in "${ROOT_KEYS_FILE}" "${FALLBACK_KEYS_FILE}"; do
    if [ -f "${candidate_file}" ]; then
        KEYS_FROM_FILE=$(grep -v '^#' "${candidate_file}" | grep -v '^[[:space:]]*$' || true)
        if [ -n "${KEYS_FROM_FILE}" ]; then
            echo ">> Installing root public keys from $(basename "${candidate_file}")..."
            while IFS= read -r key; do
                if ! grep -qxF "${key}" /root/.ssh/authorized_keys; then
                    echo "${key}" >> /root/.ssh/authorized_keys
                    KEY_ADDED=true
                fi
            done <<< "${KEYS_FROM_FILE}"
        fi
    fi
done

# 3. Check ROOT_SSH_KEY environment variable
if [[ -n "${ROOT_SSH_KEY:-}" ]]; then
    if ! grep -qxF "${ROOT_SSH_KEY}" /root/.ssh/authorized_keys; then
        echo "${ROOT_SSH_KEY}" >> /root/.ssh/authorized_keys
        KEY_ADDED=true
    fi
fi

# Prompt interactively if no key has been authorized yet
if [ ! -s /root/.ssh/authorized_keys ] && [ "$KEY_ADDED" = false ]; then
    echo ""
    echo ">> No SSH public key found."
    echo "   Paste your Mac / client SSH public key below (e.g. ssh-ed25519 AAAAC3...):"
    read -r -p "   SSH Key: " USER_PASTED_KEY
    if [[ -n "${USER_PASTED_KEY}" ]]; then
        echo "${USER_PASTED_KEY}" >> /root/.ssh/authorized_keys
        KEY_ADDED=true
    else
        echo "[WARNING] No SSH key added! Password authentication may be required."
    fi
fi

# ------------------------------------------------------------------------------
# 5. Enable and Restart SSH Service
# ------------------------------------------------------------------------------
echo ">> Enabling and restarting ${SSH_SERVICE}..."
systemctl enable "${SSH_SERVICE}" >/dev/null 2>&1 || true
systemctl restart "${SSH_SERVICE}"

# Allow port 22 in firewall if active
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 6. Summary and Connection Instructions
# ------------------------------------------------------------------------------
IP_ADDRS=$(hostname -I 2>/dev/null || ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | tr '\n' ' ' || echo "Check IP with 'ip a'")

echo ""
echo "================================================================================"
echo "                 BOOTSTRAP COMPLETE - SSH IS READY                              "
echo "================================================================================"
echo "Hostname:         ${DEVBOX_HOSTNAME}"
echo "SSH Port:         22"
echo "IP Address(es):   ${IP_ADDRS}"
echo ""
echo "Next step: Connect from your Mac workstation over SSH:"
echo "  ssh root@<IP_ADDRESS>"
echo ""
echo "Once connected, you can run all Ansible playbooks remotely from your Mac!"
echo "================================================================================"
