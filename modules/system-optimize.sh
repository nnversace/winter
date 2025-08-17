#!/bin/bash
# 系统优化模块 - Debian 13适配版
# 功能: 时区设置、时间同步
# 优化: 减少错误、提高兼容性、增强稳定性

set -euo pipefail

# === 常量定义 ===
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly DEBIAN_VERSION=$(lsb_release -rs 2>/dev/null || cat /etc/debian_version 2>/dev/null || echo "unknown")
readonly KERNEL_VERSION=$(uname -r)

# === 日志函数 ===
log() {
    local msg="$1" level="${2:-info}"
    local -A colors=([info]="\033[0;36m" [warn]="\033[0;33m" [error]="\033[0;31m" [debug]="\033[0;35m" [success]="\033[0;32m")
    echo -e "${colors[$level]:-\033[0;32m}[$(date '+%H:%M:%S')] $msg\033[0m"
}

debug_log() {
    [[ "${DEBUG:-}" == "1" ]] && log "DEBUG: $1" "debug" >&2
}

# === 系统兼容性检查 ===
check_system_compatibility() {
    local arch=$(uname -m)
    debug_log "系统检查: Debian $DEBIAN_VERSION, 内核 $KERNEL_VERSION, 架构 $arch"

    case "$arch" in
        x86_64|amd64|aarch64|arm64) ;;
        armv7l|armv8l) log "ARM32架构可能存在兼容性问题" "warn" ;;
        *) log "不支持的架构: $arch" "error"; return 1 ;;
    esac

    if ! command -v systemctl &>/dev/null; then
        log "需要systemd支持" "error"
        return 1
    fi

    return 0
}

# === 包管理器增强函数 ===
wait_for_package_manager() {
    local max_wait=300
    local wait_time=0
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )

    while (( wait_time < max_wait )); do
        local locked=false
        for lock_file in "${lock_files[@]}"; do
            if fuser "$lock_file" &>/dev/null; then
                locked=true
                break
            fi
        done

        if ! $locked && ! pgrep -f "apt|dpkg" &>/dev/null; then
            return 0
        fi

        if (( wait_time == 0 )); then
            log "等待包管理器释放..." "warn"
        fi
        sleep 5
        wait_time=$((wait_time + 5))
    done

    log "包管理器锁定超时，尝试强制继续" "warn"
    return 1
}

safe_apt_install() {
    local packages=("$@")
    local retry_count=0
    local max_retries=3

    wait_for_package_manager || log "包管理器可能仍被锁定" "warn"

    while (( retry_count < max_retries )); do
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" >/dev/null 2>&1; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        log "安装失败，重试 $retry_count/$max_retries" "warn"
        sleep 2
    done

    log "安装包失败: ${packages[*]}" "error"
    return 1
}

# === 时区配置 ===
setup_timezone() {
    local current_tz
    if ! current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null); then
        current_tz=$(cat /etc/timezone 2>/dev/null || echo "未知")
    fi
    echo "当前时区: $current_tz"

    if [[ -t 0 ]] && [[ -t 1 ]]; then
        echo "时区选择:"
        echo "1. 上海 (Asia/Shanghai)"
        echo "2. UTC (协调世界时)"
        echo "3. 东京 (Asia/Tokyo)"
        echo "4. 伦敦 (Europe/London)"
        echo "5. 纽约 (America/New_York)"
        echo "6. 自定义输入"
        echo "7. 保持当前"
        read -p "请选择 [1-7] (默认1): " choice
    else
        choice="1"
        log "非交互模式，使用默认时区" "info"
    fi

    choice=${choice:-1}
    local target_tz
    case "$choice" in
        1) target_tz="Asia/Shanghai" ;;
        2) target_tz="UTC" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="Europe/London" ;;
        5) target_tz="America/New_York" ;;
        6) 
            if [[ -t 0 ]]; then
                read -p "输入时区 (如: Asia/Shanghai): " target_tz
                if ! timedatectl list-timezones 2>/dev/null | grep -q "^$target_tz$"; then
                    log "无效时区，使用默认" "warn"
                    target_tz="$DEFAULT_TIMEZONE"
                fi
            else
                target_tz="$DEFAULT_TIMEZONE"
            fi
            ;;
        7) 
            echo "时区: $current_tz (保持不变) ✓"
            return 0
            ;;
        *) target_tz="$DEFAULT_TIMEZONE" ;;
    esac

    if [[ "$current_tz" != "$target_tz" ]]; then
        if timedatectl set-timezone "$target_tz" 2>/dev/null; then
            echo "时区: $target_tz ✅"
        else
            log "时区设置失败" "error"
            return 1
        fi
    else
        echo "时区: $target_tz (已是当前设置) ✓"
    fi
    return 0
}

# === 时间同步配置 ===
setup_chrony() {
    local sync_services=("chrony" "systemd-timesyncd" "ntp" "ntpd")
    local active_service=""

    for service in "${sync_services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            active_service="$service"
            break
        fi
    done

    if [[ "$active_service" == "chrony" ]]; then
        if command -v chronyc &>/dev/null; then
            local sync_status=$(chronyc tracking 2>/dev/null | awk '/System time.*synchronized/{print "yes";}')
            if [[ "$sync_status" == "yes" ]]; then
                local sources_count=$(chronyc sources 2>/dev/null | grep -c "^\^[*+]" || echo "0")
                echo "时间同步: Chrony (${sources_count}个同步源) ✓"
                return 0
            fi
        fi
    fi

    log "配置Chrony时间同步..." "info"
    for service in "systemd-timesyncd" "ntp" "ntpd"; do
        if systemctl is-active "$service" &>/dev/null; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
        fi
    done

    if ! command -v chronyd &>/dev/null; then
        safe_apt_install chrony || {
            log "Chrony安装失败" "error"
            return 1
        }
    fi

    local chrony_conf="/etc/chrony/chrony.conf"
    if [[ -f "$chrony_conf" ]]; then
        cp "$chrony_conf" "${chrony_conf}.bak" 2>/dev/null || true
        if ! grep -q "makestep 1 3" "$chrony_conf" 2>/dev/null; then
            echo -e "\n# 优化配置 - 系统优化脚本添加\nmakestep 1 3\nrtcsync" >> "$chrony_conf"
        fi
    fi

    systemctl enable chrony >/dev/null 2>&1 || return 1
    systemctl start chrony >/dev/null 2>&1 || return 1

    sleep 3
    if systemctl is-active chrony &>/dev/null; then
        local sync_count=$(chronyc sources 2>/dev/null | grep -c "^\^[*+]" || echo "0")
        echo "时间同步: Chrony (${sync_count}个源同步) ✅"
        return 0
    else
        log "Chrony启动失败" "error"
        return 1
    fi
}

# === 主函数 ===
main() {
    if [[ $EUID -ne 0 ]]; then
        log "需要root权限运行此脚本" "error"
        echo "请使用: sudo $0"
        exit 1
    fi

    log "🚀 Debian 13 系统优化脚本" "success"
    echo "适配系统: Debian $DEBIAN_VERSION"
    echo "内核版本: $KERNEL_VERSION"
    echo

    if ! wait_for_package_manager; then
        log "继续执行，但可能遇到包管理问题" "warn"
    fi

    echo "=== 开始系统优化 ==="
    echo

    log "🌍 配置系统时区..." "info"
    setup_timezone || log "时区配置失败" "warn"

    echo
    echo "---"

    log "⏰ 配置时间同步..." "info"
    setup_chrony || log "时间同步配置失败" "warn"

    echo
    echo "=== 优化完成 ==="
    echo
    log "📊 系统状态摘要:" "info"
    echo "当前时区: $(timedatectl show --property=Timezone --value 2>/dev/null || echo '未知')"
    if systemctl is-active chrony &>/dev/null; then
        echo "时间同步: 活跃"
    else
        echo "时间同步: 未配置"
    fi
    echo
    log "✨ 系统优化脚本执行完成！" "success"
}

trap 'log "脚本异常退出" "error"' EXIT
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
