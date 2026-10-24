# Custom CA Certificates

Place your custom Root CA certificates (`.crt` or `.pem` format) in this directory:
- `files/certs/`

Any `.crt` or `.pem` file placed here will automatically be copied to the target Linux machine's CA trust store during the baseline playbook execution:
- Debian/Ubuntu: `/usr/local/share/ca-certificates/` (followed by `update-ca-certificates`)
- RHEL/Fedora: `/etc/pki/ca-trust/source/anchors/` (followed by `update-ca-trust`)
- Arch Linux: `/etc/ca-certificates/trust-source/anchors/` (followed by `trust extract-compat`)

You may also configure certificates directly in `inventory/group_vars/all.yml` under `baseline_custom_cas`.
