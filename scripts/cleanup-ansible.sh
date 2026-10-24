#!/usr/bin/env bash
# ==============================================================================
# Ansible Cleanup Script (cleanup-ansible.sh)
#
# Removes Ansible, python dependencies, cache, and collections from the machine.
# Usage:
#   sudo ./cleanup-ansible.sh
# ==============================================================================

set -euo pipefail

# Ensure script is executed with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] cleanup-ansible.sh must be run as root (or via sudo)." 1>&2
   exit 1
fi

echo "================================================================================"
echo ">> Starting Ansible cleanup..."
echo "================================================================================"

# Identify Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# 1. Uninstall OS packages
case "$OS" in
    ubuntu|debian|pop|linuxmint)
        echo ">> Purging Ansible packages via apt..."
        apt-get remove --purge -y ansible ansible-core 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        ;;

    fedora|rhel|centos|rocky|alma)
        echo ">> Removing Ansible packages via dnf..."
        dnf remove -y ansible ansible-core 2>/dev/null || true
        dnf autoremove -y 2>/dev/null || true
        ;;

    arch|manjaro)
        echo ">> Removing Ansible packages via pacman..."
        pacman -Rns --noconfirm ansible 2>/dev/null || true
        ;;

    *)
        echo ">> Skipping package manager removal for distribution: $OS"
        ;;
esac

# 2. Uninstall pip packages if pip3 is installed
if command -v pip3 >/dev/null 2>&1; then
    echo ">> Removing Ansible packages via pip..."
    pip3 uninstall -y ansible ansible-core ansible-compat ansible-lint 2>/dev/null || \
    pip3 uninstall --break-system-packages -y ansible ansible-core 2>/dev/null || true
fi

# 3. Clean up cache, collections, and configuration directories
echo ">> Removing Ansible cache, collections, and configuration files..."
rm -rf /root/.ansible /etc/ansible /var/tmp/ansible* /tmp/ansible* 2>/dev/null || true

# Clean up any local user .ansible directories
for user_home in /home/*; do
    if [ -d "$user_home/.ansible" ]; then
        rm -rf "$user_home/.ansible" 2>/dev/null || true
    fi
done

echo "================================================================================"
echo ">> Ansible cleanup completed successfully. System is clean."
echo "================================================================================"
