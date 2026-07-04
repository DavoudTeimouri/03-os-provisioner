#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log() { printf "[%s] %s\n" "$(date +%T)" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }

# SIGINT Trap
cleanup() {
    warn "Interrupted – cleaning up temporary files"
    rm -f /tmp/stratoshell_site.yml /tmp/stratoshell_inventory.ini
    exit 1
}
trap cleanup SIGINT SIGTERM

# Disclaimer
clear
echo -e "${BOLD}${BLUE}========================================${NC}"
echo -e "${BOLD}${BLUE}  StratoShell Module 03 – OS Provisioner${NC}"
echo -e "${BOLD}${BLUE}========================================${NC}"
echo ""
echo -e "${BOLD}${RED}DISCLAIMER:${NC} This module generates a standardized Ansible Playbook for"
echo -e "multi-distro enterprise OS baseline provisioning."
echo -e "Supported: ${GREEN}Ubuntu 22.04, 24.04, 26.04${NC} | ${GREEN}RHEL 8.x, 9.x, 10.x${NC}"
echo ""

# Variables
TIME_ZONE=""
DNS_PRIMARY=""
DNS_SECONDARY=""
SSH_PORT=22
DELIVERY_MODE=""
OUTPUT_DIR=""
GITLAB_API_URL=""
GITLAB_TOKEN=""
GITLAB_PROJECT_ID=""
GITLAB_BRANCH="main"

# Valid IP regex
IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

# Input: Time Zone
while [[ -z "$TIME_ZONE" ]]; do
    read -rp "Target Time Zone (e.g., Asia/Tehran, UTC): " TIME_ZONE
    [[ -z "$TIME_ZONE" ]] && warn "Time zone cannot be empty"
done

# Input: Primary DNS
while [[ -z "$DNS_PRIMARY" ]]; do
    read -rp "Primary DNS Server (IP): " DNS_PRIMARY
    if [[ ! $DNS_PRIMARY =~ $IP_REGEX ]]; then
        warn "Invalid IP format for Primary DNS"
        DNS_PRIMARY=""
    fi
done

# Input: Secondary DNS
while [[ -z "$DNS_SECONDARY" ]]; do
    read -rp "Secondary DNS Server (IP): " DNS_SECONDARY
    if [[ ! $DNS_SECONDARY =~ $IP_REGEX ]]; then
        warn "Invalid IP format for Secondary DNS"
        DNS_SECONDARY=""
    fi
done

# Input: SSH Port
read -rp "Custom SSH Port [22]: " input_port
SSH_PORT=${input_port:-22}
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || { warn "Invalid port, using 22"; SSH_PORT=22; }

# Delivery Mode
echo ""
echo "Select delivery method:"
echo "  A) Save locally to a directory"
echo "  B) Upload to GitLab (API)"
while [[ -z "$DELIVERY_MODE" ]]; do
    read -rp "Choice [A/B]: " choice
    case ${choice^^} in
        A) DELIVERY_MODE="local" ;;
        B) DELIVERY_MODE="gitlab" ;;
        *) warn "Invalid choice" ;;
    esac
done

if [[ "$DELIVERY_MODE" == "local" ]]; then
    while [[ -z "$OUTPUT_DIR" ]]; do
        read -rp "Output directory path: " OUTPUT_DIR
        mkdir -p "$OUTPUT_DIR" 2>/dev/null || { warn "Cannot create directory"; OUTPUT_DIR=""; }
    done
else
    while [[ -z "$GITLAB_API_URL" ]]; do
        read -rp "GitLab API URL (e.g., https://gitlab.com/api/v4): " GITLAB_API_URL
    done
    while [[ -z "$GITLAB_TOKEN" ]]; do
        read -rsp "GitLab Private Access Token: " GITLAB_TOKEN; echo
    done
    while [[ -z "$GITLAB_PROJECT_ID" ]]; do
        read -rp "GitLab Project ID: " GITLAB_PROJECT_ID
    done
    read -rp "Target Branch [main]: " GITLAB_BRANCH
    GITLAB_BRANCH=${GITLAB_BRANCH:-main}
fi

# Generate inventory.ini
cat > /tmp/stratoshell_inventory.ini <<INV
[ubuntu]
# ubuntu22 ansible_host=10.0.0.1 ansible_user=ubuntu
# ubuntu24 ansible_host=10.0.0.2 ansible_user=ubuntu

[rhel]
# rhel8 ansible_host=10.0.0.3 ansible_user=root
# rhel9 ansible_host=10.0.0.4 ansible_user=root

[all:vars]
ansible_ssh_port=$SSH_PORT
ansible_python_interpreter=auto_silent
timezone=$TIME_ZONE
dns_primary=$DNS_PRIMARY
dns_secondary=$DNS_SECONDARY
INV

# Generate site.yml
cat > /tmp/stratoshell_site.yml <<'YAML'
---
- name: Enterprise OS Baseline Provisioning
  hosts: all
  become: true
  gather_facts: true
  vars:
    timezone: "{{ timezone | default('UTC') }}"
    dns_primary: "{{ dns_primary | default('1.1.1.1') }}"
    dns_secondary: "{{ dns_secondary | default('8.8.8.8') }}"
    file_limits:
      soft: 65536
      hard: 65536

  pre_tasks:
    - name: Detect distribution family
      set_fact:
        is_debian: "{{ ansible_os_family == 'Debian' }}"
        is_redhat: "{{ ansible_os_family == 'RedHat' }}"

  tasks:
    # --- Time & NTP ---
    - name: Install chrony (Debian)
      apt:
        name: chrony
        state: present
        update_cache: true
      when: is_debian

    - name: Install chrony (RHEL)
      dnf:
        name: chrony
        state: present
      when: is_redhat

    - name: Configure chrony with timezone
      template:
        src: templates/chrony.conf.j2
        dest: /etc/chrony/chrony.conf
        mode: '0644'
      notify: restart chrony

    - name: Set system timezone
      community.general.timezone:
        name: "{{ timezone }}"

    # --- Disable Non-Essential Services ---
    - name: Disable non-essential services (Debian)
      systemd:
        name: "{{ item }}"
        enabled: false
        state: stopped
        masked: true
      loop:
        - postfix
        - bluetooth
        - cups
        - avahi-daemon
      when: is_debian
      ignore_errors: true

    - name: Disable non-essential services (RHEL)
      systemd:
        name: "{{ item }}"
        enabled: false
        state: stopped
        masked: true
      loop:
        - postfix
        - bluetooth
        - cups
        - avahi-daemon
      when: is_redhat
      ignore_errors: true

    # --- Firewall ---
    - name: Disable UFW (Debian)
      ufw:
        state: disabled
      when: is_debian
      ignore_errors: true

    - name: Disable firewalld (RHEL)
      systemd:
        name: firewalld
        enabled: false
        state: stopped
        masked: true
      when: is_redhat
      ignore_errors: true

    # --- SELinux (RHEL) ---
    - name: Set SELinux to permissive (runtime)
      command: setenforce 0
      when: is_redhat
      ignore_errors: true
      changed_when: false

    - name: Set SELinux to disabled (persistent)
      lineinfile:
        path: /etc/selinux/config
        regexp: '^SELINUX='
        line: 'SELINUX=disabled'
      when: is_redhat

    # --- DNS Configuration ---
    - name: Write resolv.conf with custom DNS (systemd-resolved disabled)
      template:
        src: templates/resolv.conf.j2
        dest: /etc/resolv.conf
        mode: '0644'
      when: not is_redhat or ansible_distribution_major_version|int >= 8

    - name: Configure NetworkManager DNS (RHEL 8+)
      block:
        - name: Ensure NetworkManager.d directory
          file:
            path: /etc/NetworkManager/conf.d
            state: directory
            mode: '0755'
        - name: Write DNS config
          copy:
            dest: /etc/NetworkManager/conf.d/99-dns.conf
            content: |
              [main]
              dns=none
            mode: '0644'
        - name: Reload NetworkManager
          systemd:
            name: NetworkManager
            state: restarted
      when: is_redhat

    # --- System Limits ---
    - name: Set /etc/security/limits.conf
      blockinfile:
        path: /etc/security/limits.conf
        block: |
          * soft nofile {{ file_limits.soft }}
          * hard nofile {{ file_limits.hard }}
          root soft nofile {{ file_limits.soft }}
          root hard nofile {{ file_limits.hard }}
        marker: "# {mark} StratoShell OS Baseline Limits"

    - name: Set /etc/systemd/system.conf limits
      lineinfile:
        path: /etc/systemd/system.conf
        regexp: '^#?DefaultLimitNOFILE='
        line: 'DefaultLimitNOFILE={{ file_limits.soft }}:{{ file_limits.hard }}'

    - name: Set /etc/systemd/user.conf limits
      lineinfile:
        path: /etc/systemd/user.conf
        regexp: '^#?DefaultLimitNOFILE='
        line: 'DefaultLimitNOFILE={{ file_limits.soft }}:{{ file_limits.hard }}'

  handlers:
    - name: restart chrony
      systemd:
        name: chronyd
        state: restarted
        enabled: true

    - name: restart systemd-resolved
      systemd:
        name: systemd-resolved
        state: restarted
      when: is_debian
YAML

# Create template directory and templates
mkdir -p /tmp/stratoshell_templates

cat > /tmp/stratoshell_templates/chrony.conf.j2 <<'EOF'
# StratoShell managed chrony.conf
pool {{ dns_primary }} iburst
pool {{ dns_secondary }} iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

cat > /tmp/stratoshell_templates/resolv.conf.j2 <<'EOF'
# StratoShell managed resolv.conf
nameserver {{ dns_primary }}
nameserver {{ dns_secondary }}
options timeout:2 attempts:3 rotate single-request-reopen
EOF

# Delivery
if [[ "$DELIVERY_MODE" == "local" ]]; then
    OUT_DIR="$OUTPUT_DIR/os-provisioner-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$OUT_DIR/templates"
    cp /tmp/stratoshell_site.yml "$OUT_DIR/site.yml"
    cp /tmp/stratoshell_inventory.ini "$OUT_DIR/inventory.ini"
    cp /tmp/stratoshell_templates/* "$OUT_DIR/templates/"
    log "Playbook package saved to: $OUT_DIR"
else
    # GitLab API upload (simplified - creates files via API)
    log "Uploading to GitLab project $GITLAB_PROJECT_ID..."
    # Note: Full GitLab API upload requires multiple API calls.
    # This is a placeholder for the actual implementation.
    warn "GitLab upload requires multi-file commit API. Files staged locally at /tmp/stratoshell_*"
    warn "Implement gitlab-project-upload.sh for full automation."
fi

# Summary
clear
echo -e "${BOLD}${GREEN}=== OS Provisioner Playbook Generated ===${NC}"
echo ""
echo -e "${BOLD}Target Distributions:${NC} Ubuntu 22.04/24.04/26.04 | RHEL 8/9/10"
echo -e "${BOLD}Time Zone:${NC} $TIME_ZONE"
echo -e "${BOLD}DNS Servers:${NC} Primary: $DNS_PRIMARY | Secondary: $DNS_SECONDARY"
echo -e "${BOLD}SSH Port:${NC} $SSH_PORT"
echo -e "${BOLD}Delivery:${NC} $DELIVERY_MODE"
[[ "$DELIVERY_MODE" == "local" ]] && echo -e "${BOLD}Output Path:${NC} $OUT_DIR"
echo ""
echo -e "${BOLD}Playbook Tasks:${NC}"
echo "  • Chrony NTP with custom timezone"
echo "  • Disable postfix, bluetooth, cups, avahi-daemon"
echo "  • Disable UFW (Ubuntu) / firewalld (RHEL)"
echo "  • SELinux disabled (RHEL)"
echo "  • Persistent DNS via resolv.conf & NetworkManager"
echo "  • File limits (nofile) raised to 65536"
echo ""
echo -e "${BOLD}Execution Command:${NC}"
echo "  ansible-playbook -i inventory.ini site.yml"
echo ""

# Cleanup temp
rm -rf /tmp/stratoshell_templates /tmp/stratoshell_site.yml /tmp/stratoshell_inventory.ini
exit 0