#!/bin/bash

#================================================================================
# Linux 内核优化脚本 (Debian 13 专属优化版)
# 适用系统: Debian 12+, Ubuntu 20+
# 功能: TCP BBR, 文件句柄限制, 网络优化, IPv4/IPv6 转发, 系统性能调优
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

#--- 检测 Debian 版本 ---
detect_debian_version() {
    if [[ -f /etc/debian_version ]]; then
        local debian_version
        debian_version=$(cat /etc/debian_version)
        if [[ "$debian_version" =~ trixie|sid ]]; then
            log "检测到 Debian 13+ (Trixie/Sid)，应用专属优化配置。" "info"
            return 0
        elif [[ "$debian_version" =~ ^[0-9]+$ ]] && (( debian_version >= 12 )); then
            log "检测到 Debian $debian_version，应用优化配置。" "info"
            return 0
        fi
    fi
    log "未检测到 Debian 12+ 系统，配置可能需要调整。" "warn"
    return 1
}

#--- 配置系统资源限制 ---
configure_limits() {
    log "配置系统资源限制..." "info"
    
    local limits_file="/etc/security/limits.conf"
    backup_file "$limits_file"
    
    # 处理旧的 nproc 配置文件
    if [[ -e /etc/security/limits.d/*nproc.conf ]]; then
        for f in /etc/security/limits.d/*nproc.conf; do
            [[ -f "$f" ]] && mv "$f" "${f%.conf}.conf_bak" 2>/dev/null || true
        done
    fi
    
    # 确保 PAM 加载 limits 模块
    if [[ -f /etc/pam.d/common-session ]]; then
        if ! grep -q 'session required pam_limits.so' /etc/pam.d/common-session; then
            echo "session required pam_limits.so" >> /etc/pam.d/common-session
            log "已添加 PAM limits 模块到 common-session" "info"
        fi
    fi
    
    # 移除旧的 "End of file" 标记及其后的内容
    sed -i '/^# End of file/,$d' "$limits_file"
    
    # 添加优化的资源限制配置
    cat >> "$limits_file" <<'EOF'
# End of file
# 系统资源限制优化 - Debian 13 专属配置
# 文件句柄、进程数、核心转储、内存锁定限制

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

#--- 清理旧的 sysctl 配置 ---
cleanup_old_sysctl() {
    log "清理旧的 sysctl 配置..." "info"
    
    local params=(
        "fs.file-max"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.udp_rmem_min"
        "net.ipv4.udp_wmem_min"
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
        "net.ipv4.ip_forward"
        "net.ipv4.conf.all.route_localnet"
        "net.ipv4.conf.all.forwarding"
        "net.ipv4.conf.default.forwarding"
        "net.core.default_qdisc"
        "net.ipv4.tcp_congestion_control"
        "net.ipv6.conf.all.forwarding"
        "net.ipv6.conf.default.forwarding"
    )
    
    # 从主配置文件中移除这些参数，避免冲突
    for param in "${params[@]}"; do
        sed -i "/^${param//./\\.}/d" /etc/sysctl.conf 2>/dev/null || true
    done
}

#--- 配置内核参数 (Debian 13 专属) ---
configure_sysctl() {
    log "配置内核参数优化 (Debian 13 专属参数)..." "info"
    
    local sysctl_file="/etc/sysctl.d/99-kernel-optimize.conf"
    backup_file "$sysctl_file"
    
    cleanup_old_sysctl
    
    cat > "$sysctl_file" <<'EOF'
#================================================================================
# Kernel Optimization for Debian 13+
# 专为 Debian 13 (Trixie/Sid) 优化的内核参数
#================================================================================

#--- 文件系统优化 ---
# 系统级别打开文件描述符的最大数量
fs.file-max = 6815744

#--- 网络核心优化 ---
# 接收缓冲区最大值 (16MB)
net.core.rmem_max = 16777216
# 发送缓冲区最大值 (16MB)
net.core.wmem_max = 16777216
# 默认队列调度算法 (fq: Fair Queue，与 BBR 配合使用)
net.core.default_qdisc = fq

#--- TCP 缓冲区优化 ---
# TCP 接收缓冲区: 最小值 4KB, 默认值 ~85KB, 最大值 16MB
net.ipv4.tcp_rmem = 4096 87380 16777216
# TCP 发送缓冲区: 最小值 4KB, 默认值 64KB, 最大值 16MB
net.ipv4.tcp_wmem = 4096 65536 16777216

#--- UDP 缓冲区优化 ---
# UDP 接收缓冲区最小值 (8KB)
net.ipv4.udp_rmem_min = 8192
# UDP 发送缓冲区最小值 (8KB)
net.ipv4.udp_wmem_min = 8192

#--- TCP 性能优化 ---
# 禁用 TCP 连接指标缓存，每次连接重新探测
net.ipv4.tcp_no_metrics_save = 1
# 禁用显式拥塞通知 (ECN)
net.ipv4.tcp_ecn = 0
# 禁用快速重传恢复 (F-RTO)
net.ipv4.tcp_frto = 0
# 禁用 TCP MTU 探测
net.ipv4.tcp_mtu_probing = 0
# 禁用 RFC1337 TIME-WAIT 暗杀防护
net.ipv4.tcp_rfc1337 = 0
# 启用选择性确认 (SACK)
net.ipv4.tcp_sack = 1
# 启用转发确认 (FACK)
net.ipv4.tcp_fack = 1
# 启用 TCP 窗口缩放
net.ipv4.tcp_window_scaling = 1
# TCP 窗口缩放因子
net.ipv4.tcp_adv_win_scale = 1
# 启用接收缓冲区自动调整
net.ipv4.tcp_moderate_rcvbuf = 1

#--- BBR 拥塞控制算法 ---
# 使用 BBR (Bottleneck Bandwidth and Round-trip propagation time)
net.ipv4.tcp_congestion_control = bbr

#--- IPv4 转发和路由优化 ---
# 启用 IPv4 包转发
net.ipv4.ip_forward = 1
# 允许本地路由
net.ipv4.conf.all.route_localnet = 1
# 启用所有接口的 IPv4 转发
net.ipv4.conf.all.forwarding = 1
# 启用默认接口的 IPv4 转发
net.ipv4.conf.default.forwarding = 1

#--- IPv6 转发优化 ---
# 启用所有接口的 IPv6 转发
net.ipv6.conf.all.forwarding = 1
# 启用默认接口的 IPv6 转发
net.ipv6.conf.default.forwarding = 1
EOF
    
    log "内核参数配置完成 (已应用 Debian 13 专属参数)。" "success"
}

#--- 配置 TCP BBR ---
configure_bbr() {
    log "配置 TCP BBR 拥塞控制算法..." "info"
    
    # 尝试加载 BBR 模块
    if ! modprobe tcp_bbr 2>/dev/null; then
        log "无法加载 tcp_bbr 模块，可能内核不支持。" "warn"
        return 1
    fi
    
    # 检查内核是否支持 BBR
    if ! grep -wq bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        log "当前内核不支持 BBR 拥塞控制。" "warn"
        log "Debian 13 默认内核应该支持 BBR，请检查内核版本。" "warn"
        return 1
    fi
    
    # 确保 BBR 模块在启动时加载
    if ! grep -q "tcp_bbr" /etc/modules 2>/dev/null; then
        echo "tcp_bbr" >> /etc/modules
        log "已添加 tcp_bbr 到 /etc/modules，确保开机自动加载。" "info"
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
    
    # 应用全局 sysctl 配置
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
    echo "================================================================================"
    echo "                        当前内核配置状态"
    echo "================================================================================"
    echo
    
    # 文件系统
    echo "【文件系统】"
    echo -n "  文件句柄限制 (fs.file-max): "
    cat /proc/sys/fs/file-max 2>/dev/null || echo "N/A"
    echo
    
    # TCP BBR
    echo "【TCP BBR 拥塞控制】"
    echo -n "  当前算法: "
    cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "N/A"
    echo -n "  可用算法: "
    cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "N/A"
    echo -n "  队列调度: "
    cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "N/A"
    echo
    
    # 网络缓冲区
    echo "【网络缓冲区】"
    echo -n "  接收缓冲区最大值 (rmem_max): "
    cat /proc/sys/net/core/rmem_max 2>/dev/null || echo "N/A"
    echo -n "  发送缓冲区最大值 (wmem_max): "
    cat /proc/sys/net/core/wmem_max 2>/dev/null || echo "N/A"
    echo
    
    # TCP 优化
    echo "【TCP 优化】"
    echo -n "  SACK (选择性确认): "
    cat /proc/sys/net/ipv4/tcp_sack 2>/dev/null || echo "N/A"
    echo -n "  窗口缩放: "
    cat /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null || echo "N/A"
    echo -n "  接收缓冲区自动调整: "
    cat /proc/sys/net/ipv4/tcp_moderate_rcvbuf 2>/dev/null || echo "N/A"
    echo
    
    # IP 转发
    echo "【IP 转发】"
    echo -n "  IPv4 转发: "
    cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "N/A"
    echo -n "  IPv6 转发: "
    cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo "N/A"
    echo
    
    echo "================================================================================"
    echo
}

#--- 显示优化建议 ---
show_recommendations() {
    echo
    echo "================================================================================"
    echo "                        优化建议"
    echo "================================================================================"
    echo
    echo "1. 重启系统以确保所有配置完全生效:"
    echo "   sudo reboot"
    echo
    echo "2. 重启后验证 BBR 是否启用:"
    echo "   sysctl net.ipv4.tcp_congestion_control"
    echo "   lsmod | grep bbr"
    echo
    echo "3. 检查文件句柄限制:"
    echo "   ulimit -n"
    echo
    echo "4. 监控网络性能:"
    echo "   ss -s"
    echo "   netstat -s | grep -i tcp"
    echo
    echo "5. 如需回滚配置:"
    echo "   sudo rm /etc/sysctl.d/99-kernel-optimize.conf"
    echo "   sudo cp /etc/security/limits.conf.bak /etc/security/limits.conf"
    echo "   sudo sysctl --system"
    echo
    echo "================================================================================"
    echo
}

#--- 主程序 ---
main() {
    log "开始 Linux 内核优化 (Debian 13 专属优化版)..." "info"
    echo
    
    check_root
    detect_debian_version
    echo
    
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
    log "所有参数已针对 Debian 13 进行优化。" "success"
    
    show_recommendations
    
    if [[ -f ~/.bashrc ]]; then
        source ~/.bashrc 2>/dev/null || true
    fi
}

trap 'log "脚本在行号 $LINENO 处意外退出" "error"; exit 1' ERR

main "$@"
