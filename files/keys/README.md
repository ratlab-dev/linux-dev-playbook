# SSH Authorized Keys Directory

Public keys are organized per user using the pattern `<username>.keys`.

## Structure:
- `files/keys/root.keys`: Authorized keys for the `root` user (installed by `bootstrap.sh` and Ansible).
- `files/keys/<service-account>.keys`: Authorized keys for any service accounts or secondary users (e.g. `deployer.keys`, `ci.keys`).

Each file can contain one or multiple public keys (one per line). Empty lines and comments (`#`) are ignored.
