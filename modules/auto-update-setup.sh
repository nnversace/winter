#!/usr/bin/env bash
#
# 自动更新系统配置模块 v5.0 - 优化版
#
# 功能:
#   - 安装并配置 cron 服务。
#   - 创建一个健壮的每日自动更新脚本。
#   - 设置定时任务 (cron job) 来执行更新。
#   - 提供测试和卸载功能。
#
# 改进:
#   - 增强了错误处理和日志记录。
#   - 优化了用户交互和提示。
#   - 增加了 root 权限检查和卸载功能。
#   - 提高了脚本的健壮性和可读性。
#

# --- 环境设置 ---
# -e: 如果命令返回非零退出状态，则立即退出。
# -u: 将未设置的变量视为错误。
# -o pipefail: 如果管道中的任何命令失败，则整个管道的退出状态为失败。
set -euo pipefail

# --- 常量定义 ---
# 使用 readonly 确保这些变量不会被意外修改。
readonly UPDATE_SCRIPT_PATH="/usr/local/bin/auto-system-update.sh"
readonly LOG_FILE_PATH="/var/log/auto-system-update.log"
readonly DEFAULT_CRON_SCHEDULE="0 2 * * 0" # 默认：每周日凌晨2点
readonly CRON_JOB_COMMENT="# Auto-update job managed by setup script"
readonly SCRIPT_VERSION="5.0"

# --- 颜色定义 (用于日志输出) ---
# 使用 tput 动态检测终端能力，如果不支持颜色则禁用。
if tput setaf 1 > /dev/null 2>&1; then
    readonly COLOR_RESET="\033[0m"
    readonly COLOR_INFO="\033[0;36m"    # 青色
    readonly COLOR_SUCCESS="\033[0;32m" # 绿色
    readonly COLOR_WARN="\033[0;33m"    # 黄色
    readonly COLOR_ERROR="\033[0;31m"   # 红色
    readonly COLOR_DEBUG="\033[0;35m"   # 紫色
else
    readonly COLOR_RESET=""
    readonly COLOR_INFO=""
    readonly COLOR_SUCCESS=""
    readonly COLOR_WARN=""
    readonly COLOR_ERROR=""
    readonly COLOR_DEBUG=""
fi


# --- 工具函数 ---

# 统一的日志输出函数
# 参数:
#   $1: 消息内容
#   $2: 日志级别 (info, success, warn, error, debug)
log() {
    local msg="${1}"
    local level="${2:-info}"
    local color="${COLOR_INFO}"

    case "${level}" in
        success) color="${COLOR_SUCCESS}" ;;
        warn)    color="${COLOR_WARN}" ;;
        error)   color="${COLOR_ERROR}" ;;
        debug)   color="${COLOR_DEBUG}" ;;
    esac

    # 使用 printf 保证输出的可靠性
    printf "%b[%s] %s%b\n" "${color}" "$(date '+%Y-%m-%d %H:%M:%S')" "${msg}" "${COLOR_RESET}"
}

# Debug 日志函数，仅在 DEBUG=1 时输出
debug_log() {
    # 检查 DEBUG 环境变量是否设置为 "1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log "$1" "debug" >&2
    fi
}

# 检查脚本是否以 root 权限运行
check_root_privileges() {
    debug_log "Checking for root privileges."
    if [[ "$(id -u)" -ne 0 ]]; then
        log "此脚本需要以 root 权限运行。" "error"
        exit 1
    fi
}

# 统一处理用户交互
# 参数:
#   $1: 提示信息
#   $2: 默认值 (Y/n 或 y/N)
ask_user() {
    local prompt="$1"
    local default="${2:-}"
    local answer

    while true; do
        read -rp "${prompt} [${default}] " answer
        answer="${answer:-${default}}" # 如果用户直接回车，则使用默认值
        case "${answer}" in
            [Yy]*) return 0 ;; # 返回 0 代表 "是"
            [Nn]*) return 1 ;; # 返回 1 代表 "否"
            *) log "无效输入，请输入 'y' 或 'n'。" "warn" ;;
        esac
    done
}

# 验证 Cron 表达式格式
validate_cron_expression() {
    local expr="$1"
    debug_log "Validating cron expression: ${expr}"
    # 一个相对宽松但能覆盖大多数情况的正则表达式
    if [[ "$expr" =~ ^\s*([0-9*,-/]+)\s+([0-9*,-/]+)\s+([0-9*,-/]+)\s+([0-9*,-/]+)\s+([0-9*,-/]+)\s*$ ]]; then
        debug_log "Cron expression validation passed."
        return 0
    else
        debug_log "Cron expression validation failed."
        return 1
    fi
}

# --- 核心功能 ---

# 1. 确保 cron 服务已安装并正在运行
ensure_cron_service() {
    log "检查 cron 服务状态..." "info"
    if ! command -v crontab &> /dev/null; then
        log "未找到 cron 服务，正在尝试安装..." "warn"
        # 尝试更新并安装 cron
        if apt-get update -qq && apt-get install -y -qq cron; then
            log "cron 服务安装成功。" "success"
        else
            log "cron 服务安装失败。请手动安装后再运行此脚本。" "error"
            return 1
        fi
    fi

    # 检查服务是否正在运行，如果不是则尝试启动
    if ! systemctl is-active --quiet cron; then
        log "cron 服务未运行，正在启动..." "warn"
        if systemctl enable --now cron &> /dev/null; then
             log "cron 服务启动成功。" "success"
        else
            log "cron 服务启动失败。" "error"
            return 1
        fi
    fi
    log "cron 服务已准备就绪。" "success"
}

# 2. 创建自动更新脚本
create_update_script() {
    log "创建自动更新脚本..." "info"
    
    # 检查 unattended-upgrades 是否已安装，如果已安装则提示用户
    if dpkg -s unattended-upgrades &> /dev/null; then
        log "检测到系统已安装 'unattended-upgrades' 包。" "warn"
        log "使用此脚本可能会与现有配置冲突。建议使用 'dpkg-reconfigure -plow unattended-upgrades' 进行配置。" "warn"
        if ! ask_user "是否仍要继续创建自定义更新脚本?" "y/N"; then
            log "操作已取消。" "info"
            return 1
        fi
    fi

    # 使用 heredoc 创建脚本文件
    # 'EOF' 使用引号可以防止变量扩展
    if ! cat > "${UPDATE_SCRIPT_PATH}" << 'EOF'; then
#!/usr/bin/env bash
#
# 自动系统更新脚本 v5.0
# 由 auto-update-setup.sh 脚本生成
#

set -euo pipefail

readonly LOG_FILE="/var/log/auto-system-update.log"
# 为 apt-get 设置非交互式前端，并使用默认配置文件
readonly APT_OPTIONS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
readonly DEBIAN_FRONTEND=noninteractive

# 记录日志并打印到标准输出
log_update() {
    # tee -a: 追加到文件而不是覆盖
    echo "[$ (date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# 检查网络连接
check_connectivity() {
    # 使用 ping 命令检查与 8.8.8.8 的连通性
    if ! ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
        log_update "错误: 无网络连接，跳过更新。"
        exit 1
    fi
}

# 检查内核更新后是否需要重启
check_reboot_required() {
    log_update "检查是否需要重启..."
    # /var/run/reboot-required 文件是 Debian/Ubuntu 系统建议重启的标准标志
    if [[ -f /var/run/reboot-required ]]; then
        log_update "警告: 检测到需要重启系统以应用更新 (例如新内核)。"
        local reboot_msg
        reboot_msg=$(cat /var/run/reboot-required)
        log_update "原因: ${reboot_msg}"
        log_update "系统将在1分钟后自动重启..."
        # 等待一段时间以确保日志被写入
        sleep 60
        # 确保 sshd 正在运行，以防万一
        systemctl is-active --quiet sshd || systemctl start sshd
        sync
        systemctl reboot
    fi
}

# 主函数
main() {
    # 每次运行时覆盖旧日志，或者使用 '>>' 来追加
    log_update "=== 开始自动系统更新 ==="

    check_connectivity

    log_update "更新软件包列表..."
    # 将标准输出和错误都重定向到日志
    apt-get update -qq >> "${LOG_FILE}" 2>&1

    log_update "升级系统软件包..."
    apt-get dist-upgrade ${APT_OPTIONS} >> "${LOG_FILE}" 2>&1

    log_update "清理无用的软件包和缓存..."
    apt-get autoremove -y -qq >> "${LOG_FILE}" 2>&1
    apt-get autoclean -qq >> "${LOG_FILE}" 2>&1

    check_reboot_required

    log_update "=== 自动更新完成 ==="
}

# 设置错误陷阱，捕获任何错误并记录
trap 'log_update "错误: 更新过程中发生错误 (行号: $LINENO)"' ERR

# 运行主函数
main "$@"

EOF
    then
        log "无法写入更新脚本到 ${UPDATE_SCRIPT_PATH}。" "error"
        return 1
    fi

    # 赋予脚本执行权限
    chmod +x "${UPDATE_SCRIPT_PATH}"
    log "更新脚本已创建: ${UPDATE_SCRIPT_PATH}" "success"
}

# 3. 配置 cron 定时任务
setup_cron_job() {
    log "配置 cron 定时任务..." "info"
    local cron_schedule

    # 检查是否已存在任务
    if crontab -l 2>/dev/null | grep -q "${UPDATE_SCRIPT_PATH}"; then
        if ! ask_user "检测到已存在更新任务，是否要覆盖?" "y/N"; then
            log "保留现有定时任务。" "info"
            return 0
        fi
    fi

    # 获取用户选择的执行时间
    if ask_user "是否使用默认更新时间 (每周日凌晨2点)?" "Y/n"; then
        cron_schedule="${DEFAULT_CRON_SCHEDULE}"
    else
        while true; do
            read -rp "请输入自定义 Cron 表达式 (分 时 日 月 周): " cron_schedule
            if validate_cron_expression "${cron_schedule}"; then
                break
            else
                log "无效的 Cron 表达式格式，请重新输入。" "warn"
            fi
        done
    fi

    # 使用临时文件来安全地更新 crontab
    local temp_cron_file
    temp_cron_file=$(mktemp)
    
    # 移除旧的任务（如果有的话），然后添加新的任务
    (crontab -l 2>/dev/null | grep -vF "${CRON_JOB_COMMENT}" | grep -vF "${UPDATE_SCRIPT_PATH}"; \
     echo "${CRON_JOB_COMMENT}"; \
     echo "${cron_schedule} ${UPDATE_SCRIPT_PATH}") > "${temp_cron_file}"

    if crontab "${temp_cron_file}"; then
        log "cron 定时任务配置成功。" "success"
        log "执行时间: ${cron_schedule}" "info"
    else
        log "cron 定时任务配置失败。" "error"
        return 1
    fi
    # 清理临时文件
    rm -f "${temp_cron_file}"
}

# 4. 测试更新脚本
test_update_script() {
    if ask_user "是否立即运行一次更新脚本进行测试?" "y/N"; then
        log "开始测试更新脚本... (这可能需要一些时间)" "info"
        echo "========================= 测试输出开始 ========================="
        # 直接调用脚本并显示输出
        if bash "${UPDATE_SCRIPT_PATH}"; then
            log "测试执行成功。" "success"
        else
            log "测试执行过程中出现错误。" "error"
        fi
        echo "========================= 测试输出结束 ========================="
        log "详细日志请查看: ${LOG_FILE_PATH}" "info"
    else
        log "跳过脚本测试。" "info"
    fi
}

# 5. 显示配置摘要
show_summary() {
    printf "\n%b--- 自动更新配置摘要 ---%b\n" "${COLOR_SUCCESS}" "${COLOR_RESET}"
    
    # Cron 服务状态
    if systemctl is-active --quiet cron; then
        printf "  %-20s: %b运行中%b\n" "Cron 服务" "${COLOR_SUCCESS}" "${COLOR_RESET}"
    else
        printf "  %-20s: %b未运行%b\n" "Cron 服务" "${COLOR_ERROR}" "${COLOR_RESET}"
    fi

    # 更新脚本状态
    if [[ -x "${UPDATE_SCRIPT_PATH}" ]]; then
        printf "  %-20s: %b已创建%b\n" "更新脚本" "${COLOR_SUCCESS}" "${COLOR_RESET}"
    else
        printf "  %-20s: %b未找到%b\n" "更新脚本" "${COLOR_ERROR}" "${COLOR_RESET}"
    fi

    # 定时任务状态
    if crontab -l 2>/dev/null | grep -q "${UPDATE_SCRIPT_PATH}"; then
        local cron_line
        cron_line=$(crontab -l 2>/dev/null | grep "${UPDATE_SCRIPT_PATH}")
        printf "  %-20s: %b已配置%b\n" "定时任务" "${COLOR_SUCCESS}" "${COLOR_RESET}"
        printf "    %-18s: %s\n" "执行计划" "${cron_line}"
    else
        printf "  %-20s: %b未配置%b\n" "定时任务" "${COLOR_WARN}" "${COLOR_RESET}"
    fi
    
    printf "%b--------------------------%b\n" "${COLOR_SUCCESS}" "${COLOR_RESET}"
    log "常用命令:" "info"
    echo "  - 手动执行更新: ${UPDATE_SCRIPT_PATH}"
    echo "  - 查看实时日志: tail -f ${LOG_FILE_PATH}"
    echo "  - 编辑定时任务: crontab -e"
    echo "  - 卸载自动更新: bash $0 --uninstall"
}

# 6. 卸载功能
uninstall() {
    log "开始卸载自动更新配置..." "warn"
    if ! ask_user "这将移除更新脚本和相关的 cron 任务，是否确认?" "y/N"; then
        log "卸载操作已取消。" "info"
        exit 0
    fi

    # 移除 cron 任务
    if crontab -l 2>/dev/null | grep -q "${UPDATE_SCRIPT_PATH}"; then
        crontab -l | grep -vF "${UPDATE_SCRIPT_PATH}" | crontab -
        log "cron 定时任务已移除。" "success"
    else
        log "未找到相关的 cron 任务。" "info"
    fi

    # 移除脚本文件
    if [[ -f "${UPDATE_SCRIPT_PATH}" ]]; then
        rm -f "${UPDATE_SCRIPT_PATH}"
        log "更新脚本已删除: ${UPDATE_SCRIPT_PATH}" "success"
    fi

    # 询问是否移除日志文件
    if [[ -f "${LOG_FILE_PATH}" ]]; then
        if ask_user "是否要删除日志文件 ${LOG_FILE_PATH}?" "Y/n"; then
            rm -f "${LOG_FILE_PATH}"
            log "日志文件已删除。" "success"
        fi
    fi

    log "卸载完成。" "success"
}


# --- 主函数 ---
main() {
    # 脚本启动时清理屏幕，提供更清晰的界面
    clear
    log "欢迎使用自动更新配置脚本 (v${SCRIPT_VERSION})" "info"
    echo

    # 检查命令行参数
    if [[ "${1:-}" == "--uninstall" ]]; then
        uninstall
        exit 0
    fi

    # 依次执行各个配置步骤
    ensure_cron_service
    # 如果上一步失败，后续步骤将因为 set -e 而不会执行
    
    if ! create_update_script; then
        log "未能完成配置，已中止。" "error"
        exit 1
    fi
    
    setup_cron_job
    
    test_update_script
    
    show_summary
    
    log "所有配置已完成！" "success"
}

# --- 脚本入口 ---

# 确保在脚本退出时（无论是正常还是异常）都执行清理
cleanup() {
    debug_log "Performing cleanup..."
    # 如果创建了临时文件，在这里删除
    rm -f /tmp/temp_cron_file_*
}

# 检查 root 权限
check_root_privileges

# 设置 trap，在脚本退出、中断或出错时调用 cleanup 函数
trap cleanup EXIT
trap 'log "脚本被中断。" "error"; exit 1' INT TERM
trap 'log "脚本在行号 $LINENO 处发生错误。" "error"; exit 1' ERR

# 执行主函数，并传递所有命令行参数
main "$@"

