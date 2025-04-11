#!/bin/bash
# VPS Optimizer Script (Refactored and Modular)
# Author: github.com/origrata

#===================[ WARNA DAN GLOBAL ]===================#
CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
MAGENTA="\e[95m"
WHITE="\e[97m"
NC="\e[0m"
BOLD=$(tput bold)
LOG_FILE="/var/log/vps_optimizer.log"

#===================[ LOGGING ]===================#
log() {
    local level="$1"
    local message="$2"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
    logger -t vps_optimizer "$message"
}

send_email_log() {
    local email_to="admin@example.com"
    local subject="VPS Optimization Log - $(hostname)"
    mail -s "$subject" "$email_to" < "$LOG_FILE"
}

#===================[ VALIDASI ROOT ]===================#
if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

#===================[ BACKUP & RESTORE ]===================#
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "$file.bak.$(date '+%Y%m%d%H%M%S')"
        log "INFO" "Backup dibuat untuk $file"
    fi
}

restore_backup() {
    local file="$1"
    local backup_file=$(ls -t "$file.bak."* 2>/dev/null | head -n1)
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$file"
        log "INFO" "Restore berhasil untuk $file dari backup: $backup_file"
    else
        log "ERROR" "Backup untuk $file tidak ditemukan."
    fi
}

#===================[ LIMITS CONFIGURATION ]===================#
optimize_limits() {
    local limits_conf="/etc/security/limits.conf"
    backup_file "$limits_conf"
    cat <<EOL >> "$limits_conf"
* soft nproc 65535
* hard nproc 65535
* soft nofile 65535
* hard nofile 65535
root soft nproc 65535
root hard nproc 65535
root soft nofile 65535
root hard nofile 65535
* soft memlock unlimited
* hard memlock unlimited
EOL
    pam_session="/etc/pam.d/common-session"
    if ! grep -q "pam_limits.so" "$pam_session"; then
        echo "session required pam_limits.so" >> "$pam_session"
    fi
    log "INFO" "Optimasi batas file dan proses berhasil."
}

#===================[ SYSCTL CONFIGURATION ]===================#
optimize_sysctl() {
    local sysctl_conf="/etc/sysctl.conf"
    backup_file "$sysctl_conf"
    echo "fs.file-max = 65535" >> "$sysctl_conf"
    sysctl -p && log "INFO" "fs.file-max berhasil dikonfigurasi."
}

#===================[ LXC CONFIGURATION ]===================#
optimize_lxc() {
    local lxc_conf="/etc/pve/nodes/pve/lxc/id_lxc.conf"
    if [ -f "$lxc_conf" ]; then
        backup_file "$lxc_conf"
        echo "lxc.prlimit.nofile: 65535" >> "$lxc_conf"
        echo "unprivileged: 1" >> "$lxc_conf"
        log "INFO" "Konfigurasi LXC berhasil diterapkan."
    else
        log "WARNING" "File konfigurasi LXC tidak ditemukan."
    fi
}

#===================[ BBR CONFIGURATION ]===================#
ask_bbr_version_1() {
    local sysctl_conf="/etc/sysctl.conf"
    backup_file "$sysctl_conf"
    sed -i '/^net.core.default_qdisc/d' "$sysctl_conf"
    sed -i '/^net.ipv4.tcp_congestion_control/d' "$sysctl_conf"
    echo "net.core.default_qdisc=fq" >> "$sysctl_conf"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$sysctl_conf"
    sysctl -p && log "INFO" "BBR + FQ berhasil diaktifkan."
}

#===================[ SSH CONFIGURATION ]===================#
optimize_ssh_configuration() {
    local SSH_PATH="/etc/ssh/sshd_config"
    if [ -f "$SSH_PATH" ]; then
        backup_file "$SSH_PATH"
        cat <<EOL > "$SSH_PATH"
# Optimized SSH configuration
Protocol 2
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,ssh-rsa
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
UseDNS no
MaxSessions 10
Compression no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 3
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
PermitRootLogin no
Banner /etc/ssh/banner
X11Forwarding no
PrintMotd no
PrintLastLog yes
MaxAuthTries 3
LoginGraceTime 1m
MaxStartups 10:30:60
EOL
        echo "Unauthorized access prohibited." > /etc/ssh/banner
        systemctl restart ssh && log "INFO" "Konfigurasi SSH berhasil."
    else
        log "ERROR" "SSH config file tidak ditemukan."
    fi
}

#===================[ MENU ]===================#
show_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            ${MAGENTA}VPS OPTIMIZER${CYAN}                      ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ 1) Optimasi Batas File dan Proses             ║${NC}"
    echo -e "${CYAN}║ 2) Optimasi Sysctl (fs.file-max)              ║${NC}"
    echo -e "${CYAN}║ 3) Optimasi LXC (Proxmox)                     ║${NC}"
    echo -e "${CYAN}║ 4) Optimasi Jaringan (BBR)                    ║${NC}"
    echo -e "${CYAN}║ 5) Optimasi SSH                               ║${NC}"
    echo -e "${CYAN}║ 6) Restore Konfigurasi                        ║${NC}"
    echo -e "${CYAN}║ 7) Kirim Log ke Email                         ║${NC}"
    echo -e "${CYAN}║ 8) Keluar                                     ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
    echo -ne "${YELLOW}Pilih opsi [1-8]: ${NC}"
    read -r choice
    case $choice in
        1) optimize_limits ;;
        2) optimize_sysctl ;;
        3) optimize_lxc ;;
        4) ask_bbr_version_1 ;;
        5) optimize_ssh_configuration ;;
        6) restore_all_configs ;;
        7) send_email_log ;;
        8) echo -e "${RED}Keluar...${NC}"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
    esac
    echo -e "\n${YELLOW}Tekan Enter untuk melanjutkan...${NC}"
    read -r
}

# Restore all config files if needed
restore_all_configs() {
    restore_backup "/etc/security/limits.conf"
    restore_backup "/etc/sysctl.conf"
    restore_backup "/etc/pve/nodes/pve/lxc/id_lxc.conf"
    restore_backup "/etc/ssh/sshd_config"
}

#===================[ MAIN ]===================#
while true; do
    show_menu
done
