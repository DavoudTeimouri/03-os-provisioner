# Changelog

## v0.0.1 – 2026-07-05
- Initial implementation of OS Provisioner playbook generator
- Multi-distro support: Ubuntu 22.04/24.04/26.04, RHEL 8/9/10
- Interactive variable gathering with validation loops (timezone, NTP servers, DNS IPs, SSH port)
- Custom NTP server input parsing (comma/space separated) → Jinja2 template injection
- Playbook tasks: Chrony NTP with custom pools, service hardening, firewall disable, SELinux disable, DNS persistence, file limits
- Jinja2 templates for chrony.conf and resolv.conf (RHEL/Ubuntu paths)
- Dual delivery: local directory or GitLab API upload
- SIGINT trap with temp file cleanup
- Comprehensive README with execution instructions and verification checklist