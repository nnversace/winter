#!/bin/bash

#================================================================================
# Debian 13 系统自动更新配置脚本 (优化版)
# 功能: 创建更新脚本并配置 Cron 定时任务，实现系统无人值守更新
# 适用系统: Debian 12/13+
#================================================================================

set -euo pipefail

#--- 全局常量 ---
readonly UPDATE_SCRIPT_PATH="/usr/local/sbin/system-auto-update.sh"
readonly LOG_FILE="/var/log/system-auto-update.log"
readonly DEFAULT_CRON_SCHEDULE="0 2 * * 0"
readonly CRON_JOB_COMMENT="# System auto-update managed by deployment script"

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#--- 日志与消息输出 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local color_code

    case "$level" in
        info)    color_code="${BLUE}" ;;
        warn)    color_code="${YELLOW}" ;;
        error)   color_code="${RED}" ;;
        success) color_code="${GREEN}" ;;
        *)       color_code="${NC}" ;;
    esac

    echo -e "${color_code}[$(date '+%T')] ${msg}${NC}" >&2
}

#--- 核心功能函数 ---

ensure_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log "错误：此脚本需要以 root 权限运行。" "error"
        log "请尝试使用 'sudo bash $0' 或切换到 root 用户。" "info"
        exit 1
    fi
}

ensure_cron_service() {
    log "检查 Cron 服务状态..." "info"
    
    if ! command -v crontab &>/dev/null; then
        log "未检测到 cron，正在尝试安装..." "warn"
        if apt-get update -qq 2>/dev/null && \
           DEBIAN_FRONTEND=noninteractive apt-get install -y cron -qq 2>/dev/null; then
            log "Cron 安装成功。" "success"
        else
            log "Cron 安装失败，请手动安装后再运行此脚本。" "error"
            return 1
        fi
    fi

    if ! systemctl is-active --quiet cron 2>/dev/null; then
        log "Cron 服务未运行，正在启动并设置为开机自启..." "warn"
        systemctl start cron 2>/dev/null || true
        systemctl enable cron 2>/dev/null || true
    fi

    if systemctl is-active --quiet cron 2>/dev/null; then
        log "Cron 服务运行正常。" "success"
    else
        log "无法启动 Cron 服务，请检查系统日志。" "error"
        return 1
    fi
}

create_update_script() {
    log "创建系统更新脚本..." "info"
    
    if ! cat > "$UPDATE_SCRIPT_PATH" << 'EOF'; then
#!/bin/bash

#================================================================================
# 系统自动更新执行脚本 (Debian 13 优化版)
# 由主配置脚本生成，请勿直接修改。
#================================================================================

set -euo pipefail

readonly LOG_FILE="/var/log/system-auto-update.log"
readonly APT_OPTIONS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
readonly LOCKFILE="/var/run/system-auto-update.lock"

log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

acquire_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_to_file "另一个更新进程正在运行 (PID: $pid)，退出。"
            exit 0
        else
            log_to_file "发现过期的锁文件，将清除并继续。"
            rm -f "$LOCKFILE"
        fi
    fi
    echo "$$" > "$LOCKFILE"
    trap 'rm -f "$LOCKFILE"' EXIT
}

wait_for_apt_lock() {
    local max_wait=300
    local waited=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if (( waited >= max_wait )); then
            log_to_file "等待 APT 锁超时，退出。"
            return 1
        fi
        if (( waited == 0 )); then
            log_to_file "检测到 APT 锁，等待释放..."
        fi
        sleep 10
        waited=$((waited + 10))
    done
    return 0
}

handle_kernel_update_and_reboot() {
    local current_kernel
    current_kernel=$(uname -r)
    
    local latest_kernel
    latest_kernel=$(find /boot -name "vmlinuz-*" -printf "%f\n" 2>/dev/null | \
                    sed 's/vmlinuz-//' | sort -V | tail -1)

    if [[ -n "$latest_kernel" && "$current_kernel" != "$latest_kernel" ]]; then
        log_to_file "检测到新内核版本 ($latest_kernel)，系统将在1分钟后重启以应用更新。"
        sync
        sleep 60
        systemctl reboot || reboot
    fi
}

perform_cleanup() {
    log_to_file "正在清理无用软件包 (apt autoremove)..."
    apt-get autoremove $APT_OPTIONS >> "$LOG_FILE" 2>&1 || \
        log_to_file "警告：autoremove 执行失败"
    
    log_to_file "正在清理旧的软件包缓存 (apt autoclean)..."
    apt-get autoclean -qq >> "$LOG_FILE" 2>&1 || \
        log_to_file "警告：autoclean 执行失败"
}

check_disk_space() {
    local available_mb
    available_mb=$(df /var/cache/apt/archives | awk 'NR==2 {print int($4/1024)}')
    
    if (( available_mb < 500 )); then
        log_to_file "警告：磁盘空间不足 (可用: ${available_mb}MB)，先清理缓存..."
        apt-get clean -qq 2>/dev/null || true
    fi
}

main() {
    acquire_lock
    wait_for_apt_lock || exit 1
    
    log_to_file "======== 开始系统自动更新 ========"
    
    check_disk_space
    
    log_to_file "正在更新软件包列表 (apt update)..."
    if ! apt-get update -qq >> "$LOG_FILE" 2>&1; then
        log_to_file "错误：apt update 失败"
        exit 1
    fi
    
    log_to_file "正在执行系统升级 (apt dist-upgrade)..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade $APT_OPTIONS >> "$LOG_FILE" 2>&1; then
        log_to_file "错误：apt dist-upgrade 失败"
        exit 1
    fi
    
    handle_kernel_update_and_reboot
    
    perform_cleanup
    
    log_to_file "======== 系统自动更新完成 ========"
}

main "$@"
EOF
        log "创建更新脚本失败。" "error"
        return 1
    fi

    chmod +x "$UPDATE_SCRIPT_PATH"
    log "更新脚本已创建于: $UPDATE_SCRIPT_PATH" "success"
}

setup_cron_job() {
    log "配置 Cron 定时任务..." "info"
    local cron_schedule

    if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT_PATH"; then
        local overwrite
        read -p "检测到已存在的更新任务，是否要覆盖？[y/N]: " -r overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log "操作已取消，保留现有任务。" "warn"
            return
        fi
    fi

    local use_default
    read -p "是否使用默认更新时间 (每周日凌晨2点)？[Y/n]: " -r use_default
    if [[ "$use_default" =~ ^[Nn]$ ]]; then
        log "请输入自定义 Cron 表达式 (格式: 分 时 日 月 周)，例如 '0 3 * * 1' 表示每周一凌晨3点。" "info"
        while true; do
            read -p "请输入: " -r custom_schedule
            if [[ "$custom_schedule" =~ ^[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+[[:space:]]+[0-9*,/-]+$ ]]; then
                cron_schedule="$custom_schedule"
                log "自定义时间已设置为: $cron_schedule" "success"
                break
            else
                log "格式无效，请重新输入。" "error"
            fi
        done
    else
        cron_schedule="$DEFAULT_CRON_SCHEDULE"
        log "使用默认更新时间。" "info"
    fi

    local temp_cron_file
    temp_cron_file=$(mktemp)
    
    crontab -l 2>/dev/null | \
        grep -v "$UPDATE_SCRIPT_PATH" | \
        grep -v "$CRON_JOB_COMMENT" > "$temp_cron_file" || true
    
    echo "$CRON_JOB_COMMENT" >> "$temp_cron_file"
    echo "$cron_schedule $UPDATE_SCRIPT_PATH >> $LOG_FILE 2>&1" >> "$temp_cron_file"

    if crontab "$temp_cron_file"; then
        log "定时任务配置成功。" "success"
    else
        log "定时任务配置失败。" "error"
        rm -f "$temp_cron_file"
        return 1
    fi
    rm -f "$temp_cron_file"
}

show_summary() {
    echo
    log "---------- 自动更新配置摘要 ----------" "info"
    
    if [[ -x "$UPDATE_SCRIPT_PATH" ]]; then
        echo -e "  ${GREEN}✓${NC} 更新脚本: 已创建 ($UPDATE_SCRIPT_PATH)"
    else
        echo -e "  ${RED}✗${NC} 更新脚本: 未找到"
    fi

    if systemctl is-active --quiet cron 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Cron 服务: 运行中"
    else
        echo -e "  ${RED}✗${NC} Cron 服务: 未运行"
    fi
    
    if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT_PATH"; then
        local cron_line
        cron_line=$(crontab -l 2>/dev/null | grep "$UPDATE_SCRIPT_PATH")
        echo -e "  ${GREEN}✓${NC} 定时任务: 已配置"
        echo -e "    执行计划: $cron_line"
    else
        echo -e "  ${RED}✗${NC} 定时任务: 未配置"
    fi

    echo -e "  ${BLUE}ⓘ${NC} 日志文件: $LOG_FILE"
    log "------------------------------------" "info"
    echo
    log "常用管理命令:" "info"
    echo "  - 查看任务: crontab -l"
    echo "  - 编辑任务: crontab -e"
    echo "  - 手动执行: sudo $UPDATE_SCRIPT_PATH"
    echo "  - 实时日志: tail -f $LOG_FILE"
    echo "  - 移除任务: (crontab -l | grep -v '$UPDATE_SCRIPT_PATH' | crontab -)"
    echo
}

#--- 主函数入口 ---
main() {
    trap 'log "脚本在中途发生错误，请检查上面的输出。" "error"' ERR

    clear
    echo "=========================================="
    echo "  Debian 13 系统自动更新配置工具"
    echo "=========================================="
    echo
    
    ensure_root_privileges
    ensure_cron_service
    create_update_script
    setup_cron_job
    
    show_summary
    
    log "所有配置已完成！" "success"
}

main "$@"
