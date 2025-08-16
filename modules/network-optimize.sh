#!/bin/bash
#
# =================================================================
# Network Performance Optimization Script v5.0
#
# Features:
# - Enables BBR + FQ-CoDel for better throughput and latency.
# - Enables TCP Fast Open (TFO) to reduce connection latency.
# - Optimizes MPTCP parameters for multi-path scenarios.
# - Adjusts system limits (file descriptors, processes).
# - Provides 'apply', 'status', and 'revert' modes.
#
# Usage:
#   - Interactive: ./network-optimize.sh
#   - Apply directly: ./network-optimize.sh apply
#   - Show status:  ./network-optimize.sh status
#   - Revert changes: ./network-optimize.sh revert
# =================================================================

set -eo pipefail

# --- 全局常量 ---
readonly SYSCTL_CONFIG="/etc/sysctl.conf"
readonly LIMITS_CONFIG="/etc/security/limits.conf"
readonly SCRIPT_MARKER_START="# === Network Optimize Start ==="
readonly SCRIPT_MARKER_END="# === Network Optimize End ==="

# --- 日志和颜色 ---
C_RESET="\033[0m"
C_INFO="\033[0;36m"
C_WARN="\033[0;33m"
C_ERROR="\033[0;31m"
C_SUCCESS="\033[0;32m"

log() {
    local level="$1" color="$2" msg="$3"
    echo -e "${color}[${level}] ${msg}${C_RESET}"
}

info() { log "INFO" "${C_INFO}" "$1"; }
warn() { log "WARN" "${C_WARN}" "$1"; }
error() { log "ERROR" "${C_ERROR}" "$1"; exit 1; }
success() { log "SUCCESS" "${C_SUCCESS}" "$1"; }

# =================================================
# 辅助函数 (Checks & Detections)
# =================================================

check_root() {
    [[ "$(id -u)" -eq 0 ]] || error "此脚本必须以 root 权限运行。"
}

check_dependencies() {
    info "正在检查依赖项..."
    local missing=0
    for cmd in ip tc sysctl; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "命令 '$cmd' 未找到。请安装 'iproute2' 或相关工具包。"
            missing=1
        fi
    done
    [[ "$missing" -eq 0 ]] || error "缺少必要的依赖项。"
}

detect_main_interface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}'
}

check_bbr_support() {
    info "正在检查 BBR 支持..."
    if lsmod | grep -q "tcp_bbr"; then
        success "BBR 模块已加载。"
        return 0
    fi
    if modprobe tcp_bbr 2>/dev/null; then
        success "BBR 模块加载成功。"
        return 0
    fi
    if [[ -f "/proc/config.gz" ]] && zcat /proc/config.gz | grep -q "CONFIG_TCP_BBR=[ym]"; then
        success "内核已内建 BBR 支持。"
        return 0
    fi
    error "系统不支持 BBR。请升级到更新的内核版本 (>= 4.9)。"
}

# =================================================
# 配置函数 (Configuration)
# =================================================

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_orig="${file}.original"
        if [[ ! -f "$backup_orig" ]]; then
            cp "$file" "$backup_orig"
            info "已创建原始备份: ${backup_orig}"
        fi
        cp "$file" "${file}.backup"
        info "已创建本次操作的备份: ${file}.backup"
    fi
}

configure_mptcp() {
    local mptcp_config_text=""
    local supported_count=0
    local total_count=0

    if [[ ! -f "/proc/sys/net/mptcp/enabled" ]]; then
        warn "系统不支持 MPTCP，将跳过相关配置。"
        echo -e "\n# MPTCP not supported on this system."
        return
    fi
    
    info "正在检测并配置 MPTCP 参数..."
    
    # 定义 MPTCP 参数及其期望值
    declare -A mptcp_params=(
        ["net.mptcp.enabled"]=1
        ["net.mptcp.allow_join_initial_addr_port"]=1
        ["net.mptcp.pm_type"]=0
        ["net.mptcp.checksum_enabled"]=0
        ["net.mptcp.stale_loss_cnt"]=4
        ["net.mptcp.add_addr_timeout"]=60000
        ["net.mptcp.close_timeout"]=30000
        ["net.mptcp.scheduler"]="default"
    )
    
    mptcp_config_text+="\n# MPTCP Optimization"
    for param in "${!mptcp_params[@]}"; do
        total_count=$((total_count + 1))
        local param_path="/proc/sys/${param//./\/}"
        if [[ -f "$param_path" ]]; then
            mptcp_config_text+="\n${param} = ${mptcp_params[$param]}"
            supported_count=$((supported_count + 1))
        fi
    done
    
    info "MPTCP 参数配置完成 ($supported_count/$total_count supported)."
    echo "$mptcp_config_text"
}

apply_optimizations() {
    info "开始应用网络性能优化..."

    # 1. 备份配置文件
    backup_file "$SYSCTL_CONFIG"
    backup_file "$LIMITS_CONFIG"

    # 2. 配置系统资源限制
    info "正在配置系统资源限制 (/etc/security/limits.conf)..."
    sed -i '/^\*.*soft.*nofile/d' "$LIMITS_CONFIG"
    sed -i '/^\*.*hard.*nofile/d' "$LIMITS_CONFIG"
    sed -i '/^root.*soft.*nofile/d' "$LIMITS_CONFIG"
    sed -i '/^root.*hard.*nofile/d' "$LIMITS_CONFIG"
    
    cat >> "$LIMITS_CONFIG" << 'EOF'

# Added by network-optimize script
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    success "系统资源限制配置完成。"

    # 3. 配置 sysctl 网络参数
    info "正在配置 sysctl 网络参数 (/etc/sysctl.conf)..."
    
    # 清理旧的配置块
    sed -i "/^${SCRIPT_MARKER_START}/,/^${SCRIPT_MARKER_END}/d" "$SYSCTL_CONFIG"
    
    # 获取 MPTCP 配置
    local mptcp_settings
    mptcp_settings=$(configure_mptcp)
    
    # 写入新的配置块
    cat >> "$SYSCTL_CONFIG" << EOF
${SCRIPT_MARKER_START}
# Applied by network-optimize.sh on $(date)

# --- File System
fs.file-max = 1048576

# --- Core Network Tuning
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.default_qdisc = fq_codel

# --- TCP Tuning
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# --- Forwarding (optional, for routers/gateways)
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
${mptcp_settings}
${SCRIPT_MARKER_END}
EOF
    
    success "sysctl.conf 配置完成。"
    
    # 4. 应用 sysctl 配置
    info "正在应用 sysctl 配置..."
    if sysctl_output=$(sysctl -p 2>&1); then
        success "所有 sysctl 参数已成功应用。"
    else
        warn "部分 sysctl 参数应用失败 (这在某些内核上是正常的):"
        echo "$sysctl_output" | grep "cannot" | sed 's/^/    /'
    fi

    # 5. 配置网卡队列
    local interface
    if interface=$(detect_main_interface); then
        info "正在为主网卡 '$interface' 配置 fq_codel 队列..."
        if tc qdisc replace dev "$interface" root fq_codel; then
            success "网卡 '$interface' 的队列已设置为 fq_codel。"
        else
            warn "为网卡 '$interface' 设置 fq_codel 失败。"
        fi
    else
        warn "未能检测到主用网卡，跳过队列配置。"
    fi
}

revert_changes() {
    info "正在恢复网络配置..."
    
    # 恢复 sysctl.conf
    local sysctl_orig="${SYSCTL_CONFIG}.original"
    if [[ -f "$sysctl_orig" ]]; then
        cp "$sysctl_orig" "$SYSCTL_CONFIG"
        info "已从 '$sysctl_orig' 恢复 sysctl.conf。"
        info "正在重新加载 sysctl 配置..."
        sysctl -p &>/dev/null
        success "sysctl 配置已恢复。"
    else
        warn "未找到 sysctl.conf 的原始备份，跳过。"
    fi

    # 恢复 limits.conf
    local limits_orig="${LIMITS_CONFIG}.original"
    if [[ -f "$limits_orig" ]]; then
        cp "$limits_orig" "$LIMITS_CONFIG"
        success "已从 '$limits_orig' 恢复 limits.conf。"
    else
        warn "未找到 limits.conf 的原始备份，跳过。"
    fi
    
    success "恢复操作完成。建议重启系统以确保所有更改都已还原。"
}

show_status() {
    info "--- 网络优化状态检查 ---"
    
    local cc qdisc tfo mptcp_enabled
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "N/A")
    mptcp_enabled=$(sysctl -n net.mptcp.enabled 2>/dev/null || echo "N/A")

    # BBR
    [[ "$cc" == "bbr" ]] && success "拥塞控制: $cc (已启用)" || warn "拥塞控制: $cc (BBR 未启用)"
    
    # FQ-CoDel
    [[ "$qdisc" == "fq_codel" ]] && success "默认队列调度: $qdisc (已启用)" || warn "默认队列调度: $qdisc (fq_codel 未启用)"
    
    # TFO
    [[ "$tfo" == "3" ]] && success "TCP Fast Open: $tfo (已启用)" || warn "TCP Fast Open: $tfo (未完全启用)"
    
    # MPTCP
    if [[ "$mptcp_enabled" != "N/A" ]]; then
        [[ "$mptcp_enabled" == "1" ]] && success "MPTCP: $mptcp_enabled (已启用)" || warn "MPTCP: $mptcp_enabled (未启用)"
    else
        info "MPTCP: 系统不支持"
    fi

    # 网卡队列
    local interface
    if interface=$(detect_main_interface); then
        if tc qdisc show dev "$interface" 2>/dev/null | grep -q "fq_codel"; then
            success "网卡 '$interface' 队列: fq_codel"
        else
            warn "网卡 '$interface' 队列: 非 fq_codel"
        fi
    else
        warn "网卡检测失败"
    fi
    
    info "--- 状态检查完成 ---"
}

# =================================================
# 主函数 (Main)
# =================================================

usage() {
    echo "用法: $0 [apply|status|revert]"
    echo "  (无参数)      - 进入交互模式"
    echo "  apply        - 直接应用优化"
    echo "  status       - 检查当前网络优化状态"
    echo "  revert       - 恢复到优化前的配置"
}

main() {
    check_root
    
    local action="${1:-interactive}"

    case "$action" in
        apply)
            check_dependencies
            check_bbr_support
            apply_optimizations
            success "网络优化已应用！"
            show_status
            ;;
        status)
            show_status
            ;;
        revert)
            revert_changes
            ;;
        interactive)
            usage
            echo
            read -p "请选择要执行的操作 [apply/status/revert]: " choice
            main "$choice"
            ;;
        *)
            usage
            error "无效的参数: $action"
            ;;
    esac
}

main "$@"
