#!/bin/bash
# 一键 Linux 内核优化脚本
# 支持平台：CentOS/RedHat 7+, Debian 9+, Ubuntu 16+

set -euo pipefail  # 启用严格的错误处理

# 日志文件
LOG_FILE="/var/log/kernel_optimization.log"

# 函数：记录日志
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $*" | tee -a "$LOG_FILE"
}

# 函数：创建备份
backup_file() {
    local file="$1"
    if [ -e "$file" ]; then
        local backup="${file}.bak.$(date +%F_%T)"
        cp -a "$file" "$backup"
        log "备份文件已创建: $backup"
    else
        log "文件不存在，跳过备份: $file"
    fi
}

# 检查是否以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：必须以 root 身份运行此脚本。" >&2
    exit 1
fi

log "开始执行 Linux 内核优化脚本。"

# 备份关键配置文件
backup_file /etc/security/limits.d/*nproc.conf
backup_file /etc/pam.d/common-session
backup_file /etc/security/limits.conf
backup_file /etc/sysctl.conf

# 备份完成后，继续执行优化步骤
log "备份完成，开始修改配置文件。"

# 1. 备份并重命名现有的 nproc.conf 文件
if ls /etc/security/limits.d/*nproc.conf &>/dev/null; then
    for file in /etc/security/limits.d/*nproc.conf; do
        mv "$file" "${file}_bk"
        log "重命名 $file 为 ${file}_bk"
    done
else
    log "未找到 nproc.conf 文件，跳过重命名步骤。"
fi

# 2. 确保 pam_limits.so 被包含在 common-session 中
PAM_SESSION_FILE="/etc/pam.d/common-session"
if [ -f "$PAM_SESSION_FILE" ]; then
    if ! grep -q 'session required pam_limits.so' "$PAM_SESSION_FILE"; then
        echo "session required pam_limits.so" >> "$PAM_SESSION_FILE"
        log "已将 'session required pam_limits.so' 添加到 $PAM_SESSION_FILE"
    else
        log "$PAM_SESSION_FILE 中已包含 'session required pam_limits.so'，无需添加。"
    fi
else
    log "文件不存在，跳过修改: $PAM_SESSION_FILE"
fi

# 3. 配置 /etc/security/limits.conf
LIMITS_CONF="/etc/security/limits.conf"
log "配置 $LIMITS_CONF"

# 删除从 "# End of file" 开始的所有行
sed -i '/^# End of file/,$d' "$LIMITS_CONF"

# 追加新的限制
cat >> "$LIMITS_CONF" <<EOF
# End of file
*     soft   nofile    1048576
*     hard   nofile    1048576
*     soft   nproc     1048576
*     hard   nproc     1048576
*     soft   core      1048576
*     hard   core      1048576
*     soft   memlock   unlimited
*     hard   memlock   unlimited

root     soft   nofile    1048576
root     hard   nofile    1048576
root     soft   nproc     1048576
root     hard   nproc     1048576
root     soft   core      1048576
root     hard   core      1048576
root     soft   memlock   unlimited
root     hard   memlock   unlimited
EOF

log "已更新 $LIMITS_CONF"

# 4. 配置 /etc/sysctl.conf
SYSCTL_CONF="/etc/sysctl.conf"
log "配置 $SYSCTL_CONF"

# 要移除的配置项
REMOVE_PATTERNS=(
    'fs.file-max'
    'fs.inotify.max_user_instances'
    'net.core.somaxconn'
    'net.core.netdev_max_backlog'
    'net.core.rmem_max'
    'net.core.wmem_max'
    'net.ipv4.udp_rmem_min'
    'net.ipv4.udp_wmem_min'
    'net.ipv4.tcp_rmem'
    'net.ipv4.tcp_wmem'
    'net.ipv4.tcp_mem'
    'net.ipv4.udp_mem'
    'net.ipv4.tcp_syncookies'
    'net.ipv4.tcp_fin_timeout'
    'net.ipv4.tcp_tw_reuse'
    'net.ipv4.ip_local_port_range'
    'net.ipv4.tcp_max_syn_backlog'
    'net.ipv4.tcp_max_tw_buckets'
    'net.ipv4.route.gc_timeout'
    'net.ipv4.tcp_syn_retries'
    'net.ipv4.tcp_synack_retries'
    'net.ipv4.tcp_timestamps'
    'net.ipv4.tcp_max_orphans'
    'net.ipv4.tcp_no_metrics_save'
    'net.ipv4.tcp_ecn'
    'net.ipv4.tcp_frto'
    'net.ipv4.tcp_mtu_probing'
    'net.ipv4.tcp_rfc1337'
    'net.ipv4.tcp_sack'
    'net.ipv4.tcp_fack'
    'net.ipv4.tcp_window_scaling'
    'net.ipv4.tcp_adv_win_scale'
    'net.ipv4.tcp_moderate_rcvbuf'
    'net.ipv4.tcp_keepalive_time'
    'net.ipv4.tcp_notsent_lowat'
    'net.ipv4.conf.all.route_localnet'
    'net.ipv4.ip_forward'
    'net.ipv4.conf.all.forwarding'
    'net.ipv4.conf.default.forwarding'
    'net.core.default_qdisc'
    'net.ipv4.tcp_congestion_control'
)

# 使用循环删除所有匹配的行
for pattern in "${REMOVE_PATTERNS[@]}"; do
    sed -i "/^$pattern/d" "$SYSCTL_CONF"
done

# 追加新的内核参数
cat >> "$SYSCTL_CONF" << EOF
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

log "已更新 $SYSCTL_CONF"

# 5. 启用 TCP BBR 拥塞控制
log "尝试启用 TCP BBR 拥塞控制。"
modprobe tcp_bbr &>/dev/null || log "加载 tcp_bbr 模块失败或已加载。"

if grep -wq bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    echo "net.core.default_qdisc = fq" >> "$SYSCTL_CONF"
    echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    log "已设置 TCP 拥塞控制为 BBR。"
else
    log "系统不支持 TCP BBR 拥塞控制，跳过设置。"
fi

# 6. 应用 sysctl 配置
log "应用 sysctl 配置。"
sysctl -p &>> "$LOG_FILE"

# 7. 清屏并显示成功消息
clear
echo "内核优化成功完成 - Powered by apad.pro" | tee -a "$LOG_FILE"
log "内核优化脚本执行完成。"

exit 0
