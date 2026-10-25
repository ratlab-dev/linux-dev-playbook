# Linux Devbox Architecture and Requirements Specification

## 1. Project Overview

This repository automates the setup of a Linux development box (devbox).
Setup runs in two distinct stages.

### Stage 1: Laptop Bootstrap
- Runs locally on the target Linux machine using bootstrap.sh.
- Uses pure shell with no Python or Ansible dependencies.
- Configures the hostname to devbox.ratlab.dev.
- Starts OpenSSH on port 22 with key-based root login.

### Stage 2: Remote Provisioning
- Runs remotely from your Mac controller laptop.
- Orchestrates the full stack using Ansible over SSH and Tailscale.
- Deploys DNS, Docker, Vault PKI, Git, Registry, Kubernetes, and GitOps.
- Validates the environment with automated tests.

## 2. Networking and DNS

- Root Domain: ratlab.dev
- Core Services:
  - vault.ratlab.dev: OpenBao PKI and Web UI
  - git.ratlab.dev: Gitea Git service
  - jenkins.ratlab.dev: Jenkins CI and OIDC Provider
  - registry.ratlab.dev: Harbor container registry
  - argocd.ratlab.dev: ArgoCD GitOps Web UI
  - giant-cluster.k8s.ratlab.dev: Kubernetes API proxy
- Network Fabric: Tailscale mesh network.
- DNS Resolution: dnsmasq resolves *.ratlab.dev to the devbox Tailscale IP.
- Port Allocation Policy: Centralized registry in `inventory/group_vars/all.yml` (`ratlab_ports`). Exactly one unique port is mapped per system service:
  - SSH: 22
  - DNS (dnsmasq): 53
  - Nginx (HTTP/HTTPS): 80 / 443
  - Gitea (SSH/HTTP): 2222 / 3000
  - Kind giant-cluster API: 6443
  - Harbor (HTTP/HTTPS): 8080 / 8443
  - Jenkins Controller (HTTP/JNLP): 8088 / 50000
  - OpenBao Vault: 8200
  - Enforced by pre-run assertion in `playbooks/devbox.yml`.

## 3. Stage 1: Laptop Bootstrap Details

- File: bootstrap.sh
- Supported distributions: Ubuntu, Debian, Arch Linux, Fedora, RHEL.
- Actions performed:
  - Writes hostname to /etc/hostname and /etc/hosts.
  - Installs openssh-server.
  - Configures /etc/ssh/sshd_config.d/00-devbox.conf for key-based root access.
  - Imports public keys from files/keys/root.keys into /root/.ssh/authorized_keys.
  - Starts sshd and prints the local IP address.

## 4. Stage 2: Remote Provisioning Details

- Master Playbook: playbooks/devbox.yml

### 4.1. Baseline and Root CA (roles/baseline)
- Installs basic networking tools (curl, git, tmux, htop, dnsutils, fzf).
- Installs custom Root CA certificates from files/certs/ into the system trust store.
- Configures interactive shell tools: kubectx, kubens, and history size.

### 4.2. Tailscale Mesh (roles/tailscale)
- Installs the official Tailscale package.
- Connects the devbox with hostname devbox and enables Tailscale SSH.
- Supports pre-set auth keys or browser-based login links.
- Extracts the Tailscale IP for subsequent services.

### 4.3. Local DNS Server (roles/dns)
- Deploys dnsmasq bound to the Tailscale IP and 127.0.0.1.
- Watches /etc/dnsmasq.hosts.d/ using inotify for zero-restart record changes.
- Maps *.ratlab.dev to the devbox IP.
- Disables systemd-resolved DNSStubListener to free port 53.
- Provides the CLI tool ratlab-dns.

### 4.4. Docker Engine (roles/docker)
- Installs Docker CE, containerd, and docker-compose-plugin.
- Configures log rotation in /etc/docker/daemon.json.
- Allows the Mac controller to connect using a Docker SSH context.

### 4.5. OpenBao Vault PKI (roles/openbao)
- Installs OpenBao from the official repository.
- Runs on 127.0.0.1:8200 with the Web UI enabled.
- Nginx proxies port 443 with TLS to the OpenBao daemon.
- Two-year validity on server certificates.
- Skips YubiKey prompts if an existing certificate is valid for over 30 days.
- Initializes and unseals OpenBao.
- Exports credentials to local controller files files/openbao_init.json and files/vault_credentials.json.
- Credentials files are strictly ignored by git.
- Configures an Intermediate CA for *.ratlab.dev.
- The Intermediate CA cannot issue certificates for vault.ratlab.dev.
- Installs the helper script /usr/local/bin/issue-service-cert.

### 4.6. Gitea Git Service (roles/gitea)
- Runs as a systemd service under user git.
- Stores data in /var/lib/gitea.
- Secured with TLS via OpenBao Intermediate CA.
- Web UI on port 3000, SSH on port 2222.
- Configured with OAuth2/OIDC provider trusting Jenkins workloads so code can be pulled keylessly.

### 4.7. Jenkins CI Controller & Workload Identity (roles/jenkins)
- Runs as a systemd service under user jenkins.
- Controller executors set to 0 to guarantee all jobs run on Kubernetes ephemeral workers.
- Deployed before Harbor to allow Harbor to register and verify Jenkins OIDC trust during provisioning.
- OpenID Connect Provider plugin (`oidc-provider`) configured to issue short-lived JWT tokens for jobs.
- Dynamic ephemeral agent pods spun up in `giant-cluster` in namespace `jenkins-agents` via the Kubernetes plugin over WebSockets.
- Gitea is configured with an OAuth2/OIDC authentication source pointing to Jenkins discovery endpoints.
- Installs the validation utility `/usr/local/bin/test-jenkins-k8s-build`.

### 4.8. Harbor Container Registry (roles/harbor)
- Runs via Docker Compose with data in /data/harbor.
- Secured with TLS via OpenBao Intermediate CA on port 443.
- Configured with OIDC trust pointing to `https://jenkins.ratlab.dev` and trusted issuer registration.
- Auto-seeds official MetalLB and ArgoCD Helm charts.

### 4.9. Kubernetes Giant Cluster (roles/kind_cluster)
- Runs a single giant Kind cluster named giant-cluster.
- Node topology: 1 control plane node and 2 worker nodes.
- Local API server binds to 127.0.0.1:6443.
- Nginx proxies API traffic on port 443 for domain giant-cluster.k8s.ratlab.dev.
- Configures devbox access for Jenkins user with cluster kubeconfig.
- Trust: Configured with OpenBao Kubernetes authentication.
- Secrets: Service accounts read secrets from /apps/secrets/<ns>_<sa>.
- Networking: CoreDNS forwards internal domains to devbox DNS.
- Load Balancing: MetalLB provides LoadBalancer IPs from the docker network subnet.
- Kubeconfig: Generates unified kubeconfigs for devbox and remote Mac access.
- Contexts: giant-cluster and context alias giant.

### 4.10. ArgoCD GitOps (roles/argocd)
- Deploys ArgoCD to giant-cluster in namespace argocd.
- Web UI is accessible at https://argocd.ratlab.dev.
- Synchronizes manifests from Gitea repository admin/gitops.
- ApplicationSets deploy namespaces, platform tools, workload apps, and Jenkins ephemeral agents RBAC (ServiceAccount, Role, RoleBinding).

### 4.11. Verification Suite (roles/verify)
- Tests DNS resolution for all ratlab.dev hostnames (including Jenkins).
- Tests Docker container execution.
- Tests HTTPS health endpoints for Vault, Gitea, Jenkins (and OIDC discovery), and Harbor.
- Tests Kubernetes cluster health and ephemeral agent ServiceAccount readiness.
- Tests ArgoCD session and application status.
- Prints a consolidated access dashboard.

### 4.12. Devbox Cleanup (playbooks/cleanup.yml)
- Reverses configuration in opposite creation order.
- Deletes Kind clusters and Nginx proxy sites.
- Uninstalls services, packages, and CLI binaries.
- Preserves data in /var/lib and /data by default.
- Data is purged only when cleanup_data=true is passed.
