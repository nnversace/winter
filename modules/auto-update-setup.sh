#!/bin/bash
#
# Debian 13 系统自动更新配置脚本
# 功能: 创建更新脚本并配置 Cron 定时任务，实现系统无人值守更新。
#

# --- 环境设置 ---
# -e: 命令失败时立即退出
# -u: 变量未定义时报错
# -o pipefail: 管道中任一命令失败则整个管道失败
set -euo pipefail

# --- 全局常量 ---
readonly UPDATE_SCRIPT_PATH="/usr/local/sbin/system-auto-update.sh"
readonly LOG_FILE="/var/log/system-auto-update.log"
readonly DEFAULT_CRON_SCHEDULE="0 2 * * 0" # 默认时间：每周日凌晨2点
readonly CRON_JOB_COMMENT="# 由此脚本管理的系统自动更新任务"

# --- 日志与消息输出 ---
# 带有颜色标记的日志函数
# 使用: log "消息" "类型"
# 类型: info(蓝), warn(黄), error(红), success(绿)
log() {
    local msg="$1"
    local level="${2:-info}"
    local color_code

    case "$level" in
        info) color_code="\033[0;36m" ;;  # 青色
        warn) color_code="\033[0;33m" ;;  # 黄色
        error) color_code="\033[0;31m" ;; # 红色
        success) color_code="\033[0;32m" ;; # 绿色
        *) color_code="\033[0m" ;;
    esac

    # >&2 表示输出到标准错误，避免干扰脚本的正常输出（例如函数返回值）
    echo -e "${color_code}[$(date '+%T')] ${msg}\033[0m" >&2
}

# --- 核心功能函数 ---

# 1. 检查并确保以 root 用户身份运行
ensure_root_privileges() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log "错误：此脚本需要以 root 权限运行。" "error"
        log "请尝试使用 'sudo bash $0' 或切换到 root 用户。" "info"
        exit 1
    fi
}

# 2. 检查并安装 Cron 服务
ensure_cron_service() {
    log "检查 Cron 服务状态..." "info"
    if ! command -v crontab &>/dev/null; then
        log "未检测到 cron，正在尝试安装..." "warn"
        if apt-get update -qq && apt-get install -y cron -qq; then
            log "Cron 安装成功。" "success"
        else
            log "Cron 安装失败，请手动安装后再运行此脚本。" "error"
            return 1
        fi
    fi

    if ! systemctl is-active --quiet cron; then
        log "Cron 服务未运行，正在启动并设置为开机自启..." "warn"
        systemctl start cron
        systemctl enable cron
    fi

    if systemctl is-active --quiet cron; then
        log "Cron 服务运行正常。" "success"
    else
        log "无法启动 Cron 服务，请检查系统日志。" "error"
        return 1
    fi
}

# 3. 创建核心的自动更新脚本
create_update_script() {
    log "创建系统更新脚本..." "info"
    # 使用 cat 和 HEREDOC 创建脚本文件
    if ! cat > "$UPDATE_SCRIPT_PATH" << 'EOF'; then
#!/bin/bash
#
# 系统自动更新执行脚本
# 由主配置脚本生成，请勿直接修改。
#

set -euo pipefail

readonly LOG_FILE="/var/log/system-auto-update.log"
# 非交互式更新，优先使用默认配置处理 dpkg 冲突
readonly APT_OPTIONS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# 记录日志到文件
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查内核是否更新，如有更新则准备重启
handle_kernel_update_and_reboot() {
    local current_kernel
    current_kernel=$(uname -r)
    # 查找 /boot 目录下最新的内核版本
    local latest_kernel
    latest_kernel=$(find /boot -name "vmlinuz-*" -printf "%f\n" 2>/dev/null | sed 's/vmlinuz-//' | sort -V | tail -1)

    if [[ -n "$latest_kernel" && "$current_kernel" != "$latest_kernel" ]]; then
        log_to_file "检测到新内核版本 ($latest_kernel)，系统将在1分钟后重启以应用更新。"
        sync # 同步磁盘缓存
        sleep 60
        # 优先使用 systemctl，如果失败则使用 reboot
        systemctl reboot || reboot
    fi
}

# --- 更新主流程 ---
log_to_file "======== 开始系统自动更新 ========"

# 1. 更新软件包列表
log_to_file "正在更新软件包列表 (apt update)..."
apt-get update -qq >> "$LOG_FILE" 2>&1

# 2. 执行系统升级
log_to_file "正在执行系统升级 (apt dist-upgrade)..."
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade $APT_OPTIONS >> "$LOG_FILE" 2>&1

# 3. 检查内核更新并处理重启
handle_kernel_update_and_reboot

# 4. 清理不再需要的软件包和缓存
log_to_file "正在清理无用软件包 (apt autoremove)..."
apt-get autoremove -y -qq >> "$LOG_FILE" 2>&1

log_to_file "正在清理旧的软件包缓存 (apt autoclean)..."
apt-get autoclean -qq >> "$LOG_FILE" 2>&1

log_to_file "======== 系统自动更新完成 ========"
exit 0
EOF
        log "创建更新脚本失败。" "error"
        return 1
    fi

    # 赋予脚本执行权限
    chmod +x "$UPDATE_SCRIPT_PATH"
    log "更新脚本已创建于: $UPDATE_SCRIPT_PATH" "success"
}

# 4. 配置 Cron 定时任务
setup_cron_job() {
    log "配置 Cron 定时任务..." "info"
    local cron_schedule

    # 检查是否已存在任务
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
            # 简单的格式验证
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

    # 使用临时文件来安全地更新 crontab
    local temp_cron_file
    temp_cron_file=$(mktemp)
    # 导出当前 crontab，并过滤掉旧的任务
    crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT_PATH" | grep -v "$CRON_JOB_COMMENT" > "$temp_cron_file" || true
    # 添加新的任务
    echo "$CRON_JOB_COMMENT" >> "$temp_cron_file"
    echo "$cron_schedule $UPDATE_SCRIPT_PATH" >> "$temp_cron_file"

    # 导入新的 crontab 配置
    if crontab "$temp_cron_file"; then
        log "定时任务配置成功。" "success"
    else
        log "定时任务配置失败。" "error"
        rm -f "$temp_cron_file"
        return 1
    fi
    rm -f "$temp_cron_file"
}

# 5. 显示最终配置摘要
show_summary() {
    echo
    log "---------- 自动更新配置摘要 ----------" "info"
    
    if [[ -x "$UPDATE_SCRIPT_PATH" ]]; then
        echo -e "  \033[0;32m✓\033[0m 更新脚本: 已创建 ($UPDATE_SCRIPT_PATH)"
    else
        echo -e "  \033[0;31m✗\033[0m 更新脚本: 未找到"
    fi

    if systemctl is-active --quiet cron; then
        echo -e "  \033[0;32m✓\033[0m Cron 服务: 运行中"
    else
        echo -e "  \033[0;31m✗\033[0m Cron 服务: 未运行"
    fi
    
    if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT_PATH"; then
        local cron_line
        cron_line=$(crontab -l | grep "$UPDATE_SCRIPT_PATH")
        echo -e "  \033[0;32m✓\033[0m 定时任务: 已配置"
        echo -e "    执行计划: $cron_line"
    else
        echo -e "  \033[0;31m✗\033[0m 定时任务: 未配置"
    fi

    echo -e "  \033[0;36mⓘ\033[0m 日志文件: $LOG_FILE"
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

# --- 主函数入口 ---
main() {
    # 捕获任何错误，并给出提示
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

# --- 脚本执行 ---
main "$@"
