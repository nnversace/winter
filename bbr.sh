#!/bin/bash
# Linux Kernel Optimization
# Supported platforms: CentOS/RedHat 7+, Debian 9+, and Ubuntu 16+

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查root权限
[ "$(id -u)" != "0" ] && { echo -e "${RED}Error: You must be root to run this script${NC}"; exit 1; }

# 备份和处理limits配置
[ -e /etc/security/limits.d/*nproc.conf ] && rename nproc.conf nproc.conf_bk /etc/security/limits.d/*nproc.conf
[ -f /etc/pam.d/common-session ] && [ -z "$(grep 'session required pam_limits.so' /etc/pam.d/common-session)" ] && echo "session required pam_limits.so" >> /etc/pam.d/common-session

# 配置系统限制
sed -i '/^# End of file/,$d' /etc/security/limits.conf
cat >> /etc/security/limits.conf <<EOF
# End of file
*     soft   nofile    1048576
*     hard   nofile    1048576
*     soft   nproc     1048576
*     hard   nproc     1048576
*     soft   core      1048576
*     hard   core      1048576
*     hard   memlock   unlimited
*     soft   memlock   unlimited

root     soft   nofile    1048576
root     hard   nofile    1048576
root     soft   nproc     1048576
root     hard   nproc     1048576
root     soft   core      1048576
root     hard   core      1048576
root     hard   memlock   unlimited
root     soft   memlock   unlimited
EOF

# 清理已存在的内核参数
echo -e "${YELLOW}Cleaning existing kernel parameters...${NC}"
declare -a params=(
    "fs.file-max"
    "fs.inotify.max_user_instances"
    "net.core.somaxconn"
    "net.core.netdev_max_backlog"
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.ipv4.udp_rmem_min"
    "net.ipv4.udp_wmem_min"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
    "net.ipv4.tcp_mem"
    "net.ipv4.udp_mem"
    "net.ipv4.tcp_syncookies"
    "net.ipv4.tcp_fin_timeout"
    "net.ipv4.tcp_tw_reuse"
    "net.ipv4.ip_local_port_range"
    "net.ipv4.tcp_max_syn_backlog"
    "net.ipv4.tcp_max_tw_buckets"
    "net.ipv4.route.gc_timeout"
    "net.ipv4.tcp_syn_retries"
    "net.ipv4.tcp_synack_retries"
    "net.ipv4.tcp_timestamps"
    "net.ipv4.tcp_max_orphans"
    "net.ipv4.tcp_no_metrics_save"
    "net.ipv4.tcp_ecn"
    "net.ipv4.tcp_frto"
    "net.ipv4.tcp_mtu_probing"
    "net.ipv4.tcp_rfc1337"
    "net.ipv4.tcp_sack"
    "net.ipv4.tcp_fack"
    "net.ipv4.tcp_window_scaling"
    "net.ipv4.tcp_adv_win_scale"
    "net.ipv4.tcp_moderate_rcvbuf"
    "net.ipv4.tcp_keepalive_time"
    "net.ipv4.tcp_notsent_lowat"
    "net.ipv4.conf.all.route_localnet"
    "net.ipv4.ip_forward"
    "net.ipv4.conf.all.forwarding"
    "net.ipv4.conf.default.forwarding"
    "net.core.default_qdisc"
    "net.ipv4.tcp_congestion_control"
)

for param in "${params[@]}"; do
    sed -i "/${param//./\\.}/d" /etc/sysctl.conf
done

# 配置新的内核参数
echo -e "${YELLOW}Configuring new kernel parameters...${NC}"
cat >> /etc/sysctl.conf << EOF
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.route.gc_timeout = 100
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.conf.all.route_localnet = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
EOF

# 配置BBR
modprobe tcp_bbr &>/dev/null
if grep -wq bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo -e "${GREEN}BBR has been enabled${NC}"
else
    echo -e "${YELLOW}BBR is not available on this system${NC}"
fi

# 应用所有配置
echo -e "${YELLOW}Applying all configurations...${NC}"
sysctl -p && clear

# 显示优化结果
echo -e "${GREEN}System Optimization Results:${NC}"
echo -e "File descriptor limit: $(ulimit -n)"
echo -e "Max processes: $(ulimit -u)"
echo -e "TCP congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "BBR status: $(if lsmod | grep -q bbr; then echo "enabled"; else echo "disabled"; fi)"

echo -e "\n${GREEN}System optimization completed successfully!${NC}"
echo -e "${YELLOW}Please reboot your system to apply all changes.${NC}"
