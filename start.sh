#!/bin/bash

#================================================================================
# Debian 系统定制部署脚本
# 适用系统: Debian 12/13+
# 作者: LucaLin233 (由 Gemini 定制修改)
# 功能: 模块化部署，从远程库下载并执行指定模块
#================================================================================

set -euo pipefail

#--- 全局常量 ---
readonly MODULE_BASE_URL="https://raw.githubusercontent.com/LucaLin233/Linux/refs/heads/main/modules"
readonly TEMP_DIR="/tmp/debian-setup-modules"
readonly LOG_FILE="/var/log/debian-custom-setup.log"
readonly SUMMARY_FILE="/root/deployment_summary_custom.txt"

#--- 模块定义 ---
declare -A MODULES=(
    ["system-optimize"]="系统优化 (Zram, 时区, 时间同步)"
    ["docker-setup"]="Docker 容器化平台"
    ["tools-setup"]="系统工具 (NextTrace, SpeedTest等)"
    ["auto-update-setup"]="自动更新系统"
    ["kernel-optimize"]="内核参数深度优化 (TCP BBR, 文件句柄等)"
)

#--- 执行状态 ---
EXECUTED_MODULES=()
FAILED_MODULES=()
SELECTED_MODULES=()
declare -A MODULE_EXEC_TIME=()
TOTAL_START_TIME=0

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

#--- 日志函数 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "info")    echo -e "${GREEN}✅ [INFO] $msg${NC}" ;;
        "warn")    echo -e "${YELLOW}⚠️  [WARN] $msg${NC}" ;;
        "error")   echo -e "${RED}❌ [ERROR] $msg${NC}" ;;
        "success") echo -e "${GREEN}🎉 [SUCCESS] $msg${NC}" ;;
    esac
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

#--- 分隔线 ---
print_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '='
}

#--- 错误处理 ---
cleanup() {
    local exit_code=$?
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    if (( exit_code != 0 )); then
        log "脚本异常退出，请检查日志: $LOG_FILE" "error"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

#--- 基础检查 ---
check_system() {
    log "执行系统环境预检查..."
    if (( EUID != 0 )); then
        log "此脚本需要 root 权限才能运行。" "error"
        exit 1
    fi
    
    if [[ ! -f /etc/debian_version ]] || (( $(cut -d'.' -f1 /etc/debian_version) < 12 )); then
        log "此脚本推荐在 Debian 12 或更高版本上运行。" "warn"
    fi
    log "系统检查通过。"
}

#--- 网络检查 ---
check_network() {
    log "检查网络连接..."
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log "网络连接可能存在问题，可能会影响模块下载。" "warn"
        read -p "是否继续执行? [y/N]: " -r choice
        [[ "$choice" =~ ^[Yy]$ ]] || exit 0
    fi
    log "网络连接正常。"
}

#--- 安装基础依赖 ---
install_dependencies() {
    log "检查并安装基础依赖..."
    local missing_packages=()
    for pkg in curl wget git jq rsync sudo; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_packages+=("$pkg")
        fi
    done
    
    if (( ${#missing_packages[@]} > 0 )); then
        log "正在安装缺失的依赖: ${missing_packages[*]}"
        apt-get update -qq || log "更新软件包列表失败" "warn"
        apt-get install -y "${missing_packages[@]}" || {
            log "依赖安装失败，请手动安装后重试。" "error"
            exit 1
        }
    fi
    log "基础依赖已满足。"
}

#--- 模块选择 ---
select_modules() {
    log "选择要部署的模块"
    
    # 定义最佳执行顺序
    local master_order=(system-optimize kernel-optimize auto-update-setup docker-setup tools-setup)
    
    echo
    print_line
    echo "部署模式选择："
    echo "1) 🚀 全部安装 (按优化顺序安装所有模块)"
    echo "2) 🎯 自定义选择 (按需选择模块)"
    echo
    
    read -p "请选择模式 [1-2]: " -r mode_choice
    
    local user_selected_modules=()
    
    case "$mode_choice" in
        1)
            user_selected_modules=("${master_order[@]}")
            log "选择模式: 全部安装"
            ;;
        2)
            echo "可用模块："
            local i=1
            local module_keys=()
            # 按照 master_order 的顺序显示给用户
            for key in "${master_order[@]}"; do
                echo "$i) ${MODULES[$key]}"
                module_keys+=("$key")
                ((i++))
            done
            
            echo "请输入要安装的模块编号 (用空格分隔, 如: 1 3 5):"
            read -r selection
            
            for num in $selection; do
                if [[ "$num" =~ ^[1-5]$ ]]; then
                    local index=$((num - 1))
                    user_selected_modules+=("${module_keys[$index]}")
                else
                    log "跳过无效编号: $num" "warn"
                fi
            done
            
            if (( ${#user_selected_modules[@]} == 0 )); then
                log "未选择任何有效模块，退出。" "warn"
                exit 0
            fi
            log "已选择模块: ${user_selected_modules[*]}"
            ;;
        *)
            log "无效选择，默认执行全部安装。" "warn"
            user_selected_modules=("${master_order[@]}")
            ;;
    esac

    # 根据 master_order 排序用户的选择
    local final_selection=()
    for module in "${master_order[@]}"; do
        for selected in "${user_selected_modules[@]}"; do
            if [[ "$module" == "$selected" ]]; then
                final_selection+=("$module")
                break
            fi
        done
    done
    SELECTED_MODULES=("${final_selection[@]}")
}

#--- 下载模块 ---
download_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    local download_url="${MODULE_BASE_URL}/${module}.sh"
    
    log "正在下载模块: $module"
    
    if curl -fsSL --connect-timeout 10 "$download_url" -o "$module_file"; then
        if [[ -s "$module_file" ]] && head -1 "$module_file" | grep -q "#!/bin/bash"; then
            chmod +x "$module_file"
            return 0
        fi
    fi
    
    log "模块 $module 下载失败。" "error"
    return 1
}

#--- 执行模块 ---
execute_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    
    log "执行模块: ${MODULES[$module]}"
    
    local start_time=$(date +%s)
    local exec_result=0
    
    if [[ ! -f "$module_file" ]]; then
        log "模块文件不存在: $module" "error"
        exec_result=1
    else
        bash "$module_file" || exec_result=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    MODULE_EXEC_TIME[$module]=$duration
    
    if (( exec_result == 0 )); then
        EXECUTED_MODULES+=("$module")
        log "模块 $module 执行成功 (耗时 ${duration}s)。" "success"
    else
        FAILED_MODULES+=("$module")
        log "模块 $module 执行失败 (耗时 ${duration}s)。" "error"
    fi
}

#--- 生成摘要 ---
generate_summary() {
    log "生成部署摘要..."
    
    local total_time=$(( $(date +%s) - TOTAL_START_TIME ))
    
    # 准备摘要内容
    local summary
    summary=$(cat <<EOF
============================================================
           Debian 系统定制部署摘要
============================================================
- 部署时间: $(date '+%Y-%m-%d %H:%M:%S %Z')
- 总耗时: ${total_time} 秒
- 主机名: $(hostname)
- 系统: $(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')
- IP 地址: $(hostname -I | awk '{print $1}')

--- 执行统计 ---
- ✅ 成功模块 (${#EXECUTED_MODULES[@]}): ${EXECUTED_MODULES[*]:-}
- ❌ 失败模块 (${#FAILED_MODULES[@]}): ${FAILED_MODULES[*]:-}

--- 模块耗时详情 ---
EOF
)
    for module in "${!MODULE_EXEC_TIME[@]}"; do
        summary+=$'\n'"- ${module}: ${MODULE_EXEC_TIME[$module]}s"
    done
    summary+=$'\n\n'"--- 文件位置 ---\n- 日志文件: $LOG_FILE\n- 摘要文件: $SUMMARY_FILE"
    summary+=$'\n'"============================================================"

    # 打印到屏幕并保存到文件
    echo -e "\n$summary"
    echo -e "$summary" > "$SUMMARY_FILE" 2>/dev/null || true
    
    log "摘要已保存至: $SUMMARY_FILE"
}

#--- 主程序 ---
main() {
    # 初始化
    mkdir -p "$(dirname "$LOG_FILE")" "$TEMP_DIR" 2>/dev/null || true
    : > "$LOG_FILE"
    TOTAL_START_TIME=$(date +%s)
    
    clear
    print_line
    echo "Debian 系统定制部署脚本"
    print_line
    
    # 准备阶段
    check_system
    check_network
    install_dependencies
    
    # 选择模块
    select_modules
    
    echo
    log "最终执行计划: ${SELECTED_MODULES[*]}"
    read -p "确认并开始执行? [Y/n]: " -r choice
    [[ "${choice:-Y}" =~ ^[Yy]$ ]] || { log "用户取消操作，退出。" "warn"; exit 0; }
    
    # 执行阶段
    print_line
    log "开始执行 ${#SELECTED_MODULES[@]} 个模块..."
    print_line
    
    for module in "${SELECTED_MODULES[@]}"; do
        echo
        if download_module "$module"; then
            execute_module "$module"
        else
            FAILED_MODULES+=("$module")
        fi
    done
    
    # 完成阶段
    generate_summary
    
    echo
    log "所有任务已完成！" "success"
    echo "如果安装了内核优化模块，建议重启系统以确保所有配置完全生效: reboot"
}

# 执行主程序
main "$@"
