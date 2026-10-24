# Linux Devbox Playbook

Automation for provisioning and configuring dedicated Linux development workstations (`devbox.ratlab.dev`) within the `ratlab.dev` private network.

---

## Architecture Overview

```
                                 ┌────────────────────────────────────────────────────────┐
                                 │                   ratlab.dev Tailnet                   │
                                 └────────────────────────────────────────────────────────┘
                                            │                                  │
                                            ▼                                  ▼
                              ┌───────────────────────────┐      ┌───────────────────────────┐
                              │      Mac Workstation      │      │       Linux Devbox        │
                              │ (Remote Management Peer)  │      │(devbox.ratlab.dev / OS)   │
                              └───────────────────────────┘      └───────────────────────────┘
                                            │                                  │
                                            │ 1. Minimal Bootstrap             │ [Stage 1: Laptop]
                                            │    (sudo ./bootstrap.sh)         │ - Hostname (devbox.ratlab.dev)
                                            │    *Pure shell, zero Ansible*    │ - OpenSSH on port 22
                                            │                                  │ - Root SSH key authorized
                                            │                                  │
                                            │ 2. Remote Ansible Provisioning   │ [Stage 2: Remote Orchestration]
                                            ├─────────────────────────────────►│ - Baseline packages & Root CAs
                                            │    (playbooks/devbox.yml)        │ - Tailscale Mesh & SSH
                                            │                                  │ - CoreDNS / dnsmasq (*.ratlab.dev)
                                            │                                  │ - Docker + Peer SSH Context
                                            │                                  │ - OpenBao (Vault PKI systemd)
                                            │                                  │ - Gitea Git (systemd + TLS)
                                            │                                  │ - Harbor Registry (Docker + TLS)
                                            │                                  │ - Automated verification tests
                                            └──────────────────────────────────┴─────────────────────────────────┘
```

For complete architectural details and functional specifications, refer to [REQUIREMENTS.md](file:///Users/naugustin/work/personalisation/linux-dev-playbook/REQUIREMENTS.md).

---

## Step 1: Bootstrap the Laptop (Pure Shell, No Ansible)

Run this once locally on the fresh Linux laptop installation. It requires **no Python, pip, or Ansible**.

### 1. Pre-configure your SSH Key
Add your Mac's SSH public key into [files/keys/root.keys](file:///Users/naugustin/work/personalisation/linux-dev-playbook/files/keys/root.keys):
```bash
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@macbook" >> files/keys/root.keys
```
*(Public keys are organized per user as `files/keys/<username>.keys`).*
*(If left empty, `bootstrap.sh` will prompt you to paste it interactively).*

### 2. Run the Bootstrap Script
On the laptop:
```bash
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

**Options:**
- **Interactive Prompt:** Asks for hostname (default: `devbox.ratlab.dev`).
- **Environment Variable:**
  ```bash
  DEVBOX_HOSTNAME="devbox.ratlab.dev" sudo -E ./bootstrap.sh
  ```

### What it does:
- Sets the machine hostname to `devbox.ratlab.dev` in `/etc/hostname` and `/etc/hosts`.
- Installs `openssh-server`.
- Configures `/etc/ssh/sshd_config.d/00-devbox.conf` on port 22 with key-based root access.
- Adds your public key to `/root/.ssh/authorized_keys`.
- Starts the SSH daemon and prints the machine's IP address.

---

## Step 2: Remote Provisioning from your Mac

Once `bootstrap.sh` finishes on the laptop, test connecting from your Mac:
```bash
ssh root@<LAPTOP_IP>
```

From this point onwards, **all playbooks are executed remotely from your Mac**!

### Prerequisites on your Mac:
Install `ansible.posix`:
```bash
ansible-galaxy collection install -r requirements.yml
```

---

### Executing the Complete Devbox Playbook:

Update [inventory/hosts.ini](file:///Users/naugustin/work/personalisation/linux-dev-playbook/inventory/hosts.ini) with your devbox IP (LAN IP initially, or Tailscale IP after onboarding):
```ini
[devbox]
devbox.ratlab.dev ansible_host=<DEVBOX_IP> ansible_user=root
```

Then run the master devbox playbook using the runner script:
```bash
./scripts/run.sh
# Or standard ansible:
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml
```

> **Note on Tailscale Credentials:**
> - If you have a Tailscale auth key, export it in memory: `export TAILSCALE_AUTH_KEY="tskey-auth-..."`
> - If left unset, the playbook will automatically open your Mac's browser to the approval URL so you can authenticate in one click.

---

## Remote Verification Suite

Run the automated validation suite from your Mac over Tailscale:
```bash
./scripts/verify.sh
```

---

## Services Provisioned in Stage 2

### 1. Tailscale Onboarding (`roles/tailscale`)
- Connects the devbox to your Tailnet with `--hostname=devbox` and `--ssh`.
- Extracts `tailscale_node_ip` and binds subsequent services to it.
- Seamless in-memory authentication (via browser approval or `TAILSCALE_AUTH_KEY`).

### 2. DNS Server & Dynamic Registration (`roles/dns`)
- Deploys `dnsmasq` bound to your Tailscale IP and `127.0.0.1`.
- Dynamic hosts directory `/etc/dnsmasq.hosts.d/` watched via kernel `inotify` for real-time additions/removals with zero service restarts.
- Deploys `/usr/local/bin/ratlab-dns` for instant script/CLI registration:
  ```bash
  ratlab-dns add <domain> [ip]
  ratlab-dns remove <domain>
  ratlab-dns list
  ```
- Wildcard root mapping: `*.ratlab.dev` automatically points to the devbox.
- Configure Tailscale Admin (**DNS → Nameservers → Restricted Nameserver**) to forward `ratlab.dev` to your devbox Tailscale IP.

### 3. Docker & Peer SSH Context (`roles/docker`)
- Installs Docker CE and Docker Compose.
- Connect your Mac directly to the devbox Docker daemon:
  ```bash
  docker context create devbox --docker "host=ssh://root@<TAILSCALE_IP>"
  docker context use devbox
  docker ps
  ```

### 4. OpenBao (Vault PKI) with Web UI & Nginx Reverse Proxy (`roles/openbao`)
- **Official APT Repository Installation:** Installed via official repository `pkgs.openbao.org` which bundles the full Web UI. Cleans up any previous manual installations.
- **Local Daemon:** OpenBao runs on `127.0.0.1:8200` with `tls_disable = 1` and `ui = true`.
- **Nginx Reverse Proxy (Port 443):**
  - Nginx listens on `0.0.0.0:443` and proxies traffic to `http://127.0.0.1:8200`.
  - Serves TLS certificate on port 443 with automatic HTTP -> HTTPS redirection.
  - OpenBao Web UI accessible at: `https://vault.ratlab.dev` (or `https://vault.ratlab.dev/ui/`).
- **Smart 2-Year Certificate Expiry Logic:**
  - The TLS certificate for `vault.ratlab.dev` is issued for **2 years (730 days)**.
  - Before requesting YubiKey interaction, Ansible checks if an existing certificate is valid for **more than 30 days**.
  - If valid for > 30 days: **YubiKey signing is skipped completely** and the existing certificate is preserved.
  - If missing or expiring within 30 days: Ansible enters **interactive mode**, prompts you to plug in your YubiKey, and automatically executes `scripts/sign_with_yubikey.sh` using the OpenSSL PKCS#11 configuration from `yubikey-based-keys`.
- **Intermediate CA PKI Engine:**
  - Initializes and unseals OpenBao (backing up keys to `files/openbao_init.json`).
  - Generates intermediate CSR at `files/certs/intermediate.csr`.
  - Prompts and signs the Intermediate CA for 10 years via `scripts/sign_with_yubikey.sh` and imports it into OpenBao.
  - **Security Constraint:** Intermediate CA is authorized to sign certificates for `*.ratlab.dev`, but **explicitly forbidden from issuing for `vault.ratlab.dev`**.
  - Deploys `/usr/local/bin/issue-service-cert <domain> <cert> <key>` for automated service cert issuance.

### 5. Gitea Self-Hosted Git (`roles/gitea`)
- Systemd managed service (`gitea.service`) with persistent storage at `/var/lib/gitea`.
- TLS enabled for `git.ratlab.dev` via OpenBao intermediate PKI.
- Web UI: `https://git.ratlab.dev:3000` | SSH: Port 2222.

### 6. Harbor Container Registry (`roles/harbor`)
- Docker-based deployment running via Docker Compose (`harbor.service`).
- Persistent storage volume: `/data/harbor`.
- TLS enabled on port 443 for `registry.ratlab.dev`.

### 7. Automated End-to-End Testing (`roles/verify`)
- Concludes the playbook with automated tests verifying:
  - DNS resolution of all `*.ratlab.dev` domains.
  - Tailscale connectivity.
  - Docker container execution.
  - OpenBao, Gitea, and Harbor HTTPS health endpoints.
  - Displays a consolidated status dashboard.

---

## Running Specific Stages / Tags

You can selectively run or update individual components using tags:

```bash
# Run only Tailscale onboarding:
ansible-playbook playbooks/devbox.yml --tags tailscale

# Run only DNS server:
ansible-playbook playbooks/devbox.yml --tags dns

# Run only Docker setup:
ansible-playbook playbooks/devbox.yml --tags docker

# Run only OpenBao setup:
ansible-playbook playbooks/devbox.yml --tags openbao

# Run only Gitea:
ansible-playbook playbooks/devbox.yml --tags gitea

# Run only Harbor:
ansible-playbook playbooks/devbox.yml --tags harbor

# Run only Verification tests:
ansible-playbook playbooks/devbox.yml --tags verify
```

---

---

## Devbox Teardown & Tooling Cleanup

The cleanup automation can uninstall all services, systemd units, binaries, APT packages, and reverse proxies provisioned on the devbox in **reverse order of creation** (`ArgoCD/Kind` → `Harbor` → `Gitea` → `OpenBao` → `Nginx` → `Docker` → `DNS` → `Hosts`).

### What gets removed:
* **Binaries:** `/usr/local/bin/{kind,kubectl,helm,kubectx,kubens,gitea,ratlab-dns,issue-service-cert,upload-*-chart-to-harbor}`, `/usr/bin/{bao,vault}`.
* **Systemd Services:** `nginx`, `openbao`, `gitea`, `harbor`, `docker`, `containerd`, `dnsmasq` (stopped, disabled, unit files removed).
* **APT Packages & Repositories:** `nginx`, `openbao`, `docker-ce`, `containerd.io`, `dnsmasq`, plus official APT source lists (`/etc/apt/sources.list.d/openbao.sources`, `/etc/apt/sources.list.d/docker.list`) and keyrings.
* **DNS & Proxies:** Nginx site configurations, dnsmasq configs, systemd-resolved stub restoration, and `/etc/hosts` cleanups.

### Persistent Data Policy (Explicit When Needed):
> [!IMPORTANT]
> **Persistent data is PRESERVED by default.**
> Directories containing application data (`/data/harbor`, `/var/lib/gitea`, `/var/lib/openbao`, `/root/.kube`, and Docker volumes) are kept safe. They are only purged when you explicitly pass the data flag.

### Usage:

#### 1. Via Playbook Runner (`scripts/run.sh`)
```bash
# Standard cleanup: Uninstalls tools, services, and packages (data is preserved):
./scripts/run.sh cleanup

# Explicit cleanup WITH persistent data purged:
./scripts/run.sh cleanup -e "cleanup_data=true"

# Component-specific cleanup via tags:
./scripts/run.sh cleanup --tags k8s       # Remove Kind clusters, ArgoCD & K8s binaries
./scripts/run.sh cleanup --tags harbor    # Remove Harbor stack, systemd & scripts
./scripts/run.sh cleanup --tags gitea     # Remove Gitea service, binary & user
./scripts/run.sh cleanup --tags openbao   # Remove OpenBao service, binary, package & PKI
./scripts/run.sh cleanup --tags nginx     # Remove Nginx proxy configs & purge package
./scripts/run.sh cleanup --tags docker    # Remove Docker containers, service & packages
./scripts/run.sh cleanup --tags dns       # Remove dnsmasq, CLI tool & restore stub
./scripts/run.sh cleanup --tags data      # Explicitly purge persistent data stores
```

#### 2. Via Standalone Orchestrator (`scripts/cleanup-devbox.sh`)
```bash
# Run remotely from Mac:
./scripts/cleanup-devbox.sh --remote

# Run remotely with data purged:
./scripts/cleanup-devbox.sh --remote --with-data

# Target individual steps:
./scripts/cleanup-devbox.sh openbao --remote
```

#### 3. Cleaning up Ansible from Laptop
If you ran earlier bootstrap iterations and have Ansible packages or pip dependencies installed on your laptop that you want to remove:
```bash
chmod +x cleanup-ansible.sh
sudo ./cleanup-ansible.sh
```

---

## Directory Structure

```
linux-dev-playbook/
├── REQUIREMENTS.md                     # Architecture & specifications
├── README.md                           # Documentation & quickstart
├── ansible.cfg                         # Ansible configuration
├── bootstrap.sh                        # Pure shell bootstrap (SSH & hostname only)
├── cleanup-ansible.sh                  # Cleanup script to purge Ansible on target
├── requirements.yml                    # Ansible collections requirements
├── inventory/
│   ├── hosts.ini                       # Inventory definitions
│   └── group_vars/
│       └── all.yml                     # Central configuration variables
├── files/
│   ├── keys/                           # Per-user authorized keys (<username>.keys)
│   │   ├── root.keys                   # Public keys for root user
│   │   └── README.md
│   └── certs/                          # Drop-in folder for custom Root CA certificates
├── playbooks/
│   ├── baseline.yml                    # Baseline system setup & CAs
│   ├── tailscale_onboard.yml           # Tailscale onboarding playbook
│   └── devbox.yml                      # Master devbox orchestration playbook
└── roles/
    ├── baseline/                       # Baseline role (system, CAs, fzf, kubectx/kubens, history)
    ├── tailscale/                      # Tailscale onboarding role
    ├── dns/                            # dnsmasq DNS server role
    ├── docker/                         # Docker CE & context role
    ├── openbao/                        # OpenBao systemd, TLS CSR & PKI role
    ├── gitea/                          # Gitea systemd & persistent volume role
    ├── harbor/                         # Harbor docker-compose role
    ├── kind_cluster/                   # Kind cluster provisioning, Vault trust, MetalLB & Nginx proxy
    ├── argocd/                         # ArgoCD Helm deployment, GitOps repo sync & ApplicationSets
    └── verify/                         # Automated end-to-end verification role
```

---

## Kubernetes & GitOps Platform

### 1. Accessing Clusters with kubectl, kubectx & kubens

**From your Mac Workstation:**
Multi-cluster Kubeconfig is automatically generated and synchronized to `files/kubeconfig`, pointing to the Nginx reverse proxies with Vault Intermediate PKI TLS certificates:
```bash
export KUBECONFIG="$(pwd)/files/kubeconfig"
kubectx tooling-cluster      # Management cluster (ArgoCD)
kubectx app-cluster-1        # Workload cluster (region: in-south-1)
kubectx app-cluster-2        # Workload cluster (region: in-north-1)
kubectl get nodes
kubectl get pods -A
```

**Locally on the Linux Devbox:**
Pre-configured in `/root/.kube/config` and `/etc/profile.d/00-ratlab-shell.sh` with `kubectx`, `kubens`, `fzf` completion, and 50,000 persistent history lines:
```bash
kubectx          # Interactive context selection (tooling-cluster, app-cluster-1, app-cluster-2)
kubens           # Interactive namespace selection (argocd, kube-system, default, etc.)
k get pods       # Short alias for kubectl with auto-completion
```

### 2. Multi-Cluster GitOps with ArgoCD
- **URL:** [https://argocd.ratlab.dev](https://argocd.ratlab.dev)
- **Username:** `admin`
- **Password:** `admin`
- **GitOps Repository:** Automatically initialized from local `gitops/` directory without nested git tracking, staged in `/tmp/gitops-init`, and pushed to Gitea at `https://git.ratlab.dev:3000/admin/gitops.git`.
- **Automated Cluster Cross-Referencing:**
  - `tooling-cluster`: Management cluster hosting ArgoCD and platform tools.
  - `app-cluster-1`: Workload cluster tagged with labels `application-workload: "true"`, `region: "in-south-1"`.
  - `app-cluster-2`: Workload cluster tagged with labels `application-workload: "true"`, `region: "in-north-1"`.
  - ApplicationSets (`gitops/applicationsets/workload-apps.yaml`) dynamically target clusters matching `application-workload: "true"` to deploy applications automatically.

### 3. Vault ServiceAccount Secrets Isolation
Service accounts of the format `<namespace>/<sa_name>` authenticate via Vault Kubernetes Auth and automatically receive read permissions strictly scoped to `/apps/secrets/<namespace>_<sa_name>` via dynamic identity templated policies:
```bash
# Read secret for default/test-app
curl -H "X-Vault-Token: <token>" https://vault.ratlab.dev/v1/apps/secrets/data/default_test-app
```
