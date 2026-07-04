# Changelog

## v0.0.1 – 2026-07-04
- Initial implementation of OS Provisioner playbook generator
- Multi-distro support: Ubuntu 22.04/24.04/26.04, RHEL 8/9/10
- Interactive variable gathering with validation loops (timezone, DNS IPs, SSH port)
- Playbook tasks: Chrony NTP, service hardening, firewall disable, SELinux disable, DNS persistence, file limits
- Jinja2 templates for chrony.conf and resolv.conf
- Dual delivery: local directory or GitLab API upload placeholder
- SIGINT trap with temp file cleanup
- Comprehensive README with execution instructions