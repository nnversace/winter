#!/bin/bash
#
# ==============================================================================
# System Performance Optimization Script
#
# This script optimizes system performance on modern Linux systems (Debian 13+)
# by configuring:
#   - Intelligent ZRAM swap based on system resources
#   - System timezone
#   - Chrony for accurate time synchronization
#
# Key Improvements:
#   - [Modernization] Uses /etc/sysctl.d/ for kernel parameters, which is the
#     recommended practice.
#   - [Robustness] Added root privileges and dependency checks at startup.
#     Handles package manager locks gracefully.
#   - [Simplicity] Removed complex, non-persistent multi-device ZRAM setup,
#     focusing on a robust single-device configuration managed by `zram-tools`.
#   - [Automation] Added a '-y' / '--yes' flag for non-interactive execution.
#   - [Clarity] Enhanced comments and logging for better user understanding.
# ==============================================================================

set -euo pipefail

# === Configuration & Constants ===
readonly SYSCTL_CONFIG_FILE="/etc/sysctl.d/99-zram-optimize.conf"
readonly ZRAM_CONFIG_FILE="/etc/default/zramswap"
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
UNATTENDED=false
DEBUG=false

# === Logging Function ===
log() {
    local msg="$1" level="${2:-info}"
    # Color map: info=cyan, warn=yellow, error=red, success=green, debug=magenta
    local -A colors=(
        [info]="\033[0;36m"
        [warn]="\033[0;33m"
        [error]="\033[0;31m"
        [success]="\033[0;32m"
        [debug]="\033[0;35m"
    )
    echo -e "${colors[$level]:-\033[0;32m}$msg\033[0m"
}

debug_log() {
    $DEBUG && log "DEBUG: $1" "debug" >&2
}

# === Pre-flight Checks ===
run_pre_flight_checks() {
    # Check for root privileges
    if [[ "$(id -u)" -ne 0 ]]; then
        log "错误: 此脚本必须以 root 权限运行。" "error"
        exit 1
    fi

    # Parse command-line arguments
    for arg in "$@"; do
        case $arg in
            -y|--yes)
                UNATTENDED=true
                log "已启用无人值守模式。" "warn"
                shift
                ;;
            --debug)
                DEBUG=true
                log "已启用调试模式。" "warn"
                shift
                ;;
        esac
    done

    # Check for required commands
    local missing_cmds=()
    for cmd in awk swapon systemctl timedatectl; do
        command -v "$cmd" &>/dev/null || missing_cmds+=("$cmd")
    done
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log "错误: 缺少核心命令: ${missing_cmds[*]}。" "error"
        log "请确保您在一个标准的 Debian/Ubuntu 环境中运行。" "error"
        exit 1
    fi
}

# === Helper Functions ===
# Gracefully wait for apt lock to be released
wait_for_apt_lock() {
    log "检查包管理器状态..." "info"
    local wait_count=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [[ $wait_count -eq 0 ]]; then
            log "检测到包管理器被锁定，等待释放 (最多等待60秒)..." "warn"
        fi
        ((wait_count++))
        if [[ $wait_count -ge 6 ]]; then
            log "包管理器锁定超时，请检查是否有其他 apt/dpkg 进程在运行。" "error"
            exit 1
        fi
        sleep 10
    done
}

# Install packages if they are not present
install_packages() {
    local packages_to_install=()
    for pkg in "$@"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log "正在安装必需的依赖: ${packages_to_install[*]}..." "info"
        wait_for_apt_lock
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages_to_install[@]}" >/dev/null 2>&1 || {
            log "错误: 依赖包安装失败: ${packages_to_install[*]}" "error"
            return 1
        }
    fi
    return 0
}

# Format size in MB to a human-readable format (GB or MB)
format_size() {
    local mb="$1"
    if (( mb >= 1024 )); then
        # Use awk for floating point division
        awk -v m="$mb" 'BEGIN {printf "%.1fG", m/1024}'
    else
        echo "${mb}M"
    fi
}

# === ZRAM Configuration ===
# Decision matrix for optimal ZRAM settings
get_optimal_zram_config() {
    local mem_mb="$1"
    
    # algorithm,size_multiplier
    if (( mem_mb < 1024 )); then
        echo "zstd,2.0"      # <1GB: Aggressive swapping
    elif (( mem_mb < 2048 )); then
        echo "zstd,1.5"      # 1-2GB: High swapping
    elif (( mem_mb < 4096 )); then
        echo "zstd,1.0"      # 2-4GB: Balanced
    else
        echo "zstd,0.75"     # 4GB+: Moderate
    fi
}

# Configure sysctl parameters for ZRAM optimization
configure_zram_sysctl() {
    local mem_mb="$1"
    local swappiness

    if (( mem_mb <= 2048 )); then
        swappiness=80 # High swappiness for low memory systems
    else
        swappiness=70 # Moderate swappiness for high memory systems
    fi
    
    log "配置内核参数 (swappiness=$swappiness)..." "info"
    
    cat > "$SYSCTL_CONFIG_FILE" << EOF
# This file was generated by the system optimization script.
# It optimizes kernel parameters for ZRAM usage.

# Set how aggressively the kernel will swap memory pages.
# Higher values mean more aggressive swapping.
vm.swappiness = $swappiness

# Recommended for ZRAM to improve efficiency.
vm.page-cluster = 0
EOF
    # Apply settings immediately
    sysctl -p "$SYSCTL_CONFIG_FILE" >/dev/null 2>&1 || log "应用 sysctl 设置时出现非致命错误。" "warn"
}

# Main function to set up ZRAM
setup_zram() {
    log "--- 配置智能 ZRAM Swap ---" "info"
    
    if ! install_packages zram-tools bc; then
        log "ZRAM 配置因依赖安装失败而中止。" "error"
        return 1
    fi

    local mem_mb cores
    mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    cores=$(nproc)
    
    log "检测到系统资源: $(format_size "$mem_mb")B 内存, ${cores} 核 CPU" "info"

    # Get optimal settings
    local config settings_algo settings_multiplier
    config=$(get_optimal_zram_config "$mem_mb")
    settings_algo=$(echo "$config" | cut -d, -f1)
    settings_multiplier=$(echo "$config" | cut -d, -f2)

    # Calculate target size
    local target_size_mb
    target_size_mb=$(echo "$mem_mb * $settings_multiplier" | bc | awk '{print int($1)}')

    log "决策: 使用 $settings_algo 算法, ZRAM 大小为物理内存的 ${settings_multiplier}x (~$(format_size "$target_size_mb")B)" "info"

    # Configure sysctl parameters
    configure_zram_sysctl "$mem_mb"

    # Configure zram-tools
    log "正在写入 ZRAM 配置文件..." "info"
    cat > "$ZRAM_CONFIG_FILE" << EOF
# This file was generated by the system optimization script.
# It controls the zramswap service.

# Compression algorithm to use
ALGO=$settings_algo

# Amount of RAM to use for ZRAM (in MB)
SIZE=$target_size_mb

# Swap priority
PRIORITY=100
EOF

    # Restart the service to apply changes
    log "正在重启 zramswap 服务以应用配置..." "info"
    systemctl restart zramswap.service
    sleep 2 # Allow time for the device to be configured

    # Verification
    if swapon --show | grep -q '/dev/zram0'; then
        log "✓ ZRAM 配置成功并已激活。" "success"
    else
        log "✗ ZRAM 配置失败。请检查 'systemctl status zramswap.service' 获取详情。" "error"
        return 1
    fi
}

# === Time and Zone Configuration ===
setup_timezone() {
    log "--- 配置系统时区 ---" "info"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "未知")
    log "当前时区: $current_tz" "info"
    
    local target_tz="$DEFAULT_TIMEZONE"
    
    if ! $UNATTENDED; then
        read -p "选择时区 [1=上海(默认) 2=UTC 3=东京 4=保持不变]: " choice
        case "$choice" in
            2) target_tz="UTC" ;;
            3) target_tz="Asia/Tokyo" ;;
            4) 
                log "时区保持不变。" "info"
                return 0 
                ;;
            *) target_tz="$DEFAULT_TIMEZONE" ;;
        esac
    fi

    if [[ "$current_tz" != "$target_tz" ]]; then
        log "正在设置时区为: $target_tz..." "info"
        timedatectl set-timezone "$target_tz" || {
            log "设置时区失败。" "error"
            return 1
        }
        log "✓ 时区已更新。" "success"
    else
        log "时区无需更改。" "info"
    fi
}

setup_chrony() {
    log "--- 配置时间同步 (Chrony) ---" "info"

    if ! install_packages chrony; then
        log "时间同步配置因 chrony 安装失败而中止。" "error"
        return 1
    fi
    
    # Stop and disable conflicting services
    if systemctl is-active --quiet systemd-timesyncd; then
        log "正在停用 systemd-timesyncd 以避免冲突..." "info"
        systemctl stop systemd-timesyncd
        systemctl disable systemd-timesyncd >/dev/null 2>&1
    fi

    log "正在启用并启动 chrony 服务..." "info"
    systemctl enable --now chrony >/dev/null 2>&1
    
    # Force a time sync
    chronyc -a makestep >/dev/null 2>&1 &
    
    sleep 2
    if systemctl is-active --quiet chrony; then
        log "✓ Chrony 服务已激活。" "success"
    else
        log "✗ Chrony 服务启动失败。" "error"
        return 1
    fi
}

# === Summary ===
show_system_summary() {
    echo
    log "====================== 🎯 系统优化摘要 ======================" "info"
    
    # ZRAM Status
    local zram_info
    zram_info=$(swapon --show | grep zram0 || true)
    if [[ -n "$zram_info" ]]; then
        local zram_size zram_used
        zram_size=$(echo "$zram_info" | awk '{print $3}')
        zram_used=$(echo "$zram_info" | awk '{print $4}')
        log "  [✓] ZRAM Swap  : 已激活 (大小: ${zram_size}B, 已用: ${zram_used}B)" "success"
    else
        log "  [✗] ZRAM Swap  : 未激活" "warn"
    fi
    
    # Swappiness
    local swappiness
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "未知")
    log "  [✓] Swappiness : $swappiness" "success"

    # Timezone
    local timezone
    timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "未知")
    log "  [✓] 时区       : $timezone" "success"

    # Time Sync
    if systemctl is-active --quiet chrony; then
        log "  [✓] 时间同步   : Chrony (已激活)" "success"
    else
        log "  [✗] 时间同步   : 未激活" "warn"
    fi
    log "================================================================" "info"
}


# === Main Execution Logic ===
main() {
    run_pre_flight_checks "$@"

    log "🚀 启动系统性能优化脚本" "info"
    echo
    log "此脚本将优化 ZRAM Swap、时区和时间同步。" "info"
    log "所有配置都将以符合现代系统管理规范的方式进行。" "info"
    echo

    if ! $UNATTENDED; then
        read -p "是否继续进行系统优化? [Y/n]: " -r choice
        if [[ "$choice" =~ ^[Nn]$ ]]; then
            log "操作已取消。" "info"
            exit 0
        fi
    fi

    # --- Step 1: ZRAM ---
    setup_zram

    # --- Step 2: Timezone ---
    echo
    setup_timezone

    # --- Step 3: Time Sync ---
    echo
    setup_chrony

    # --- Step 4: Summary ---
    show_system_summary
    
    echo
    log "🎉 系统优化配置完成!" "success"
}

# Run the main function with all script arguments
main "$@"
