#!/bin/bash
#
# ==============================================================================
# Network Performance Optimization Script v5.0
#
#
# This script optimizes network performance on modern Linux systems (Debian 13+)
# by configuring:
#   - BBR congestion control
#   - fq_codel queue discipline
#   - TCP Fast Open (TFO)
#   - Multi-Path TCP (MPTCP)
#   - System resource limits (file descriptors, etc.)
#
# Changelog (v5.0):
#   - [Modernization] Use /etc/sysctl.d/ and /etc/security/limits.d/ for
#     configuration, avoiding modification of main system files. This is the
#     recommended practice for modern systems like Debian 13.
#   - [Robustness] Added root privileges and dependency checks at startup.
#   - [Maintainability] Refactored MPTCP parameter configuration into a loop
#     for cleaner and more maintainable code.
#   - [Automation] Added a '-y' / '--yes' flag for non-interactive execution.
#   - [Clarity] Enhanced comments to explain the purpose of key parameters.
#   - [Simplicity] Removed complex sed operations, as we now write to dedicated
#     config files.
# ==============================================================================

set -euo pipefail

# === Configuration Files ===
# Use dedicated files in .d directories for cleaner system management.
readonly SYSCTL_CONFIG_FILE="/etc/sysctl.d/99-network-opt.conf"
readonly LIMITS_CONFIG_FILE="/etc/security/limits.d/99-network-opt.conf"

# === Global Variables ===
MPTCP_SUPPORTED_COUNT=0
MPTCP_TOTAL_COUNT=0
MPTCP_CONFIG_TEXT=""
UNATTENDED=false

# === Logging Function ===
# Provides colored output for different message levels.
log() {
    local msg="$1" level="${2:-info}"
    # Color map: info=cyan, warn=yellow, error=red, success=green
    local -A colors=(
        [info]="\033[0;36m"
        [warn]="\033[0;33m"
        [error]="\033[0;31m"
        [success]="\033[0;32m"
    )
    # Default to green if level is not in the map
    echo -e "${colors[$level]:-\033[0;32m}$msg\033[0m"
}

# === Pre-flight Checks ===
# Ensures the script is run with proper permissions and dependencies.
run_pre_flight_checks() {
    # Check for root privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        log "错误: 此脚本必须以 root 权限运行。" "error"
        log "请尝试使用 'sudo ./your_script_name.sh'" "error"
        exit 1
    fi

    # Check for required commands (iproute2 package)
    if ! command -v ip &>/dev/null || ! command -v tc &>/dev/null; then
        log "错误: 缺少 'iproute2' 包，它是运行此脚本所必需的。" "error"
        log "在 Debian/Ubuntu 上，请使用 'sudo apt update && sudo apt install iproute2' 安装。" "error"
        exit 1
    fi

    # Parse command-line arguments for unattended mode
    if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
        UNATTENDED=true
        log "已启用无人值守模式。脚本将不会请求用户确认。" "warn"
    fi
}

# === Detection Functions ===
# Detects network interfaces and kernel feature support.
detect_main_interface() {
    # Find the interface used for the default route.
    local interface
    interface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')
    if [[ -n "$interface" ]]; then
        echo "$interface"
    else
        return 1
    fi
}

check_bbr_support() {
    log "检查 BBR 支持..." "info"
    # BBR is standard in modern kernels (like in Debian 13).
    # This check ensures it's either available as a module or built-in.
    if modprobe tcp_bbr 2>/dev/null; then
        log "✓ BBR 模块可加载" "success"
        return 0
    fi

    if [[ -f "/proc/config.gz" ]] && zcat /proc/config.gz | grep -q "CONFIG_TCP_BBR=[ym]"; then
        log "✓ BBR 内建于内核" "success"
        return 0
    fi

    log "✗ 系统不支持 BBR。无法继续优化。" "error"
    return 1
}

check_mptcp_support() {
    # MPTCP is enabled if this proc file exists.
    [[ -f "/proc/sys/net/mptcp/enabled" ]]
}

check_sysctl_param() {
    # Generic function to check if a sysctl parameter exists.
    local param_file="/proc/sys/${1//./\/}"
    [[ -f "$param_file" ]]
}

# === Configuration Functions ===
# Applies the actual system configurations.
configure_mptcp_params() {
    MPTCP_SUPPORTED_COUNT=0
    MPTCP_CONFIG_TEXT=""

    if ! check_mptcp_support; then
        log "⚠ 系统不支持 MPTCP，将跳过相关配置。" "warn"
        MPTCP_CONFIG_TEXT=$'\n# MPTCP: Not supported by the kernel.'
        return
    fi

    log "检测 MPTCP 参数支持..." "info"

    # A map of MPTCP parameters and their desired values.
    # Refactored for better readability and maintainability.
    local -A mptcp_params=(
        ["net.mptcp.enabled"]="1"
        ["net.mptcp.allow_join_initial_addr_port"]="1"
        ["net.mptcp.pm_type"]="0" # 0=default, 1=in-kernel, 2=userspace
        ["net.mptcp.checksum_enabled"]="0" # Disable for performance gain
        ["net.mptcp.stale_loss_cnt"]="4"
        ["net.mptcp.add_addr_timeout"]="60000"
        ["net.mptcp.close_timeout"]="30000"
        ["net.mptcp.scheduler"]="default"
    )
    MPTCP_TOTAL_COUNT=${#mptcp_params[@]}

    MPTCP_CONFIG_TEXT=$'\n# MPTCP 优化配置'
    for param in "${!mptcp_params[@]}"; do
        if check_sysctl_param "$param"; then
            MPTCP_CONFIG_TEXT+=$'\n'"$param = ${mptcp_params[$param]}"
            log "  ✓ 支持: $param" "success"
            ((MPTCP_SUPPORTED_COUNT++))
        else
            log "  ✗ 跳过: $param" "warn"
        fi
    done

    log "MPTCP 参数检测完成: 支持 $MPTCP_SUPPORTED_COUNT/$MPTCP_TOTAL_COUNT 个参数" "info"
}

configure_system_limits() {
    log "配置系统资源限制..." "info"

    # Create a dedicated limits configuration file.
    # This is cleaner than modifying /etc/security/limits.conf.
    cat > "$LIMITS_CONFIG_FILE" << 'EOF'
# This file was generated by the network optimization script.
# It increases the limits for file descriptors and processes.

# Default limits for all users
* soft   nofile    1048576
* hard   nofile    1048576
* soft   nproc     1048576
* hard   nproc     1048576
* hard   memlock   unlimited
* soft   memlock   unlimited

# Overrides for the root user
root  soft   nofile    1048576
root  hard   nofile    1048576
root  soft   nproc     1048576
root  hard   nproc     1048576
root  hard   memlock   unlimited
root  soft   memlock   unlimited
EOF

    # Ensure PAM uses the limits module.
    if [[ -f /etc/pam.d/common-session ]] && ! grep -q 'session required pam_limits.so' /etc/pam.d/common-session; then
        echo "session required pam_limits.so" >> /etc/pam.d/common-session
    fi

    log "✓ 系统资源限制已写入 '$LIMITS_CONFIG_FILE'" "success"
}

configure_network_parameters() {
    log "配置网络核心参数..." "info"

    # First, configure MPTCP parameters based on kernel support.
    configure_mptcp_params

    # Now, write all network parameters to a dedicated sysctl file.
    # This avoids modifying /etc/sysctl.conf and simplifies management.
    cat > "$SYSCTL_CONFIG_FILE" << EOF
# ==============================================================================
# This file was generated by the network optimization script.
# Date: $(date +"%Y-%m-%d %H:%M")
#
# It applies a set of sysctl parameters to optimize network performance.
# Features: BBR + fq_codel + TFO + MPTCP ($MPTCP_SUPPORTED_COUNT/$MPTCP_TOTAL_COUNT supported)
# ==============================================================================

# 文件系统优化 (提高文件句柄上限)
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192

# 网络核心参数 (增大队列和缓冲区)
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

# UDP 缓冲区优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = 65536 131072 262144

# TCP 缓冲区优化
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216

# TCP 连接优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.route.gc_timeout = 100
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
# 禁用时间戳 (可减少开销，但在某些网络下可能影响性能测量)
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_no_metrics_save = 1

# TCP 高级参数
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

# 路由和转发 (如有需要)
net.ipv4.conf.all.route_localnet = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1

# --- 核心优化: BBR + FQ_CODEL ---
# 队列调度算法: fq_codel (公平队列，减少延迟抖动)
# 备选: cake (更现代的算法，但在某些场景下 CPU 占用稍高)
net.core.default_qdisc = fq_codel
# 拥塞控制算法: bbr (Google 出品，显著提升高延迟、有丢包网络下的吞吐量)
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open (TFO): 减少连续 TCP 连接的握手延迟
net.ipv4.tcp_fastopen = 3
${MPTCP_CONFIG_TEXT}
EOF

    log "✓ 网络参数已写入 '$SYSCTL_CONFIG_FILE'" "success"

    # Apply the new settings
    log "应用 sysctl 配置..." "info"
    local sysctl_output
    local sysctl_exitcode=0
    sysctl_output=$(sysctl --system 2>&1) || sysctl_exitcode=$?

    if [[ $sysctl_exitcode -eq 0 ]]; then
        log "✓ 所有 sysctl 参数应用成功" "success"
    else
        log "⚠ sysctl 应用时遇到一些问题，正在分析..." "warn"
        # Filter for unsupported parameters
        local unsupported_params
        unsupported_params=$(echo "$sysctl_output" | grep -E "cannot stat|unknown key" || true)
        if [[ -n "$unsupported_params" ]]; then
            log "以下参数不被当前内核支持 (可安全忽略):" "warn"
            echo "$unsupported_params" | sed 's/^/  ✗ /'
        else
            log "未能识别的错误，请检查以上输出。" "error"
            echo "$sysctl_output"
        fi
    fi
}

configure_interface_qdisc() {
    local interface="$1"
    log "为网卡 '$interface' 配置队列调度..." "info"

    # Attempt to set qdisc to fq_codel directly on the interface.
    # This is a runtime setting and complements the default in sysctl.
    if tc qdisc show dev "$interface" 2>/dev/null | grep -q "fq_codel"; then
        log "✓ 网卡 '$interface' 已在使用 fq_codel 队列" "success"
    elif tc qdisc replace dev "$interface" root fq_codel 2>/dev/null; then
        log "✓ 网卡 '$interface' 队列已实时切换为 fq_codel" "success"
    else
        log "✗ 无法为网卡 '$interface' 实时切换队列 (可能已被其他程序管理)" "warn"
    fi
}

# === Verification and Summary ===
# Displays the final state of the system.
show_network_summary() {
    echo
    log "====================== 🎯 网络优化摘要 ======================" "info"

    local current_cc current_qdisc current_tfo
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    current_tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "0")

    # Core components status
    [[ "$current_cc" == "bbr" ]] && log "  [✓] BBR          : 已启用" "success" || log "  [✗] BBR          : $current_cc (未启用)" "warn"
    [[ "$current_qdisc" == "fq_codel" ]] && log "  [✓] fq_codel     : 已设为默认" "success" || log "  [✗] fq_codel     : $current_qdisc (未启用)" "warn"
    [[ "$current_tfo" == "3" ]] && log "  [✓] TCP Fast Open: 已启用" "success" || log "  [✗] TFO          : $current_tfo (未启用)" "warn"

    # MPTCP status
    if check_mptcp_support; then
        local current_mptcp
        current_mptcp=$(sysctl -n net.mptcp.enabled 2>/dev/null || echo "0")
        if [[ "$current_mptcp" == "1" ]]; then
            log "  [✓] MPTCP        : 已启用 ($MPTCP_SUPPORTED_COUNT/$MPTCP_TOTAL_COUNT 参数)" "success"
        else
            log "  [✗] MPTCP        : 未启用" "warn"
        fi
    else
        log "  [!] MPTCP        : 系统不支持" "info"
    fi

    # Limits status
    if [[ -f "$LIMITS_CONFIG_FILE" ]] && grep -q "nofile.*1048576" "$LIMITS_CONFIG_FILE" 2>/dev/null; then
        log "  [✓] 资源限制   : 已配置" "success"
    else
        log "  [✗] 资源限制   : 未配置" "warn"
    fi

    # Interface qdisc status
    local interface
    if interface=$(detect_main_interface); then
        if tc qdisc show dev "$interface" 2>/dev/null | grep -q "fq_codel"; then
            log "  [✓] 网卡 '$interface' : 正在使用 fq_codel" "success"
        else
            log "  [!] 网卡 '$interface' :未使用 fq_codel (建议重启使配置生效)" "warn"
        fi
    else
        log "  [✗] 网卡检测     : 失败" "warn"
    fi
     log "================================================================" "info"
}

# === Main Execution Logic ===
main() {
    run_pre_flight_checks "$@"

    log "🚀 启动网络性能优化脚本 v5.0" "info"
    echo
    log "此脚本将通过调整内核参数来优化网络性能。" "info"
    log "主要功能包括启用 BBR、fq_codel、TFO 和 MPTCP。" "info"
    log "配置文件将写入 /etc/sysctl.d/ 和 /etc/security/limits.d/ 目录。" "info"
    echo

    if ! $UNATTENDED; then
        read -p "是否继续进行网络性能优化? [Y/n]: " -r choice
        if [[ "$choice" =~ ^[Nn]$ ]]; then
            log "操作已取消。" "info"
            exit 0
        fi
    fi

    # --- Step 1: Check prerequisites ---
    if ! check_bbr_support; then
        exit 1
    fi

    local interface
    if ! interface=$(detect_main_interface); then
        log "✗ 未能自动检测到主网络接口。无法继续。" "error"
        exit 1
    fi
    log "检测到主网络接口: $interface" "info"

    # --- Step 2: Apply configurations ---
    configure_system_limits
    configure_network_parameters
    configure_interface_qdisc "$interface"

    # --- Step 3: Show summary ---
    show_network_summary

    echo
    log "🎉 网络优化配置完成!" "success"
    log "为了使所有设置（特别是资源限制）完全生效，建议您重启系统。" "warn"
    echo
    log "常用检查命令:" "info"
    log "  - 查看拥塞控制: sysctl net.ipv4.tcp_congestion_control"
    log "  - 查看队列调度: sysctl net.core.default_qdisc"
    log "  - 查看网卡队列: tc qdisc show dev $interface"
    log "  - 查看 MPTCP 状态: sysctl net.mptcp.enabled"
}

# Run the main function with all script arguments
main "$@"
