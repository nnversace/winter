#!/bin/bash

#=============================================================================
# Debian システム一鍵部署脚本
#
# 适用系统: Debian 12/13
# 作者: LucaLin233 (由 Gemini-Pro 优化)
#
# 功能:
#   - 模块化部署，按需选择安装
#   - 适配 Debian 13 Trixie
#   - 新增内核优化、网络优化及 MosDNS 模块
#   - 优化模块执行顺序，确保系统稳定性
#   - [优化] 单个模块失败后不中断整体流程
#
#=============================================================================

set -euo pipefail

#--- 全局常量 ---
readonly SCRIPT_NAME="one-click-debian-setup.sh"
readonly MODULE_BASE_URL="https://raw.githubusercontent.com/nnversace/winter/main/modules" # 确保这是您模块的正确URL
readonly TEMP_DIR="/tmp/debian-setup-modules"
readonly LOG_FILE="/var/log/debian-setup.log"
readonly SUMMARY_FILE="/root/deployment_summary.txt"

#--- 模块定义 (移除了 kernel_optimization) ---
declare -A MODULES=(
    ["system-optimize"]="基础系统优化 (Zram, 时区, 时间同步)"
    ["tools-setup"]="常用工具集 (NextTrace, SpeedTest 等)"
    ["network-optimize"]="网络性能优化"
    ["ssh-security"]="SSH 安全加固 (修改端口, 禁用密码登录)"
    ["mosdns-x"]="MosDNS-X DNS 服务"
    ["docker-setup"]="Docker & Docker Compose 容器化平台"
    ["auto-update-setup"]="配置系统自动更新"
)

#--- [优化] 模块执行顺序 (移除了 kernel_optimization) ---
# 1. 系统层优化 -> 2. 网络 -> 3. 安全配置 -> 4. 应用服务 -> 5. 维护任务
readonly ORDERED_MODULE_KEYS=(
    "system-optimize"
    "tools-setup"
    "network-optimize"
    "ssh-security"
    "mosdns-x"
    "docker-setup"
    "auto-update-setup"
)

#--- 执行状态变量 ---
EXECUTED_MODULES=()
FAILED_MODULES=()
SKIPPED_MODULES=()
SELECTED_MODULES=()
declare -A MODULE_EXEC_TIME=()
TOTAL_START_TIME=0

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#--- 日志与输出 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "info")     echo -e "${GREEN}[INFO] $msg${NC}" ;;
        "warn")     echo -e "${YELLOW}[WARN] $msg${NC}" ;;
        "error")    echo -e "${RED}[ERROR] $msg${NC}" ;;
        "success")  echo -e "${GREEN}🎉 [SUCCESS] $msg${NC}" ;;
        "header")   echo -e "\n${BLUE}--- $msg ---${NC}" ;;
    esac
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

print_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '='
}

#--- 错误处理与清理 ---
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "临时目录 $TEMP_DIR 已清理" "info"
    fi
    # 仅在脚本非正常退出时显示错误
    # The exit code is checked against the number of failed modules.
    # If they are equal, it means the script finished but some modules failed.
    # If they are not equal (and not 0), it means the script itself crashed.
    if (( exit_code != 0 && exit_code != ${#FAILED_MODULES[@]} )); then
        log "脚本意外终止 (退出码: $exit_code)。详情请查看日志: $LOG_FILE" "error"
    fi
}
trap cleanup EXIT INT TERM

#--- [优化] 系统检查 (适配 Debian 13) ---
check_system() {
    log "进行系统环境检查" "header"
    if (( EUID != 0 )); then
        log "此脚本需要以 root 权限运行" "error"
        exit 1
    fi
    
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/etc/os-release
        source /etc/os-release
        if [[ "$ID" == "debian" ]] && (( VERSION_ID == 12 || VERSION_ID == 13 )); then
            log "检测到 Debian $VERSION_ID ($PRETTY_NAME)，系统兼容。" "info"
        else
            log "此脚本专为 Debian 12/13 设计，当前系统为 $PRETTY_NAME，可能存在兼容性问题。" "warn"
        fi
    else
        log "无法确定操作系统版本，请谨慎操作。" "error"
        exit 1
    fi
}

#--- 网络检查 ---
check_network() {
    log "检查网络连接..." "info"
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log "网络连接失败。请检查您的网络设置后重试。" "error"
        exit 1
    fi
    log "网络连接正常。" "info"
}

#--- 安装基础依赖 ---
install_dependencies() {
    log "检查并安装基础依赖 (curl, wget, git...)" "header"
    local required_deps=("curl" "wget" "git" "jq" "rsync" "sudo" "dnsutils" "unzip")
    local missing_packages=()
    
    for pkg in "${required_deps[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing_packages+=("$pkg")
        fi
    done
    
    if (( ${#missing_packages[@]} > 0 )); then
        log "正在安装缺失的依赖: ${missing_packages[*]}" "info"
        apt-get update -qq || log "更新软件包列表失败" "warn"
        apt-get install -y "${missing_packages[@]}" || {
            log "依赖安装失败，请检查apt源。" "error"; exit 1
        }
    fi
    log "所有基础依赖均已安装。" "success"
}

#--- [新增] 交互式模块选择 ---
select_modules() {
    log "请选择您需要安装的模块" "header"
    echo "您可以输入多个数字，用空格隔开 (例如: 1 3 5)。按 Enter 键全选。"
    
    local i=1
    local options=()
    for key in "${ORDERED_MODULE_KEYS[@]}"; do
        printf "  [%d] %s\n" "$i" "${MODULES[$key]}"
        options+=("$key")
        ((i++))
    done
    
    read -rp "请输入选项 [默认全选]: " -a choices
    
    if (( ${#choices[@]} == 0 )); then
        SELECTED_MODULES=("${ORDERED_MODULE_KEYS[@]}")
        log "已选择全部模块。" "info"
        return
    fi
    
    for choice in "${choices[@]}"; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            SELECTED_MODULES+=("${options[choice-1]}")
        else
            log "无效选项: $choice" "warn"
        fi
    done
    
    # 去重
    # shellcheck disable=SC2207
    SELECTED_MODULES=($(echo "${SELECTED_MODULES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    if (( ${#SELECTED_MODULES[@]} == 0 )); then
        log "未选择任何有效模块，脚本将退出。" "error"
        exit 1
    fi
}

#--- 下载模块 ---
download_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    local download_url="${MODULE_BASE_URL}/${module}.sh"
    
    log "正在下载模块: $module..." "info"
    
    if curl -fsSL --connect-timeout 15 "$download_url" -o "$module_file"; then
        if [[ -s "$module_file" ]] && head -1 "$module_file" | grep -q "#!/bin/bash"; then
            chmod +x "$module_file"
            log "模块 $module 下载成功。" "success"
            return 0
        fi
    fi
    
    log "模块 $module 下载失败。请检查 URL 或网络: $download_url" "error"
    return 1
}

#--- [优化] 执行模块 (增加错误容忍) ---
execute_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    
    if [[ ! -f "$module_file" ]]; then
        log "模块脚本文件不存在: $module" "error"
        FAILED_MODULES+=("$module")
        return 1
    fi
    
    log "执行模块: ${MODULES[$module]}" "header"
    
    local start_time
    start_time=$(date +%s)
    
    local exec_result=0
    # 暂时禁用 exit-on-error (-e)，以便捕获模块的退出代码
    # 而不会导致主脚本终止。
    set +e
    bash "$module_file"
    exec_result=$?
    # 重新启用 exit-on-error
    set -e
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    MODULE_EXEC_TIME[$module]=$duration
    
    if (( exec_result == 0 )); then
        EXECUTED_MODULES+=("$module")
        log "模块 $module 执行成功 (耗时 ${duration}s)" "success"
        return 0
    else
        FAILED_MODULES+=("$module")
        log "模块 $module 执行失败 (退出码: $exec_result, 耗时 ${duration}s)" "error"
        return 1
    fi
}

#--- 系统状态获取 ---
get_system_status() {
    local status_info
    status_info="主机名: $(hostname)\n"
    status_info+="系统: $(source /etc/os-release && echo "$PRETTY_NAME")\n"
    status_info+="内核: $(uname -r)\n"
    status_info+="CPU: $(nproc) 核心\n"
    status_info+="内存: $(free -h | awk '/^Mem/ {print $3 "/" $2}')\n"
    status_info+="磁盘: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')\n"
    
    if command -v docker &>/dev/null; then
        status_info+="Docker: $(docker --version | awk '{print $3}' | tr -d ',')\n"
    else
        status_info+="Docker: 未安装\n"
    fi
    
    local ssh_port
    ssh_port=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    status_info+="SSH 端口: $ssh_port"
    
    echo -e "$status_info"
}

#--- 生成部署摘要 ---
generate_summary() {
    log "生成部署摘要" "header"
    local total_selected=${#SELECTED_MODULES[@]}
    local success_count=${#EXECUTED_MODULES[@]}
    local failed_count=${#FAILED_MODULES[@]}
    local success_rate=0
    if (( total_selected > 0 )); then
        success_rate=$(( success_count * 100 / total_selected ))
    fi
    local total_time=$(( $(date +%s) - TOTAL_START_TIME ))
    
    # 构建摘要内容
    local summary
    summary=$(cat <<-EOF
============================================================
             Debian 系统部署摘要 ($SCRIPT_NAME)
============================================================
部署完成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')
总耗时: ${total_time} 秒

--- 执行统计 ---
选择模块: $total_selected, 成功: $success_count, 失败: $failed_count, 成功率: ${success_rate}%

--- 模块详情 ---
✅ 成功模块:
$(for module in "${EXECUTED_MODULES[@]}"; do printf "  - %-22s (耗时: %s)\n" "$module" "${MODULE_EXEC_TIME[$module]}s"; done | sed '/^$/d')

❌ 失败模块:
$(for module in "${FAILED_MODULES[@]}"; do printf "  - %s\n" "$module"; done | sed '/^$/d')

--- 当前系统状态 ---
$(get_system_status | sed 's/^/  /')

--- 文件位置 ---
  - 详细日志: $LOG_FILE
  - 本摘要:   $SUMMARY_FILE
============================================================
EOF
)
    # 输出并保存
    echo -e "\n$summary" | tee "$SUMMARY_FILE"
    log "摘要已保存至: $SUMMARY_FILE" "info"
}

#--- 主函数 ---
main() {
    # 初始化
    mkdir -p "$TEMP_DIR"
    : > "$LOG_FILE"
    TOTAL_START_TIME=$(date +%s)
    
    clear
    print_line
    echo "欢迎使用 Debian 系统一键部署脚本"
    print_line
    
    # 准备阶段
    check_system
    check_network
    install_dependencies
    
    # 交互阶段
    select_modules
    
    log "已选择 ${#SELECTED_MODULES[@]} 个模块: ${SELECTED_MODULES[*]}" "info"
    read -p "配置完成，按 Enter 键开始执行..."
    
    # 执行阶段
    for module_key in "${ORDERED_MODULE_KEYS[@]}"; do
        if [[ " ${SELECTED_MODULES[*]} " =~ " ${module_key} " ]]; then
            if download_module "$module_key"; then
                # execute_module会处理失败情况，并记录到FAILED_MODULES
                execute_module "$module_key"
            else
                FAILED_MODULES+=("$module_key")
                log "因下载失败，跳过模块 $module_key" "warn"
            fi
        fi
    done
    
    # 完成阶段
    generate_summary

    # 提醒用户检查SSH模块的输出
    if [[ " ${EXECUTED_MODULES[*]} " =~ " ssh-security " ]]; then
        log "SSH 安全模块已执行。请检查该模块的输出日志以确认端口是否已更改以及如何重新连接。" "warn"
    fi
    
    if (( ${#FAILED_MODULES[@]} > 0 )); then
        log "部分模块执行失败，请检查日志: $LOG_FILE" "warn"
        # 脚本以失败模块的数量作为退出码
        exit "${#FAILED_MODULES[@]}"
    else
        log "所有任务已执行完毕！" "success"
    fi
}

# --- 脚本入口 ---
main "$@"
