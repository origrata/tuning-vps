#!/bin/bash
# VPS Optimizer - Refactored and Modular Version
# Author: github.com/origrata
# Version: 2.0

#=== WARNA DAN KONFIGURASI DASAR ===#
CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
MAGENTA="\e[95m"
WHITE="\e[97m"
NC="\e[0m"
BOLD=$(tput bold)

LOG_FILE="/var/log/vps_optimizer.log"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

ensure_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n ${RED}This script must be run as root.${NC}"
        exit 1
    fi
}

include_pam_limits() {
    local pam_session="/etc/pam.d/common-session"
    grep -q "pam_limits.so" "$pam_session" || echo "session required pam_limits.so" >> "$pam_session"
}

optimize_limits() {
    echo -e "${YELLOW}Mengoptimasi batas file dan proses...${NC}"
    cat <<EOL > /etc/security/limits.d/99-custom.conf
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
    include_pam_limits
    log "File limits configured"
    echo -e "${GREEN}Limits selesai dikonfigurasi.${NC}"
}

optimize_sysctl() {
    echo -e "${YELLOW}Mengoptimasi parameter sysctl...${NC}"
    cat <<EOL >> /etc/sysctl.d/99-custom.conf
fs.file-max = 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.ip_local_port_range = 10240 65000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 65535
EOL
    sysctl --system
    log "Sysctl configured"
    echo -e "${GREEN}Parameter sysctl telah dioptimasi.${NC}"
}

optimize_lxc() {
    local lxc_conf="/etc/pve/lxc/100.conf"
    echo -e "${YELLOW}Mengoptimasi LXC...${NC}"
    if [ -f "$lxc_conf" ]; then
        echo "lxc.prlimit.nofile: 65535" >> "$lxc_conf"
        echo "unprivileged: 1" >> "$lxc_conf"
        log "LXC configuration updated"
        echo -e "${GREEN}LXC berhasil dikonfigurasi.${NC}"
    else
        echo -e "${RED}LXC config tidak ditemukan: $lxc_conf${NC}"
    fi
}

apply_bbr() {
    echo -e "${YELLOW}Mengkonfigurasi BBR...${NC}"
    if [[ $(uname -r) =~ ([4-9]\.|[1-9][0-9]) ]]; then
        sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p && log "BBR applied"
        echo -e "${GREEN}BBR berhasil diaktifkan.${NC}"
    else
        echo -e "${RED}Kernel tidak mendukung BBR.${NC}"
    fi
}

optimize_ssh() {
    local SSH_PATH="/etc/ssh/sshd_config"
    echo -e "${MAGENTA}Mengoptimasi SSH...${NC}"

    if [ -f "$SSH_PATH" ]; then
        cp "$SSH_PATH" "${SSH_PATH}.bak"
        cat <<EOL > "$SSH_PATH"
Protocol 2
PasswordAuthentication no
PermitRootLogin no
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
X11Forwarding no
PrintMotd no
PrintLastLog yes
MaxAuthTries 3
LoginGraceTime 1m
MaxStartups 10:30:60
Banner /etc/ssh/banner
EOL
        echo "WARNING: Unauthorized access to this system is prohibited." > /etc/ssh/banner
        systemctl restart sshd || systemctl restart ssh
        log "SSH optimized"
        echo -e "${GREEN}SSH berhasil dikonfigurasi.${NC}"
    else
        echo -e "${RED}SSH config tidak ditemukan.${NC}"
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║            ${MAGENTA}VPS OPTIMIZER${CYAN}                      ║${NC}"
        echo -e "${CYAN}╠═══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║ 1) Optimasi Batas File dan Proses             ║${NC}"
        echo -e "${CYAN}║ 2) Optimasi Sysctl (fs.file-max & lainnya)    ║${NC}"
        echo -e "${CYAN}║ 3) Optimasi LXC (Proxmox)                     ║${NC}"
        echo -e "${CYAN}║ 4) Aktifkan BBR                               ║${NC}"
        echo -e "${CYAN}║ 5) Optimasi SSH                               ║${NC}"
        echo -e "${CYAN}║ 6) Keluar                                     ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
        echo -ne "${YELLOW}Pilih opsi [1-6]: ${NC}"
        read -r choice

        case $choice in
            1) optimize_limits ;;
            2) optimize_sysctl ;;
            3) optimize_lxc ;;
            4) apply_bbr ;;
            5) optimize_ssh ;;
            6) echo -e "${RED}Keluar...${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid. Silakan coba lagi.${NC}" ;;
        esac
        echo -e "\n${YELLOW}Tekan Enter untuk melanjutkan...${NC}"
        read -r
    done
}

# Entry point
ensure_root
log "Starting VPS Optimization"
main_menu
