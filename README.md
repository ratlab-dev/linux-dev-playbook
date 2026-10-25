# Linux Devbox Playbook

This repository provisions and maintains a dedicated Linux workstation.
The target host is devbox.ratlab.dev on the private ratlab.dev network.

## Architecture

The project has two setup stages.

```
                    ratlab.dev Tailnet
                            |
             +--------------+--------------+
             |                             |
             v                             v
      Mac Workstation                Linux Devbox
    (Controller Laptop)         (devbox.ratlab.dev)
             |                             |
             | 1. Shell Bootstrap          | [Stage 1: Local]
             |    (sudo ./bootstrap.sh)    | - Set hostname
             |    *No Python or Ansible*   | - Start OpenSSH on port 22
             |                             | - Authorize root key
             |                             |
             | 2. Remote Ansible Run       | [Stage 2: Remote Orchestration]
             +---------------------------->| - System packages and Root CA
                  (playbooks/devbox.yml)   | - Tailscale mesh with SSH
                                           | - Local DNS via dnsmasq
                                           | - Docker engine
                                           | - OpenBao Vault PKI and Web UI
                                           | - Gitea Git service
                                           | - Jenkins CI and OIDC Provider
                                           | - Harbor container registry
                                           | - Giant Kind cluster
                                           | - ArgoCD GitOps
                                           | - Automated verification
```

For more architectural details, see [REQUIREMENTS.md](file:///Users/naugustin/work/personalisation/linux-dev-playbook/REQUIREMENTS.md).

## Step 1: Bootstrap the Laptop

Run this step directly on the fresh Linux installation.
It does not require Python or Ansible.

### 1. Configure Your SSH Key
Add your Mac public key to [files/keys/root.keys](file:///Users/naugustin/work/personalisation/linux-dev-playbook/files/keys/root.keys):
```bash
echo "ssh-ed25519 AAAAC3NzaC... user@macbook" >> files/keys/root.keys
```
If this file is empty, the script prompts for the key.

### 2. Run the Script
On the Linux machine, run:
```bash
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

You can pass the hostname through an environment variable:
```bash
DEVBOX_HOSTNAME="devbox.ratlab.dev" sudo -E ./bootstrap.sh
```

### What This Step Does
- Sets the system hostname to devbox.ratlab.dev.
- Installs openssh-server.
- Configures key-based root login on port 22.
- Adds your public key to /root/.ssh/authorized_keys.
- Starts SSH and prints the IP address.

## Step 2: Remote Provisioning from Mac

After bootstrap completes, verify SSH access from your Mac:
```bash
ssh root@<DEVBOX_IP>
```

All remaining steps run remotely from your Mac.

### Requirements on Your Mac
Install required Ansible collections:
```bash
ansible-galaxy collection install -r requirements.yml
```

### Update Inventory
Set your devbox IP address in [inventory/hosts.ini](file:///Users/naugustin/work/personalisation/linux-dev-playbook/inventory/hosts.ini):
```ini
[devbox]
devbox.ratlab.dev ansible_host=<DEVBOX_IP> ansible_user=root
```

### Run the Playbook
Run the full provisioning playbook:
```bash
./scripts/run.sh
```
Or run Ansible directly:
```bash
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml
```

If you have a Tailscale auth key, set it before running:
```bash
export TAILSCALE_AUTH_KEY="tskey-auth-..."
```
If you do not set an auth key, Ansible prints a login link.
Click the link to approve the device.

## Automated Verification

Run tests from your Mac to check all services:
```bash
./scripts/verify.sh
```

## Services Provisioned

### 1. Tailscale Mesh (roles/tailscale)
- Connects the devbox to your Tailscale network.
- Enables Tailscale SSH.
- Sets facts for downstream services.

### 2. Local DNS (roles/dns)
- Runs dnsmasq on the Tailscale IP and 127.0.0.1.
- Watches /etc/dnsmasq.hosts.d/ for instant updates.
- Routes all *.ratlab.dev queries to the devbox.
- Includes the ratlab-dns helper tool:
  ```bash
  ratlab-dns add <domain> [ip]
  ratlab-dns remove <domain>
  ratlab-dns list
  ```

### 3. Docker (roles/docker)
- Installs Docker CE and Docker Compose.
- Supports remote Docker contexts from your Mac:
  ```bash
  docker context create devbox --docker "host=ssh://root@<TAILSCALE_IP>"
  docker context use devbox
  docker ps
  ```

### 4. OpenBao Vault PKI (roles/openbao)
- Installs OpenBao from the official repository.
- Runs on 127.0.0.1:8200 with the Web UI enabled.
- Nginx proxies port 443 to the OpenBao daemon.
- Web UI is at https://vault.ratlab.dev.
- TLS certificate is valid for two years.
- YubiKey signing is only requested when certificates are missing or near expiry.
- Exports root tokens and unseal keys to local files on your Mac:
  - [files/openbao_init.json](file:///Users/naugustin/work/personalisation/linux-dev-playbook/files/openbao_init.json)
  - [files/vault_credentials.json](file:///Users/naugustin/work/personalisation/linux-dev-playbook/files/vault_credentials.json)
- Both credential files are ignored by git.
- Provides the cert helper script:
  ```bash
  /usr/local/bin/issue-service-cert <domain> <cert_out> <key_out>
  ```

### 5. Gitea Git Service (roles/gitea)
- Systemd service storing data in /var/lib/gitea.
- Uses TLS certificates from the OpenBao Intermediate CA.
- Web UI: https://git.ratlab.dev:3000
- SSH clone port: 2222

### 6. Harbor Registry (roles/harbor)
- Runs via Docker Compose with data stored in /data/harbor.
- Uses TLS certificates from the OpenBao Intermediate CA.
- Web UI and registry: https://registry.ratlab.dev
- Automatically publishes official MetalLB and ArgoCD Helm charts.

### 7. Kubernetes Giant Cluster (roles/kind_cluster)
- Runs a single giant Kind cluster named giant-cluster.
- Node topology: 1 control plane node, 2 worker nodes.
- Local access: 127.0.0.1:6443.
- Remote access: https://giant-cluster.k8s.ratlab.dev through Nginx.
- Pre-loaded with Ratlab Root CA certificates.
- Configured with OpenBao Kubernetes authentication.
- MetalLB provides Layer 2 load balancing on the cluster network.

### 8. ArgoCD GitOps (roles/argocd)
- Deployed to giant-cluster in namespace argocd.
- Web UI: https://argocd.ratlab.dev
- Default login: admin / admin
- Syncs applications from Gitea repository admin/gitops.
- Deploys namespaces, platform tools, and user workloads.

## Kubernetes Access

### Kubeconfig on Your Mac
The playbook writes your multi-cluster config to files/kubeconfig.
Point your shell to this file:
```bash
export KUBECONFIG="$(pwd)/files/kubeconfig"
kubectx giant-cluster
kubectl get nodes
kubectl get pods -A
```
You can also use the shorter context alias:
```bash
kubectx giant
```

### Kubeconfig on the Devbox
On the devbox, /root/.kube/config is pre-configured:
```bash
kubectx
kubens
kubectl get nodes
```

## Running Individual Steps

Run individual roles with tags:
```bash
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags tailscale
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags dns
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags docker
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags openbao
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags gitea
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags harbor
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags kind
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags argocd
ansible-playbook -i inventory/hosts.ini playbooks/devbox.yml --tags verify
```

## Teardown and Cleanup

You can remove tools, services, and packages in reverse creation order.

### Standard Cleanup
Removes binaries, systemd units, and packages.
Preserves application data in /var/lib and /data:
```bash
./scripts/run.sh cleanup
```

### Complete Cleanup With Data Purge
Removes all packages and purges persistent directories:
```bash
./scripts/run.sh cleanup -e "cleanup_data=true"
```

### Remote Cleanup Script
You can also clean up with the shell wrapper:
```bash
./scripts/cleanup-devbox.sh --remote
./scripts/cleanup-devbox.sh --remote --with-data
```

## Repository Structure

```
linux-dev-playbook/
├── REQUIREMENTS.md         # Technical requirements
├── README.md               # User guide
├── ansible.cfg             # Ansible defaults
├── bootstrap.sh            # Bootstrap shell script
├── cleanup-ansible.sh      # Ansible remover on laptop
├── requirements.yml        # Galaxy collections
├── inventory/
│   ├── hosts.ini           # Machine inventory
│   └── group_vars/
│       └── all.yml         # Shared variables
├── files/
│   ├── keys/               # Authorized SSH public keys
│   └── certs/              # Custom Root CA certificates
├── playbooks/
│   ├── baseline.yml        # OS baseline setup
│   ├── tailscale_onboard.yml
│   ├── cleanup.yml         # Uninstaller playbook
│   └── devbox.yml          # Main orchestration playbook
└── roles/
    ├── baseline/           # Packages, shell, and Root CA
    ├── tailscale/          # Tailscale mesh setup
    ├── dns/                # dnsmasq local DNS
    ├── docker/             # Docker CE and context
    ├── openbao/            # Vault PKI and Web UI
    ├── gitea/              # Git service
    ├── jenkins/            # CI controller, K8s ephemeral agents & OIDC
    ├── harbor/             # Registry and Helm charts
    ├── kind_cluster/       # Giant Kind cluster setup
    ├── argocd/             # GitOps deployment
    └── verify/             # Automated validation tests
```
