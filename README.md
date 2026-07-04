# 03‑os‑provisioner

Multi‑distribution Ansible Playbook generator for automated OS baseline provisioning (Ubuntu / RHEL).

## Disclaimer
This module **generates** Ansible playbooks; it does not execute them directly. Run the generated playbook against your inventory.

## Supported Distributions
| Family | Versions |
|--------|----------|
| Ubuntu | 22.04, 24.04, 26.04 |
| RHEL‑based | 8.x, 9.x, 10.x |

## Generated Playbook Tasks
1. **Chrony NTP** – installs and configures `chronyd` with the requested time zone.
2. **Service Hardening** – masks/disables non‑essential services: `postfix`, `bluetooth`, `cups`, `avahi-daemon`.
3. **Firewall** – disables `ufw` (Ubuntu) or `firewalld` (RHEL).
4. **SELinux** – sets to `disabled` (persistent) and `permissive` (runtime) on RHEL.
5. **DNS** – writes persistent `/etc/resolv.conf` with user‑provided primary/secondary DNS; configures NetworkManager on RHEL 8+.
6. **System Limits** – raises `nofile` to 65536 in `/etc/security/limits.conf`, `/etc/systemd/system.conf`, and `/etc/systemd/user.conf`.

## Usage
```bash
cd modules/03-os-provisioner
./execute.sh
```
Follow the interactive prompts:
1. Target Time Zone (e.g., `Asia/Tehran`).
2. Primary & Secondary DNS IPs (validated).
3. Custom SSH port for Ansible.
4. Delivery method:
   - **A) Local** – saves `site.yml`, `inventory.ini`, and Jinja2 templates to a directory you specify.
   - **B) GitLab** – (placeholder) stages files for GitLab API upload.

## Running the Generated Playbook
After local delivery:
```bash
cd <output-directory>
ansible-playbook -i inventory.ini site.yml
```

## Requirements
- Ansible ≥ 2.12 on the control machine.
- Python 3 on target hosts.
- SSH access to targets (root or sudo user).

## Cleanup
Ctrl+C at any prompt triggers safe cleanup of temporary files.

---
© Davoud Teimouri – StratoShell project