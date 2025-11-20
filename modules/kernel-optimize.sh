#!/bin/bash

#================================================================================
# Linux 内核优化脚本 (Debian 13 优化版)
# 适用系统: Debian 12+, Ubuntu 20+
# 功能: TCP BBR, 文件句柄限制, 网络优化, 系统性能调优
#================================================================================

set -euo pipefail

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#--- 日志函数 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    
    case "$level" in
        "info")    echo -e "${GREEN}[INFO]${NC} $msg" ;;
        "warn")    echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        "error")   echo -e "${RED}[ERROR]${NC} $msg" ;;
        "success") echo -e "${BLUE}[SUCCESS]${NC} $msg" ;;
    esac
}

#--- 权限检查 ---
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log "此脚本需要 root 权限运行。" "error"
        log "请使用: sudo $0" "info"
        exit 1
    fi
}

#--- 备份文件 ---
backup_file() {
    local file="$1"
    if [[ -f "$file" && ! -f "${file}.bak" ]]; then
        cp "$file" "${file}.bak"
        log "已备份: $file -> ${file}.bak" "info"
    fi
}

#--- 配置系统资源限制 ---
configure_limits() {
    log "配置系统资源限制..." "info"
    
    local limits_file="/etc/security/limits.conf"
    backup_file "$limits_file"
    
    if [[ -e /etc/security/limits.d/*nproc.conf ]]; then
        for f in /etc/security/limits.d/*nproc.conf; do
            mv "$f" "${f%.conf}.conf_bak" 2>/dev/null || true
        done
    fi
    
    if [[ -f /etc/pam.d/common-session ]]; then
        if ! grep -q 'session required pam_limits.so' /etc/pam.d/common-session; then
            echo "session required pam_limits.so" >> /etc/pam.d/common-session
            log "已添加 PAM limits 模块到 common-session" "info"
        fi
    fi
    
    sed -i '/^# End of file/,$d' "$limits_file"
    
    cat >> "$limits_file" <<'EOF'
# End of file
# 优化资源限制 - Debian 13 优化配置
*     soft   nofile    1048576
*     hard   nofile    1048576
*     soft   nproc     1048576
*     hard   nproc     1048576
*     soft   core      1048576
*     hard   core      1048576
*     hard   memlock   unlimited
*     soft   memlock   unlimited

root  soft   nofile    1048576
root  hard   nofile    1048576
root  soft   nproc     1048576
root  hard   nproc     1048576
root  soft   core      1048576
root  hard   core      1048576
root  hard   memlock   unlimited
root  soft   memlock   unlimited
EOF
    
    log "系统资源限制配置完成。" "success"
}

#--- 配置内核参数 ---
configure_sysctl() {
    log "配置内核参数优化..." "info"
    
    local sysctl_file="/etc/sysctl.d/99-kernel-optimize.conf"
    backup_file "$sysctl_file"
    
    local params=(
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
        sed -i "/^${param//./\\.}/d" /etc/sysctl.conf 2>/dev/null || true
    done
    
    cat > "$sysctl_file" <<'EOF'
# Kernel Optimization for Debian 13+
# 文件系统优化
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192

# 网络核心优化
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

# TCP/UDP 缓冲区优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.udp_mem = 65536 131072 262144

# TCP 性能优化
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

# IP 转发和路由优化
net.ipv4.conf.all.route_localnet = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
EOF
    
    log "内核参数配置完成。" "success"
}

#--- 配置 TCP BBR ---
configure_bbr() {
    log "配置 TCP BBR 拥塞控制算法..." "info"
    
    if ! modprobe tcp_bbr 2>/dev/null; then
        log "无法加载 tcp_bbr 模块，可能内核不支持。" "warn"
        return 1
    fi
    
    if ! grep -wq bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        log "当前内核不支持 BBR 拥塞控制。" "warn"
        return 1
    fi
    
    local sysctl_file="/etc/sysctl.d/99-kernel-optimize.conf"
    
    if ! grep -q "net.core.default_qdisc" "$sysctl_file" 2>/dev/null; then
        echo "net.core.default_qdisc = fq" >> "$sysctl_file"
    fi
    
    if ! grep -q "net.ipv4.tcp_congestion_control" "$sysctl_file" 2>/dev/null; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$sysctl_file"
    fi
    
    if ! grep -q "tcp_bbr" /etc/modules 2>/dev/null; then
        echo "tcp_bbr" >> /etc/modules
    fi
    
    log "TCP BBR 配置完成。" "success"
    return 0
}

#--- 应用配置 ---
apply_sysctl() {
    log "应用 sysctl 配置..." "info"
    
    local sysctl_file="/etc/sysctl.d/99-kernel-optimize.conf"
    
    if [[ -f "$sysctl_file" ]]; then
        if sysctl -p "$sysctl_file" >/dev/null 2>&1; then
            log "sysctl 配置应用成功。" "success"
        else
            log "sysctl 配置应用时出现警告，部分参数可能不支持。" "warn"
            sysctl -p "$sysctl_file" 2>&1 | grep -i "error" || true
        fi
    fi
    
    if sysctl -p /etc/sysctl.conf >/dev/null 2>&1; then
        log "全局 sysctl 配置应用成功。" "success"
    else
        log "全局 sysctl 配置应用时出现警告。" "warn"
    fi
}

#--- 验证配置 ---
verify_configuration() {
    log "验证配置..." "info"
    
    echo
    echo "=== 当前配置状态 ==="
    
    echo -n "文件句柄限制: "
    cat /proc/sys/fs/file-max
    
    echo -n "TCP 拥塞控制算法: "
    cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "N/A"
    
    echo -n "可用拥塞控制算法: "
    cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "N/A"
    
    echo -n "默认队列调度算法: "
    cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "N/A"
    
    echo -n "最大连接队列: "
    cat /proc/sys/net/core/somaxconn 2>/dev/null || echo "N/A"
    
    echo
}

#--- 主程序 ---
main() {
    log "开始 Linux 内核优化 (Debian 13 优化版)..." "info"
    echo
    
    check_root
    
    configure_limits
    echo
    
    configure_sysctl
    echo
    
    configure_bbr
    echo
    
    apply_sysctl
    echo
    
    verify_configuration
    
    log "内核优化完成！" "success"
    log "部分配置需要重启系统后才能完全生效。" "warn"
    log "建议执行: reboot" "info"
    
    if [[ -f ~/.bashrc ]]; then
        source ~/.bashrc 2>/dev/null || true
    fi
}

trap 'log "脚本在行号 $LINENO 处意外退出" "error"; exit 1' ERR

main "$@"
