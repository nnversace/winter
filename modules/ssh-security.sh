#!/bin/bash
#
# =================================================================
# System Optimization & Security Hardening Script v6.0
#
# Features:
# - Network: Enables BBR + FQ-CoDel, TFO, MPTCP, and system limits.
# - SSH: Configures port, password auth, root login, and other security policies.
# - Provides 'apply', 'status', and 'revert' modes for both modules.
#
# Usage:
#   - Interactive: ./system-harden.sh
#   - Apply all:   ./system-harden.sh apply
#   - Show status: ./system-harden.sh status
#   - Revert all:  ./system-harden.sh revert
# =================================================================

set -eo pipefail

# --- 全局常量 ---
readonly SYSCTL_CONFIG="/etc/sysctl.conf"
readonly LIMITS_CONFIG="/etc/security/limits.conf"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly NET_MARKER_START="# === Network Optimize Start ==="
readonly NET_MARKER_END="# === Network Optimize End ==="

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
# 通用辅助函数
# =================================================

check_root() {
    [[ "$(id -u)" -eq 0 ]] || error "此脚本必须以 root 权限运行。"
}

check_dependencies() {
    info "正在检查依赖项..."
    local missing=0
    for cmd in ip tc sysctl sshd systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "命令 '$cmd' 未找到。请确保已安装所需工具包 (如 iproute2, openssh-server)。"
            missing=1
        fi
    done
    [[ "$missing" -eq 0 ]] || error "缺少必要的依赖项。"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_orig="${file}.original"
        if [[ ! -f "$backup_orig" ]]; then
            cp "$file" "$backup_orig"
            info "已为 '$file' 创建原始备份: ${backup_orig}"
        fi
    fi
}

# =================================================
# 网络优化模块
# =================================================

detect_main_interface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}'
}

check_bbr_support() {
    info "正在检查 BBR 支持..."
    if lsmod | grep -q "tcp_bbr" || modprobe tcp_bbr 2>/dev/null; then
        success "BBR 模块可用。"
        return 0
    fi
    if [[ -f "/proc/config.gz" ]] && zcat /proc/config.gz | grep -q "CONFIG_TCP_BBR=[ym]"; then
        success "内核已内建 BBR 支持。"
        return 0
    fi
    error "系统不支持 BBR。请升级到更新的内核版本 (>= 4.9)。"
}

configure_mptcp() {
    local mptcp_config_text=""
    if [[ ! -f "/proc/sys/net/mptcp/enabled" ]]; then
        warn "系统不支持 MPTCP，将跳过相关配置。"
        echo -e "\n# MPTCP not supported on this system."
        return
    fi
    
    info "正在检测并配置 MPTCP 参数..."
    declare -A mptcp_params=(
        ["net.mptcp.enabled"]=1 ["net.mptcp.pm_type"]=0
        ["net.mptcp.checksum_enabled"]=0 ["net.mptcp.scheduler"]="default"
    )
    mptcp_config_text+="\n# MPTCP Optimization"
    for param in "${!mptcp_params[@]}"; do
        [[ -f "/proc/sys/${param//./\/}" ]] && mptcp_config_text+="\n${param} = ${mptcp_params[$param]}"
    done
    echo "$mptcp_config_text"
}

apply_network_optimizations() {
    info "--- 开始应用网络性能优化 ---"
    check_bbr_support
    backup_file "$SYSCTL_CONFIG"
    backup_file "$LIMITS_CONFIG"

    # 配置 limits.conf
    info "正在配置系统资源限制 (/etc/security/limits.conf)..."
    sed -i '/# Added by system-harden script/,+4d' "$LIMITS_CONFIG"
    cat >> "$LIMITS_CONFIG" << 'EOF'
# Added by system-harden script
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    
    # 配置 sysctl.conf
    info "正在配置 sysctl 网络参数 (/etc/sysctl.conf)..."
    sed -i "/^${NET_MARKER_START}/,/^${NET_MARKER_END}/d" "$SYSCTL_CONFIG"
    local mptcp_settings; mptcp_settings=$(configure_mptcp)
    
    cat >> "$SYSCTL_CONFIG" << EOF
${NET_MARKER_START}
# Applied by system-harden.sh on $(date)
fs.file-max = 1048576
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.ip_forward = 1
${mptcp_settings}
${NET_MARKER_END}
EOF
    
    info "正在应用 sysctl 配置..."
    sysctl -p >/dev/null 2>&1
    
    local interface;
    if interface=$(detect_main_interface); then
        info "正在为主网卡 '$interface' 配置 fq_codel 队列..."
        tc qdisc replace dev "$interface" root fq_codel &>/dev/null
    fi
    success "网络优化配置完成。"
}

revert_network_changes() {
    info "--- 正在恢复网络配置 ---"
    local sysctl_orig="${SYSCTL_CONFIG}.original"
    if [[ -f "$sysctl_orig" ]]; then
        cp "$sysctl_orig" "$SYSCTL_CONFIG"
        sysctl -p &>/dev/null
        success "sysctl.conf 已恢复。"
    fi
    local limits_orig="${LIMITS_CONFIG}.original"
    if [[ -f "$limits_orig" ]]; then
        cp "$limits_orig" "$LIMITS_CONFIG"
        success "limits.conf 已恢复。"
    fi
}

show_network_status() {
    info "--- 网络优化状态检查 ---"
    local cc qdisc tfo
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "N/A")
    
    [[ "$cc" == "bbr" ]] && success "拥塞控制: $cc" || warn "拥塞控制: $cc (BBR 未启用)"
    [[ "$qdisc" == "fq_codel" ]] && success "默认队列调度: $qdisc" || warn "默认队列调度: $qdisc (fq_codel 未启用)"
    [[ "$tfo" == "3" ]] && success "TCP Fast Open: $tfo" || warn "TCP Fast Open: $tfo (未完全启用)"
}

# =================================================
# SSH 安全加固模块
# =================================================

check_ssh_keys() {
    [[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]]
}

update_ssh_config() {
    local key="$1" value="$2"
    info "设置 SSH: $key -> $value"
    # 如果键已存在（无论是否被注释），则替换它
    if grep -qE "^\s*#?\s*${key}\s+" "$SSH_CONFIG"; then
        sed -i -E "s/^\s*#?\s*${key}\s+.*/${key} ${value}/" "$SSH_CONFIG"
    else
        # 否则，在文件末尾添加它
        echo "${key} ${value}" >> "$SSH_CONFIG"
    fi
}

apply_ssh_hardening() {
    info "--- 开始应用 SSH 安全加固 ---"
    backup_file "$SSH_CONFIG"
    
    # --- 交互式配置 ---
    read -p "请输入新的 SSH 端口 [1024-65535] (留空则保持不变): " new_port
    if [[ -n "$new_port" ]]; then
        update_ssh_config "Port" "$new_port"
    fi

    if check_ssh_keys; then
        read -p "检测到 SSH 密钥。是否禁用密码登录? [Y/n]: " -r choice
        if [[ ! "$choice" =~ ^[Nn]$ ]]; then
            update_ssh_config "PasswordAuthentication" "no"
        fi
    else
        warn "未检测到 SSH 密钥，建议在禁用密码登录前进行配置。"
    fi

    echo "请选择 Root 登录策略:"
    echo "  1) 禁止 Root 登录 (最安全)"
    echo "  2) 仅允许密钥登录"
    echo "  3) 保持不变"
    read -p "选择 [1-3]: " -r choice
    case "$choice" in
        1) update_ssh_config "PermitRootLogin" "no" ;;
        2) update_ssh_config "PermitRootLogin" "prohibit-password" ;;
        *) info "保持当前 Root 登录策略。" ;;
    esac

    # --- 应用其他安全设置 ---
    update_ssh_config "PubkeyAuthentication" "yes"
    update_ssh_config "PermitEmptyPasswords" "no"
    update_ssh_config "MaxAuthTries" "3"
    update_ssh_config "X11Forwarding" "no"
    update_ssh_config "UseDNS" "no"

    info "正在验证并重新加载 SSH 服务..."
    if sshd -t; then
        systemctl reload sshd
        success "SSH 安全配置已应用。"
    else
        error "SSH 配置文件语法错误！请手动检查 $SSH_CONFIG"
    fi
}

revert_ssh_changes() {
    info "--- 正在恢复 SSH 配置 ---"
    local ssh_orig="${SSH_CONFIG}.original"
    if [[ -f "$ssh_orig" ]]; then
        cp "$ssh_orig" "$SSH_CONFIG"
        systemctl reload sshd
        success "sshd_config 已恢复。"
    fi
}

show_ssh_status() {
    info "--- SSH 安全状态检查 ---"
    local port pass root
    port=$(grep -E "^\s*Port\s+" "$SSH_CONFIG" | awk '{print $2}' || echo "22")
    pass=$(grep -E "^\s*PasswordAuthentication\s+" "$SSH_CONFIG" | awk '{print $2}' || echo "yes")
    root=$(grep -E "^\s*PermitRootLogin\s+" "$SSH_CONFIG" | awk '{print $2}' || echo "prohibit-password")

    success "SSH 端口: $port"
    [[ "$pass" == "no" ]] && success "密码登录: 已禁用" || warn "密码登录: 已启用"
    [[ "$root" == "no" ]] && success "Root 登录: 已禁用" || warn "Root 登录: $root"
}

# =================================================
# 主函数 (Main)
# =================================================

usage() {
    echo "用法: $0 [command]"
    echo "Commands:"
    echo "  (无参数)      - 进入交互模式"
    echo "  apply        - 应用所有优化和加固"
    echo "  status       - 检查所有模块的状态"
    echo "  revert       - 恢复所有模块的配置"
    echo "  apply-net    - 仅应用网络优化"
    echo "  apply-ssh    - 仅应用 SSH 加固"
}

main() {
    check_root
    local action="${1:-interactive}"

    case "$action" in
        apply) check_dependencies; apply_network_optimizations; apply_ssh_hardening; show_status ;;
        status) show_network_status; show_ssh_status ;;
        revert) revert_network_changes; revert_ssh_changes ;;
        apply-net) check_dependencies; apply_network_optimizations; show_network_status ;;
        apply-ssh) check_dependencies; apply_ssh_hardening; show_ssh_status ;;
        interactive)
            echo "请选择要执行的操作:"
            echo "  1) 应用所有优化 (网络 + SSH)"
            echo "  2) 仅应用网络优化"
            echo "  3) 仅应用 SSH 安全加固"
            echo "  4) 查看当前状态"
            echo "  5) 恢复所有配置"
            read -p "选择 [1-5]: " -r choice
            case "$choice" in
                1) main "apply" ;;
                2) main "apply-net" ;;
                3) main "apply-ssh" ;;
                4) main "status" ;;
                5) main "revert" ;;
                *) echo "无效选择。" ;;
            esac
            ;;
        *)
            usage
            error "无效的参数: $action"
            ;;
    esac
}

main "$@"
