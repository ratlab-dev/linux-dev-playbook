# Linux Devbox Architecture & Requirements Specification

## 1. Project Overview
This repository manages the automated setup, provisioning, and maintenance of a Linux-based development box ("devbox"). The setup is partitioned into two distinct stages:

1. **Stage 1: Laptop Bootstrap (Local Shell Execution)**
   - Executed directly on a fresh Linux laptop installation via `bootstrap.sh`.
   - **Scope:** Zero dependencies (no Python or Ansible required on the laptop). Sets hostname (`devbox.ratlab.dev`), configures OpenSSH on port 22, and authorizes the root public key from `files/keys/root.keys`.
2. **Stage 2: Devbox Provisioning & Services (Remote Execution via Ansible from Mac)**
   - Executed remotely from your Mac workstation over SSH/Tailscale.
   - **Scope:** 
     - Baseline tooling & custom Root CA installation into the OS trust store.
     - Tailscale onboarding (mesh connection, `--ssh`, and firewall configuration).
     - DNS Server (`dnsmasq`) for `ratlab.dev` and wildcard subdomains.
     - Docker CE engine, Compose plugin, and remote SSH context for peer workstations.
     - OpenBao (Vault fork) systemd service, Root CA (YubiKey) CSR signing workflow, and Intermediate PKI CA (`*.ratlab.dev` excluding `vault.ratlab.dev`).
     - Gitea self-hosted Git service (systemd, persistent volume, TLS).
     - Harbor container registry (Docker Compose, persistent storage, TLS).
     - Automated end-to-end verification suite in Ansible.

---

## 2. Global Assumptions & Networking
- **Base Domain:** `ratlab.dev` is the root domain used for all internal services:
  - `vault.ratlab.dev` (OpenBao PKI / Secrets)
  - `git.ratlab.dev` (Gitea Git Server)
  - `registry.ratlab.dev` / `harbor.ratlab.dev` (Harbor Container Registry)
  - `dns.ratlab.dev` (dnsmasq Resolver)
- **Network Fabric:** Tailscale mesh network interconnects devbox instances and peer workstations (Mac).
- **DNS Resolution:** dnsmasq resolves `*.ratlab.dev` to the devbox's Tailscale IP, with Split DNS configured in Tailscale Admin.

---

## 3. Stage 1: Laptop Bootstrap (Pure Shell)

- **Entrypoint:** `bootstrap.sh`
- **Dependencies:** None (pure POSIX shell, utilizes native package manager `apt`, `dnf`, or `pacman`).
- **Features:**
  - Configures system hostname (`devbox.ratlab.dev`) and adds entry to `/etc/hosts`.
  - Installs `openssh-server`.
  - Configures `/etc/ssh/sshd_config.d/00-devbox.conf` on port 22 with key-based root login enabled (`PermitRootLogin prohibit-password`).
  - Automatically loads root SSH public key from `files/keys/root.keys` into `/root/.ssh/authorized_keys`.
  - Enables and restarts SSH service, displaying the target IP address.

---

## 4. Stage 2: Remote Devbox Provisioning (Ansible from Mac)

- **Entrypoint:** `playbooks/devbox.yml`

### 4.1. Baseline & Custom CAs (`roles/baseline`)
- Installs debugging and networking utilities (`curl`, `git`, `htop`, `tmux`, `dnsutils`, `net-tools`, `tcpdump`, etc.).
- Installs custom Root CA certificates (`files/certs/*.crt`) into the OS trust store (`update-ca-certificates` / `update-ca-trust`).

### 4.2. Tailscale Mesh Onboarding (`roles/tailscale`)
- Installs official Tailscale package and starts `tailscaled`.
- Connects node using `tailscale up --hostname={{ baseline_hostname }} --ssh --accept-routes`.
- Supports pre-approved auth keys or interactive web login.
- Extracts `tailscale_node_ip` and exposes it as a fact for all downstream roles.

### 4.3. DNS Server for `ratlab.dev` (`roles/dns`)
- Deploys `dnsmasq` bound to `tailscale_node_ip` and `127.0.0.1`.
- Prevents port 53 collision with `systemd-resolved` by disabling stub listener if active.
- Configures wildcard address: `address=/ratlab.dev/<TAILSCALE_IP>` (any `*.ratlab.dev` resolves to the devbox).
- Supports explicit/custom overrides in `dns_custom_records`.
- Upstream forwarders configured to `1.1.1.1` and `8.8.8.8`.

### 4.4. Docker & Peer SSH Context (`roles/docker`)
- Installs Docker CE engine, containerd, and `docker-compose-plugin`.
- Configures log rotation in `/etc/docker/daemon.json` (`json-file`, 50m max-size).
- Configures Docker group permissions.
- Prepares peer command for Mac:
  `docker context create devbox --docker "host=ssh://root@<TAILSCALE_IP>"`

### 4.5. OpenBao (Vault) & PKI Intermediate CA (`roles/openbao`)
- **Daemon Setup:**
  - Deploys OpenBao binary as a hardened `systemd` service (`openbao.service`) under `openbao:openbao`.
  - File storage backend at `/var/lib/openbao/data`.
- **Server TLS & YubiKey CSR Workflow:**
  - Generates RSA 2048 private key and CSR for `vault.ratlab.dev` (with SANs for `127.0.0.1`, Tailscale IP, localhost).
  - Fetches `files/certs/openbao.csr` to Mac for offline signing with YubiKey Root CA.
  - Deploys signed `files/certs/openbao.crt` when provided.
- **Intermediate CA PKI Secrets Engine:**
  - Initializes and unseals OpenBao (backing up keys to `/root/.openbao_init.json` and fetching to Mac).
  - Enables PKI secrets engine at `pki_ratlab`.
  - Generates intermediate CSR (`files/certs/intermediate.csr`) for YubiKey Root CA signing.
  - Imports signed intermediate certificate (`files/certs/intermediate.crt`).
  - Configures role `ratlab-services` allowing issuance for `*.ratlab.dev`.
  - Enforces policy constraint: **Intermediate CA is authorized to sign `*.ratlab.dev` SANs, but explicitly forbidden from signing for `vault.ratlab.dev`**.
  - Deploys helper utility `/usr/local/bin/issue-service-cert <domain> <cert_out> <key_out>`.

### 4.6. Gitea Self-Hosted Git Service (`roles/gitea`)
- Systemd managed service (`gitea.service`) running under dedicated `git` user.
- Persistent volumes: `/var/lib/gitea/data`, `/var/lib/gitea/repositories`, `/etc/gitea`.
- TLS enabled using certificate issued for `git.ratlab.dev` by OpenBao intermediate PKI.
- HTTPS on port 3000, SSH on port 2222.

### 4.7. Harbor Container Registry (`roles/harbor`)
- Docker-based deployment running via Docker Compose (`harbor.service`).
- Persistent storage volume: `/data/harbor`.
- TLS enabled on port 443 with certificate issued for `registry.ratlab.dev` by OpenBao intermediate PKI.
- HTTP traffic routed on port 8080.

### 4.8. Automated End-to-End Verification (`roles/verify`)
- Ansible automated testing suite validating:
  - DNS resolution of all `*.ratlab.dev` hostnames.
  - Tailscale connectivity and active status.
  - Docker container execution (`docker run --rm alpine ...`).
  - OpenBao HTTPS health endpoint (`/v1/sys/health`).
  - Gitea HTTPS API endpoint (`/api/v1/version`).
  - Harbor HTTPS registry ping (`/api/v2.0/ping`).
- Outputs an aggregated summary report with direct service URLs.

### 4.9. Automated Devbox Teardown & Tooling Cleanup (`playbooks/cleanup.yml`)
- Reverses configuration in opposite order of creation: ArgoCD/Kind → Harbor → Gitea → OpenBao → Nginx → Docker → DNS → Hosts.
- **Tooling Uninstallation:**
  - Systemd services stopped, disabled, and unit files removed.
  - Binaries uninstalled (`kind`, `kubectl`, `helm`, `kubectx`, `kubens`, `gitea`, `bao`, `vault`, `ratlab-dns`, etc.).
  - APT packages and repositories purged (`nginx`, `dnsmasq`, `openbao`, `docker-ce`, `containerd.io`).
- **Data Policy:** Persistent data stores (`/data/harbor`, `/var/lib/gitea`, `/var/lib/openbao`, `/root/.kube`) are preserved by default, and only purged when explicitly passed via `cleanup_data=true` or `--with-data`.
