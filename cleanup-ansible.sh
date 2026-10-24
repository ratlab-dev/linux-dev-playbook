#!/usr/bin/env bash
# Forwarder to scripts/cleanup-ansible.sh
exec "$(dirname "$0")/scripts/cleanup-ansible.sh" "$@"
