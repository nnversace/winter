#!/bin/bash
#
# =================================================================
# System Optimization & Security Hardening Script
#
# Changelog:
# - [FIX] Reworked network module to use /etc/sysctl.d/ and /etc/security/limits.d/
#   for full compatibility with modern systems (e.g., Debian 12/13) where
#   main config files may not exist by default.
# - [IMPROVE] Made network and limits configuration fully idempotent.
# - [MODERNIZE] ZRAM setup now uses the zram-tools package configuration
#   (/etc/default/zramswap) instead of manual udev rules for better stability.
# - [ROBUST] SSH config updates are now more robust against existing commented lines.
# - [ENHANCE] Improved logging and status reporting clarity.
# - [FIX] ZRAM service name is now dynamically detected to support multiple environments.
#
# Features:
# - Network: Enables BBR + FQ, TFO, and system limits.
# - SSH: Configures port, password auth, root login, and other security policies.
# - System: Smart ZRAM, Timezone, and Chrony time synchronization.
# - Provides 'apply', 'status', and 'revert' modes for all modules.
#
# Usage:
#   - Interactive: ./system-harden.sh
#   - Apply all:   ./system-harden.sh apply
#   - Show status: ./system-harden.sh status
#   - Revert all:  ./system-harden.sh revert
# =================================================================

set -eo pipefail

# --- 全局常量 ---
readonly SYSCTL_CUSTOM_CONFIG="/etc/sysctl.d/99-system-harden.conf"
readonly LIMITS_CUSTOM_CONFIG="/etc/security/limits.d/99-system-harden.conf"
readonly SSH_CONFIG="/etc/ssh/sshd_config"

# --- 日志和颜色 ---
C_RESET="\033[0m"; C_INFO="\033[0;36m"; C_WARN="\033[0;33m"
C_ERROR="\033[0;31m"; C_SUCCESS="\033[0;32m"
log() { local level="$1" color="$2" msg="$3"; echo -e "${color}[${level}] ${msg}${C_RESET}"; }
info() { log "INFO" "${C_INFO}" "$1"; }; warn() { log "WARN" "${C_WARN}" "$1"; }
error() { log "ERROR" "${C_ERROR}" "$1"; exit 1; }; success() { log "SUCCESS" "${C_SUCCESS}" "$1"; }

# =================================================
# 通用辅助函数
# =================================================

check_root() { [[ "$(id -u)" -eq 0 ]] || error "此脚本必须以 root 权限运行。"; }

check_dependencies() {
    info "正在检查依赖项..."
    for cmd in ip sysctl sshd systemctl timedatectl; do
        command -v "$cmd" &>/dev/null || error "命令 '$cmd' 未找到。请确保已安装核心系统工具。"
    done
    success "依赖项检查通过。"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_orig="${file}.original"
        if [[ ! -f "$backup_orig" ]]; then
            cp -a "$file" "$backup_orig"
            info "已为 '$file' 创建原始备份: ${backup_orig}"
        fi
    fi
}

# =================================================
# 网络优化模块
# =================================================

apply_network_optimizations() {
    info "--- 开始应用网络性能优化 ---"
    
    info "正在配置系统资源限制 (${LIMITS_CUSTOM_CONFIG})..."
    mkdir -p "$(dirname "$LIMITS_CUSTOM_CONFIG")"
    cat > "$LIMITS_CUSTOM_CONFIG" << 'EOF'
# Added by system-harden script
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    
    info "正在配置 sysctl 网络参数 (${SYSCTL_CUSTOM_CONFIG})..."
    mkdir -p "$(dirname "$SYSCTL_CUSTOM_CONFIG")"
    cat > "$SYSCTL_CUSTOM_CONFIG" << EOF
# Applied by system-harden.sh on $(date)
fs.file-max = 1048576
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65000
EOF
    
    info "正在应用 sysctl 配置..."
    sysctl --system >/dev/null 2>&1
    
    success "网络优化配置完成。请重新登录以使资源限制完全生效。"
}

revert_network_changes() {
    info "--- 正在恢复网络配置 ---"
    if rm -f "$SYSCTL_CUSTOM_CONFIG"; then
        sysctl --system >/dev/null 2>&1
        success "自定义 sysctl 配置已移除。"
    else
        info "未找到自定义 sysctl 配置文件，无需操作。"
    fi
    if rm -f "$LIMITS_CUSTOM_CONFIG"; then
        success "自定义资源限制配置已移除。"
    else
        info "未找到自定义资源限制配置文件，无需操作。"
    fi
}

show_network_status() {
    info "--- 网络优化状态检查 ---"
    local cc qdisc tfo
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "N/A")
    
    [[ "$cc" == "bbr" ]] && success "拥塞控制: $cc" || warn "拥塞控制: $cc (BBR 未启用)"
    [[ "$qdisc" == "fq" ]] && success "默认队列调度: $qdisc" || warn "默认队列调度: $qdisc (fq 未启用)"
    [[ "$tfo" == "3" ]] && success "TCP Fast Open: $tfo" || warn "TCP Fast Open: $tfo (未完全启用)"
    [[ -f "$LIMITS_CUSTOM_CONFIG" ]] && success "资源限制: 已配置" || warn "资源限制: 未配置"
}

# =================================================
# SSH 安全加固模块
# =================================================

set_ssh_config() {
    local key="$1" value="$2"
    info "设置 SSH: $key -> $value"
    sed -i -E "/^[#\s]*${key}\s+/d" "$SSH_CONFIG"
    echo "${key} ${value}" >> "$SSH_CONFIG"
}

apply_ssh_hardening() {
    info "--- 开始应用 SSH 安全加固 ---"
    backup_file "$SSH_CONFIG"
    
    read -p "请输入新的 SSH 端口 [1024-65535] (留空则保持不变): " new_port
    [[ -n "$new_port" && "$new_port" -ge 1024 && "$new_port" -le 65535 ]] && set_ssh_config "Port" "$new_port"

    if [[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]]; then
        read -p "检测到 SSH 密钥。是否禁用密码登录? [Y/n]: " -r choice
        [[ ! "$choice" =~ ^[Nn]$ ]] && set_ssh_config "PasswordAuthentication" "no"
    else
        warn "未检测到 SSH 密钥，建议在禁用密码登录前进行配置。"
        set_ssh_config "PasswordAuthentication" "yes"
    fi

    echo "请选择 Root 登录策略: 1) 禁止(最安全) 2) 仅密钥 3) 保持不变"
    read -p "选择 [1-3, 默认 3]: " -r choice
    case "$choice" in
        1) set_ssh_config "PermitRootLogin" "no" ;;
        2) set_ssh_config "PermitRootLogin" "prohibit-password" ;;
    esac

    set_ssh_config "PubkeyAuthentication" "yes"; set_ssh_config "PermitEmptyPasswords" "no"
    set_ssh_config "MaxAuthTries" "3"; set_ssh_config "UseDNS" "no"

    info "正在验证并重新加载 SSH 服务..."
    if sshd -t; then systemctl reload sshd; success "SSH 安全配置已应用。";
    else error "SSH 配置文件语法错误！请手动检查 $SSH_CONFIG"; fi
}

revert_ssh_changes() {
    info "--- 正在恢复 SSH 配置 ---"
    local ssh_orig="${SSH_CONFIG}.original"
    if [[ -f "$ssh_orig" ]]; then 
        cp -a "$ssh_orig" "$SSH_CONFIG"
        if sshd -t; then systemctl reload sshd; success "sshd_config 已恢复。";
        else error "恢复后的 SSH 配置文件语法错误！"; fi
    else
        warn "未找到 SSH 原始备份文件。"
    fi
}

show_ssh_status() {
    get_ssh_config() { sshd -T | grep -i "^${1}" | awk '{print $2}'; }
    
    info "--- SSH 安全状态检查 (基于当前运行配置) ---"
    local port pass root
    port=$(get_ssh_config "port")
    pass=$(get_ssh_config "passwordauthentication")
    root=$(get_ssh_config "permitrootlogin")

    success "SSH 端口: $port"
    [[ "$pass" == "no" ]] && success "密码登录: 已禁用" || warn "密码登录: 已启用"
    [[ "$root" == "no" ]] && success "Root 登录: 已禁用" || warn "Root 登录: $root"
}

# =================================================
# 系统优化模块 (ZRAM, Time)
# =================================================

setup_zram() {
    info "--- 开始配置智能 ZRAM ---"
    if ! command -v zramctl &>/dev/null; then
        info "正在安装 zram-tools..."
        # 移除 >/dev/null 以便在安装失败时查看错误
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools || error "zram-tools 安装失败。"
        # 安装后重新加载 systemd 服务列表
        info "重新加载 systemd daemon..."
        systemctl daemon-reload
    fi
    
    local mem_total_kb; mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local zram_size_mb; zram_size_mb=$((mem_total_kb / 1024 / 2))
    [[ $zram_size_mb -gt 8192 ]] && zram_size_mb=8192

    info "物理内存: $((mem_total_kb / 1024))MB。将配置 ${zram_size_mb}MB ZRAM。"
    
    {
        echo "# Configured by system-harden.sh"
        echo "ALGO=zstd"
        echo "SIZE=${zram_size_mb}M"
        echo "PRIORITY=100"
    } > /etc/default/zramswap
    
    # 动态查找 ZRAM 服务名
    local service_name=""
    if systemctl list-unit-files | grep -q 'zram-config.service'; then
        service_name="zram-config"
    elif systemctl list-unit-files | grep -q 'zramswap.service'; then
        service_name="zramswap"
    else
        error "安装 zram-tools 后，未能找到对应的 systemd 服务 (zram-config.service 或 zramswap.service)。"
    fi
    
    info "正在使用 '${service_name}.service' 重启 ZRAM 服务以应用配置..."
    systemctl restart "${service_name}"
    
    echo "vm.swappiness = 80" > /etc/sysctl.d/99-zram.conf
    sysctl -p /etc/sysctl.d/99-zram.conf >/dev/null
    
    success "ZRAM 配置完成。"
}

setup_timezone_and_time() {
    info "--- 开始配置时区和时间同步 ---"
    timedatectl set-timezone "Asia/Shanghai"
    success "时区已设置为 Asia/Shanghai。"

    info "正在安装并配置 chrony 时间同步服务..."
    systemctl stop systemd-timesyncd 2>/dev/null || true
    systemctl disable systemd-timesyncd 2>/dev/null || true
    # 移除 >/dev/null 以便在安装失败时查看错误
    DEBIAN_FRONTEND=noninteractive apt-get install -y chrony || error "chrony 安装失败。"
    systemctl enable --now chrony
    success "Chrony 已启动并设为开机自启。"
}

apply_system_optimizations() { setup_zram; setup_timezone_and_time; }

revert_system_changes() {
    info "--- 正在恢复系统优化配置 ---"
    if command -v zramctl &>/dev/null; then
        info "正在卸载 zram-tools 并清理配置..."
        # 动态查找 ZRAM 服务名以停止
        local service_name=""
        if systemctl list-unit-files | grep -q 'zram-config.service'; then
            service_name="zram-config"
        elif systemctl list-unit-files | grep -q 'zramswap.service'; then
            service_name="zramswap"
        fi
        
        if [[ -n "$service_name" ]]; then
            systemctl stop "${service_name}" 2>/dev/null || true
        fi
        
        # 移除 >/dev/null 以便在卸载失败时查看错误
        DEBIAN_FRONTEND=noninteractive apt-get purge -y zram-tools
    fi
    rm -f /etc/sysctl.d/99-zram.conf
    success "ZRAM 配置已移除。"
    warn "请注意: 时区设置不会自动恢复。"
}

show_system_status() {
    info "--- 系统优化状态检查 ---"
    if swapon --show | grep -q zram; then
        success "ZRAM: 已启用 ($(swapon --show | grep zram | awk '{print $3}'))"
    else warn "ZRAM: 未启用"; fi
    
    success "时区: $(timedatectl status | grep 'Time zone' | awk '{print $3}')"
    
    if systemctl is-active --quiet chrony; then success "时间同步: chrony (运行中)"
    else warn "时间同步: chrony (未运行)"; fi
}

# =================================================
# 主函数 (Main)
# =================================================

usage() { echo "用法: $0 [apply|status|revert|apply-net|apply-ssh|apply-sys]"; }

main() {
    check_root
    local action="${1:-interactive}"

    case "$action" in
        apply) check_dependencies; apply_network_optimizations; apply_ssh_hardening; apply_system_optimizations; main status ;;
        status) echo; show_network_status; echo; show_ssh_status; echo; show_system_status; echo ;;
        revert) revert_network_changes; revert_ssh_changes; revert_system_changes ;;
        apply-net) check_dependencies; apply_network_optimizations; show_network_status ;;
        apply-ssh) check_dependencies; apply_ssh_hardening; show_ssh_status ;;
        apply-sys) check_dependencies; apply_system_optimizations; show_system_status ;;
        interactive)
            echo "请选择要执行的操作:"
            echo "  1) 应用所有优化 (网络 + SSH + 系统)"
            echo "  2) 查看当前状态"
            echo "  3) 恢复所有配置"
            read -p "选择 [1-3]: " -r choice
            case "$choice" in
                1) main "apply" ;; 2) main "status" ;; 3) main "revert" ;;
                *) echo "无效选择。" ;;
            esac
            ;;
        *) usage; error "无效的参数: $action" ;;
    esac
}

main "$@"
