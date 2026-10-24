# Helper & Operational Scripts

This directory houses helper scripts for orchestrating, maintaining, and verifying the Linux devbox infrastructure.

---

### Overview of Scripts

| Script | Execution Target | Purpose |
| :--- | :--- | :--- |
| [`run.sh`](run.sh) | **Mac Workstation** | Convenience orchestrator for Ansible playbooks with tag filtering and connectivity checks. |
| [`verify.sh`](verify.sh) | **Mac Workstation** | Automated remote end-to-end test suite checking ping, SSH, DNS, Root CA trust, and service health. |
| [`sign_with_yubikey.sh`](sign_with_yubikey.sh) | **Mac Workstation** | Interactive PKCS#11 CSR signer using a physical YubiKey Root CA. |
| [`cleanup-devbox.sh`](cleanup-devbox.sh) | **Mac / Devbox** | Comprehensive cleanup orchestrator: uninstalls tools, binaries, systemd units, and APT packages in reverse order. |
| [`cleanup-ansible.sh`](cleanup-ansible.sh) | **Linux Devbox** | Maintenance script to purge Ansible packages, Python dependencies, and caches from the host. |

---

### Usage Details

#### 1. `run.sh` (Mac Workstation)
Executes Ansible playbooks with environment checks and shortcuts:
```bash
# Provision everything
./scripts/run.sh

# Target specific playbooks
./scripts/run.sh baseline
./scripts/run.sh tailscale

# Target specific service tags
./scripts/run.sh dns
./scripts/run.sh openbao
./scripts/run.sh gitea

# Test SSH / Tailscale connectivity
./scripts/run.sh check
```

#### 2. `verify.sh` (Mac Workstation)
Runs end-to-end validation tests against the active devbox over Tailscale:
```bash
./scripts/verify.sh [target_ip]
```

#### 3. `sign_with_yubikey.sh` (Mac Workstation)
Signs a Certificate Signing Request (CSR) with the hardware YubiKey:
```bash
# Sign server certificate (vault.ratlab.dev):
./scripts/sign_with_yubikey.sh files/certs/openbao.csr files/certs/openbao.crt 730 server

# Sign an intermediate CA (OpenBao PKI):
./scripts/sign_with_yubikey.sh files/certs/intermediate.csr files/certs/intermediate.crt 3650 intermediate
```

#### 4. `cleanup-ansible.sh` (Linux Devbox)
Purges local Ansible installations if you want to keep the devbox purely orchestrated remotely:
```bash
sudo ./scripts/cleanup-ansible.sh
```
*(Also available via top-level forwarder: `sudo ./cleanup-ansible.sh`).*

#### 5. `cleanup-devbox.sh` (Mac Workstation or Linux Devbox)
Reverts and uninstalls services, systemd units, binaries, and APT packages in reverse order:
```bash
# Clean tools, binaries, services, and packages (preserves persistent data):
./scripts/cleanup-devbox.sh --remote

# Clean tools, binaries, AND purge persistent data:
./scripts/cleanup-devbox.sh --remote --with-data

# Clean only a specific component (e.g. kind, openbao, nginx, docker, dns):
./scripts/cleanup-devbox.sh openbao --remote
```
