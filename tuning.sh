#!/bin/bash
# 
# Author: github.com/origrata
#
# For more information and updates, visit github.com/origrata and @origrata on telegram.
CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
WHITE="\e[97m"
NC="\e[0m"
BOLD=$(tput bold)

# Mengecek apakah script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

# Fungsi untuk menambahkan batas file dan proses
optimize_limits() {
    echo -e "${YELLOW}Menyesuaikan batas file dan proses di /etc/security/limits.conf${NC}"
    limits_conf="/etc/security/limits.conf"
    cat <<EOL >> $limits_conf
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

    echo -e "${YELLOW}Mengaktifkan modul PAM limits${NC}"
    pam_session="/etc/pam.d/common-session"
    if ! grep -q "pam_limits.so" $pam_session; then
        echo "session required pam_limits.so" >> $pam_session
    fi

    echo -e "${GREEN}Batas file dan proses telah dioptimasi.${NC}"
}

# Fungsi untuk menambahkan konfigurasi fs.file-max
optimize_sysctl() {
    echo -e "${YELLOW}Menambahkan konfigurasi fs.file-max ke /etc/sysctl.conf${NC}"
    sysctl_conf="/etc/sysctl.conf"
    echo "fs.file-max = 65535" >> $sysctl_conf
    sysctl -p
    echo -e "${GREEN}Konfigurasi fs.file-max telah ditambahkan.${NC}"
}

# Fungsi untuk menambahkan konfigurasi LXC (opsional)
optimize_lxc() {
    echo -e "${YELLOW}Menambahkan konfigurasi LXC (jika menggunakan Proxmox)${NC}"
    lxc_conf="/etc/pve/nodes/pve/lxc/id_lxc.conf"
    if [ -f "$lxc_conf" ]; then
       echo "lxc.prlimit.nofile: 65535" >> $lxc_conf
        echo "unprivileged: 1" >> $lxc_conf
        echo -e "${GREEN}Konfigurasi LXC telah ditambahkan.${NC}"
    else
        echo -e "${RED}File konfigurasi LXC tidak ditemukan. Skipping...${NC}"
    fi
}

# Fungsi untuk memeriksa dukungan kernel terhadap algoritma queuing
check_qdisc_support() {
    local algorithm="$1"

    if tc qdisc add dev lo root "$algorithm" 2>/dev/null; then
        echo && echo -e "$GREEN $algorithm is supported by your kernel. $NC"
        # Remove the test qdisc immediately
        tc qdisc del dev lo root 2>/dev/null
        return 0
    else
        echo && echo -e "$RED $algorithm is not supported by your kernel. $NC"
        return 1
    fi
}

# Fungsi untuk menginstal dan mengkonfigurasi BBRv1
ask_bbr_version_1() {
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    echo && echo -e "${YELLOW}Installing and configuring BBRv1 + FQ...${NC}"
    sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    if [ $? -eq 0 ]; then
        echo && echo -e "${GREEN}Kernel parameter optimization for OpenVZ was successful.${NC}"
    else
        echo && echo -e "${RED}Optimization failed. Restoring original sysctl configuration.${NC}"
        mv /etc/sysctl.conf.bak /etc/sysctl.conf
    fi
}

# Fungsi untuk membuat progress bar
fun_bar() {
    local title="$1"
    local command1="$2"
    local command2="$3"
    (
        [[ -e $HOME/fim ]] && rm $HOME/fim
        $command1 -y > /dev/null 2>&1
        $command2 -y > /dev/null 2>&1
        touch $HOME/fim
    ) &
    tput civis
    echo -ne "  ${BOLD}${YELLOW}$title${BOLD} - ${YELLOW}["
    while true; do
        for ((i = 0; i < 18; i++)); do
            echo -ne "${RED}#"
            sleep 0.1
        done
        if [[ -e "$HOME/fim" ]]; then
            rm "$HOME/fim"
            break
        fi
        echo -e "${YELLOW}]"
        sleep 0.5
        tput cuu1
        tput el 
        echo -ne "  ${BOLD}${YELLOW}$title${BOLD} - ${YELLOW}["
    done
    echo -e "${YELLOW}]${WHITE} -${GREEN} DONE!${WHITE}"
    tput cnorm
}

# Fungsi untuk mengoptimasi SSH
optimize_ssh_configuration() {
    SSH_PATH="/etc/ssh/sshd_config"
    title="Improve SSH Configuration and Optimize SSHD"
    echo && echo -e "${MAGENTA}$title${NC}\n"
    echo && echo -e "\e[93m+-------------------------------------+\e[0m\n"
    if [ -f "$SSH_PATH" ]; then
        cp "$SSH_PATH" "${SSH_PATH}.bak"
        echo && echo -e "${YELLOW}Backup of the original SSH configuration created at ${SSH_PATH}.bak${NC}"
    else
        echo && echo -e "${RED}Error: SSH configuration file not found at ${SSH_PATH}.${NC}"
        return 1
    fi
    echo && cat <<EOL > "$SSH_PATH"
# Optimized SSH configuration for improved security and performance
Protocol 2
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,ecdsa-sha2-nistp256,ssh-rsa
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
    echo "WARNING: Unauthorized access to this system is prohibited." > /etc/ssh/banner
    if service ssh restart; then
        echo && echo -e "${GREEN}SSH and SSHD configuration and optimization complete.${NC}"
    else
        echo && echo -e "${RED}Failed to restart SSH service. Please check the configuration.${NC}"
        return 1
    fi
}

# Fungsi utama untuk optimasi
main_optimization() {
    echo -e "${CYAN}Memulai optimasi VPS...${NC}"
    optimize_limits
    optimize_sysctl
    optimize_lxc
    ask_bbr_version_1
    optimize_ssh_configuration
    echo -e "${GREEN}Optimasi selesai. Silakan reboot sistem untuk menerapkan perubahan.${NC}"
}

# Panggil fungsi utama
main_optimization

# Menu utama
while true; do
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            ${MAGENTA}VPS OPTIMIZER${CYAN}                      ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ 1) Optimasi Batas File dan Proses             ║${NC}"
    echo -e "${CYAN}║ 2) Optimasi Sysctl (fs.file-max)              ║${NC}"
    echo -e "${CYAN}║ 3) Optimasi LXC (Proxmox)                     ║${NC}"
    echo -e "${CYAN}║ 4) Optimasi Jaringan (BBR)                    ║${NC}"
    echo -e "${CYAN}║ 5) Optimasi SSH                               ║${NC}"
    echo -e "${CYAN}║ 6) Keluar                                     ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
    echo -ne "${YELLOW}Pilih opsi [1-6]: ${NC}"
    read -r choice

    case $choice in
        1) optimize_limits ;;
        2) optimize_sysctl ;;
        3) optimize_lxc ;;
        4) ask_bbr_version_1 ;;
        5) optimize_ssh_configuration ;;
        6) echo -e "${RED}Keluar...${NC}"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid. Silakan coba lagi.${NC}" ;;
    esac

    echo -e "\n${YELLOW}Tekan Enter untuk melanjutkan...${NC}"
    read -r
done
