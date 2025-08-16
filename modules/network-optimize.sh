#!/bin/bash
#
# =================================================================
# System Optimization & Security Hardening Script v7.1
#
# Features:
# - SSH: Configures port, password auth, root login, and other security policies.
# - System: Smart ZRAM, Timezone, and Chrony time synchronization.
# - Provides 'apply', 'status', and 'revert' modes for all modules.
#
# NOTE: This version has removed the network optimization module for better
#       compatibility and focus.
#
# Usage:
#   - Interactive: ./system-harden.sh
#   - Apply all:   ./system-harden.sh apply
#   - Show status: ./system-harden.sh status
#   - Revert all:  ./system-harden.sh revert
# =================================================================

set -eo pipefail

# --- 全局常量 ---
readonly SSH_CONFIG="/etc/ssh/sshd_config"

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
    for cmd in ip sshd systemctl swapon modprobe timedatectl; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "命令 '$cmd' 未找到。请确保已安装所需工具包 (如 iproute2, openssh-server, util-linux)。"
            missing=1
        fi
    done
    [[ "$missing" -eq 0 ]] || error "缺少必要的依赖项。"
}

wait_for_apt_lock() {
    local wait_count=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [[ $wait_count -eq 0 ]]; then
            warn "检测到包管理器被锁定，等待释放..."
        fi
        sleep 5
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt 12 ]]; then
            error "包管理器锁定超时，请检查是否有其他 apt 进程在运行。"
        fi
    done
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
# SSH 安全加固模块
# =================================================

check_ssh_keys() { [[ -f "$HOME/.ssh/authorized_keys" && -s "$HOME/.ssh/authorized_keys" ]]; }

update_ssh_config() {
    local key="$1" value="$2"
    info "设置 SSH: $key -> $value"
    if grep -qE "^\s*#?\s*${key}\s+" "$SSH_CONFIG"; then
        sed -i -E "s/^\s*#?\s*${key}\s+.*/${key} ${value}/" "$SSH_CONFIG"
    else
        echo "${key} ${value}" >> "$SSH_CONFIG"
    fi
}

apply_ssh_hardening() {
    info "--- 开始应用 SSH 安全加固 ---"
    backup_file "$SSH_CONFIG"
    
    read -p "请输入新的 SSH 端口 [1024-65535] (留空则保持不变): " new_port
    [[ -n "$new_port" ]] && update_ssh_config "Port" "$new_port"

    if check_ssh_keys; then
        read -p "检测到 SSH 密钥。是否禁用密码登录? [Y/n]: " -r choice
        [[ ! "$choice" =~ ^[Nn]$ ]] && update_ssh_config "PasswordAuthentication" "no"
    else
        warn "未检测到 SSH 密钥，建议在禁用密码登录前进行配置。"
    fi

    echo "请选择 Root 登录策略: 1) 禁止(最安全) 2) 仅密钥 3) 保持不变"
    read -p "选择 [1-3]: " -r choice
    case "$choice" in
        1) update_ssh_config "PermitRootLogin" "no" ;;
        2) update_ssh_config "PermitRootLogin" "prohibit-password" ;;
    esac

    update_ssh_config "PubkeyAuthentication" "yes"; update_ssh_config "PermitEmptyPasswords" "no"
    update_ssh_config "MaxAuthTries" "3"; update_ssh_config "UseDNS" "no"

    info "正在验证并重新加载 SSH 服务..."
    if sshd -t; then systemctl reload sshd; success "SSH 安全配置已应用。";
    else error "SSH 配置文件语法错误！请手动检查 $SSH_CONFIG"; fi
}

revert_ssh_changes() {
    info "--- 正在恢复 SSH 配置 ---"
    local ssh_orig="${SSH_CONFIG}.original"
    if [[ -f "$ssh_orig" ]]; then cp "$ssh_orig" "$SSH_CONFIG"; systemctl reload sshd; success "sshd_config 已恢复。"; fi
}

show_ssh_status() {
    info "--- SSH 安全状态检查 ---"
    local port pass root
    port=$(grep -E "^\s*Port\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22")
    pass=$(grep -E "^\s*PasswordAuthentication\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes")
    root=$(grep -E "^\s*PermitRootLogin\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "prohibit-password")

    success "SSH 端口: $port"
    [[ "$pass" == "no" ]] && success "密码登录: 已禁用" || warn "密码登录: 已启用"
    [[ "$root" == "no" ]] && success "Root 登录: 已禁用" || warn "Root 登录: $root"
}

# =================================================
# 系统优化模块 (ZRAM, Time)
# =================================================

cleanup_zram_completely() {
    info "正在清理所有 ZRAM 设备..."
    systemctl stop zramswap.service 2>/dev/null || true
    systemctl disable zramswap.service 2>/dev/null || true
    for dev in $(ls /dev/zram* 2>/dev/null); do
        swapoff "$dev" 2>/dev/null || true
        echo 1 > "/sys/block/$(basename "$dev")/reset" 2>/dev/null || true
    done
    modprobe -r zram 2>/dev/null || true
}

setup_zram() {
    info "--- 开始配置智能 ZRAM ---"
    wait_for_apt_lock
    if ! command -v zramctl &>/dev/null; then
        info "正在安装 zram-tools..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools >/dev/null 2>&1 || error "zram-tools 安装失败。"
    fi
    
    cleanup_zram_completely
    
    local mem_mb; mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local cores; cores=$(nproc)
    # ZRAM size = 50% of RAM, but no more than 4GB
    local zram_size; zram_size=$((mem_mb / 2))
    [[ $zram_size -gt 4096 ]] && zram_size=4096

    info "内存: ${mem_mb}MB, CPU核心: ${cores}。将配置 ${zram_size}MB ZRAM。"
    
    echo "zram" > /sys/class/zram-control/hot_add
    local dev_num; dev_num=$(cat /sys/class/zram-control/num_devices)
    local zram_dev; zram_dev="/dev/zram$((dev_num - 1))"

    echo "zstd" > "/sys/block/$(basename "$zram_dev")/comp_algorithm"
    echo "${zram_size}M" > "/sys/block/$(basename "$zram_dev")/disksize"
    mkswap "$zram_dev" >/dev/null
    swapon "$zram_dev" -p 100

    # Make it persistent
    echo "KERNEL==\"zram0\", ATTR{disksize}=\"${zram_size}M\", ATTR{comp_algorithm}=\"zstd\", RUN+=\"/usr/sbin/mkswap /dev/zram0\", RUN+=\"/usr/sbin/swapon /dev/zram0 -p 100\"" > /etc/udev/rules.d/99-zram.rules
    
    # Set swappiness
    echo "vm.swappiness = 80" > /etc/sysctl.d/99-zram.conf
    sysctl -p /etc/sysctl.d/99-zram.conf >/dev/null
    
    success "ZRAM 配置完成。"
}

setup_timezone_and_time() {
    info "--- 开始配置时区和时间同步 ---"
    read -p "请输入目标时区 (例如 Asia/Shanghai, UTC, 留空则使用 Asia/Shanghai): " target_tz
    target_tz=${target_tz:-"Asia/Shanghai"}
    
    if timedatectl set-timezone "$target_tz"; then
        success "时区已设置为 $target_tz。"
    else
        warn "设置时区失败，请检查时区名称是否正确。"
    fi

    wait_for_apt_lock
    info "正在安装并配置 chrony 时间同步服务..."
    systemctl stop systemd-timesyncd 2>/dev/null || true
    systemctl disable systemd-timesyncd 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y chrony >/dev/null 2>&1 || error "chrony 安装失败。"
    systemctl enable --now chrony >/dev/null 2>&1
    success "Chrony 已启动并设为开机自启。"
}

apply_system_optimizations() {
    setup_zram
    setup_timezone_and_time
}

revert_system_changes() {
    info "--- 正在恢复系统优化配置 ---"
    cleanup_zram_completely
    rm -f /etc/udev/rules.d/99-zram.rules /etc/sysctl.d/99-zram.conf
    success "ZRAM 配置已移除。"
    warn "请注意: 时区设置和已安装的软件包 (chrony, zram-tools) 不会自动恢复。"
}

show_system_status() {
    info "--- 系统优化状态检查 ---"
    local zram_info; zram_info=$(swapon --show | grep zram || echo "N/A")
    if [[ "$zram_info" != "N/A" ]]; then
        success "ZRAM: 已启用 ($(echo "$zram_info" | awk '{print $3}'))"
    else
        warn "ZRAM: 未启用"
    fi
    success "时区: $(timedatectl status | grep 'Time zone' | awk '{print $3}')"
    if systemctl is-active --quiet chrony; then
        success "时间同步: chrony (运行中)"
    else
        warn "时间同步: chrony (未运行)"
    fi
}

# =================================================
# 主函数 (Main)
# =================================================

usage() {
    echo "用法: $0 [command]"
    echo "Commands:"
    echo "  (无参数)      - 进入交互模式"
    echo "  apply        - 应用所有优化和加固 (SSH + 系统)"
    echo "  status       - 检查所有模块的状态"
    echo "  revert       - 恢复所有模块的配置"
    echo "  apply-ssh    - 仅应用 SSH 加固"
    echo "  apply-sys    - 仅应用系统优化"
}

main() {
    check_root
    local action="${1:-interactive}"

    case "$action" in
        apply) check_dependencies; apply_ssh_hardening; apply_system_optimizations; main status ;;
        status) echo; show_ssh_status; echo; show_system_status; echo ;;
        revert) revert_ssh_changes; revert_system_changes ;;
        apply-ssh) check_dependencies; apply_ssh_hardening; show_ssh_status ;;
        apply-sys) check_dependencies; apply_system_optimizations; show_system_status ;;
        interactive)
            echo "请选择要执行的操作:"
            echo "  1) 应用所有优化 (SSH + 系统)"
            echo "  2) 仅应用 SSH 安全加固"
            echo "  3) 仅应用系统优化 (ZRAM + Time)"
            echo "  4) 查看当前状态"
            echo "  5) 恢复所有配置"
            read -p "选择 [1-5]: " -r choice
            case "$choice" in
                1) main "apply" ;; 2) main "apply-ssh" ;; 3) main "apply-sys" ;;
                4) main "status" ;; 5) main "revert" ;;
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
