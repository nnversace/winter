#!/bin/bash

#=============================================================================
# Debian 系统部署脚本 v3.5.0 (优化版)
# 适用系统: Debian 12+, 作者: LucaLin233
# 功能: 模块化部署，智能依赖处理
# 优化点: 默认全量安装，支持自定义SSH端口
#=============================================================================

set -euo pipefail

#--- 全局常量 ---
readonly SCRIPT_VERSION="3.5.0"
readonly MODULE_BASE_URL="https://raw.githubusercontent.com/nnversace/winter/refs/heads/main/modules"
readonly TEMP_DIR="/tmp/debian-setup-modules"
readonly LOG_FILE="/var/log/debian-setup.log"
readonly SUMMARY_FILE="/root/deployment_summary.txt"

#--- 模块定义 ---
declare -A MODULES=(
    ["system-optimize"]="系统优化 (Zram, 时区, 时间同步)"
    ["docker-setup"]="Docker 容器化平台"
    ["tools-setup"]="系统工具 (NextTrace, SpeedTest等)"
    ["ssh-security"]="SSH 安全配置"
    ["auto-update-setup"]="自动更新系统"
)
# 模块执行顺序
readonly ORDERED_MODULE_KEYS=("system-optimize" "docker-setup" "tools-setup" "ssh-security" "auto-update-setup")

#--- 执行状态 ---
EXECUTED_MODULES=()
FAILED_MODULES=()
SKIPPED_MODULES=()
SELECTED_MODULES=()
declare -A MODULE_EXEC_TIME=()
TOTAL_START_TIME=0
CUSTOM_SSH_PORT="" # 用于存储自定义SSH端口

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

#--- 日志函数 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "info")     echo -e "${GREEN}✅ $msg${NC}" ;;
        "warn")     echo -e "${YELLOW}⚠️  $msg${NC}" ;;
        "error")    echo -e "${RED}❌ $msg${NC}" ;;
        "success")  echo -e "${GREEN}🎉 $msg${NC}" ;;
    esac
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

#--- 分隔线 ---
print_line() {
    echo "============================================================"
}

#--- 错误处理 ---
cleanup() {
    local exit_code=$?
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    if (( exit_code != 0 )); then
        log "脚本异常退出，日志: $LOG_FILE" "error"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

#--- 基础检查 ---
check_system() {
    log "系统预检查"
    if (( EUID != 0 )); then
        log "需要 root 权限运行" "error"; exit 1
    fi
    if [[ ! -f /etc/debian_version ]]; then
        log "仅支持 Debian 系统" "error"; exit 1
    fi
    log "系统检查通过"
}

#--- 网络检查 ---
check_network() {
    log "检查网络连接..."
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log "网络连接异常，可能影响模块下载" "warn"
        read -p "继续执行? [y/N]: " -r choice
        [[ "$choice" =~ ^[Yy]$ ]] || exit 0
    fi
    log "网络连接正常"
}

#--- 安装基础依赖 ---
install_dependencies() {
    log "检查并安装系统依赖"
    local required_deps=("curl" "wget" "git" "jq" "rsync" "sudo" "dnsutils")
    local missing_packages=()
    
    for pkg in "${required_deps[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing_packages+=("$pkg")
        fi
    done
    
    if (( ${#missing_packages[@]} > 0 )); then
        log "安装缺失依赖: ${missing_packages[*]}"
        apt-get update -qq || log "软件包列表更新失败" "warn"
        apt-get install -y "${missing_packages[@]}" || {
            log "依赖安装失败" "error"; exit 1
        }
    fi
    log "依赖检查完成"
}

#--- 系统更新 ---
system_update() {
    log "系统更新"
    apt-get update -qq && apt-get upgrade -y -qq || log "系统更新或升级失败" "warn"
    log "系统更新完成"
}

#--- [优化] 获取自定义SSH端口 ---
get_custom_ssh_port() {
    echo
    print_line
    log "SSH 端口配置"
    while true; do
        read -p "请输入新的 SSH 端口 (1024-65535, 推荐20000以上, 留空则不修改): " -r port_input
        if [[ -z "$port_input" ]]; then
            CUSTOM_SSH_PORT=""
            log "用户跳过 SSH 端口自定义。" "warn"
            break
        elif [[ "$port_input" =~ ^[0-9]+$ ]] && (( port_input >= 1024 && port_input <= 65535 )); then
            CUSTOM_SSH_PORT="$port_input"
            log "SSH 端口将设置为: $CUSTOM_SSH_PORT"
            break
        else
            log "无效输入。请输入 1024 到 65535 之间的数字。" "error"
        fi
    done
}


#--- 下载模块 ---
download_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    local download_url="${MODULE_BASE_URL}/${module}.sh"
    
    log "获取模块 $module"
    
    if curl -fsSL --connect-timeout 10 "$download_url" -o "$module_file" 2>/dev/null; then
        if [[ -s "$module_file" ]] && head -1 "$module_file" | grep -q "#!/bin/bash"; then
            chmod +x "$module_file"
            return 0
        fi
    fi
    
    log "模块 $module 下载失败" "error"
    return 1
}

#--- [优化] 执行模块 (支持传递参数) ---
execute_module() {
    local module="$1"
    local module_file="$TEMP_DIR/${module}.sh"
    
    if [[ ! -f "$module_file" ]]; then
        log "模块文件不存在: $module" "error"
        FAILED_MODULES+=("$module")
        return 1
    fi
    
    log "执行模块: ${MODULES[$module]}"
    
    local start_time=$(date +%s)
    local exec_result=0
    
    # 根据模块传递不同参数
    # 假设:
    # - ssh-security.sh 接受端口号作为第一个参数
    # - tools-setup.sh 接受 --install-all 参数以自动安装所有工具
    if [[ "$module" == "ssh-security" ]] && [[ -n "$CUSTOM_SSH_PORT" ]]; then
        log "传递自定义端口 $CUSTOM_SSH_PORT 到 ssh-security 模块"
        bash "$module_file" "$CUSTOM_SSH_PORT" || exec_result=$?
    elif [[ "$module" == "tools-setup" ]]; then
        log "传递 --install-all 参数到 tools-setup 模块"
        bash "$module_file" --install-all || exec_result=$?
    else
        bash "$module_file" || exec_result=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    MODULE_EXEC_TIME[$module]=$duration
    
    if (( exec_result == 0 )); then
        EXECUTED_MODULES+=("$module")
        log "模块 $module 执行成功 (${duration}s)" "success"
        return 0
    else
        FAILED_MODULES+=("$module")
        log "模块 $module 执行失败 (${duration}s)" "error"
        return 1
    fi
}

#--- 系统状态获取 ---
get_system_status() {
    # (此函数未修改，保持原样)
    local status_lines=()
    local cpu_cores=$(nproc 2>/dev/null || echo "未知")
    local mem_info=$(free -h 2>/dev/null | grep Mem | awk '{print $3"/"$2}' || echo "未知")
    local disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "未知")
    status_lines+=("💻 CPU: ${cpu_cores}核心 | 内存: $mem_info | 磁盘: $disk_usage")
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "未知")
        status_lines+=("🐳 Docker: v$docker_version (运行中)")
    else
        status_lines+=("🐳 Docker: 未安装")
    fi
    local ssh_port=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    status_lines+=("🔒 SSH Port: $ssh_port")
    printf '%s\n' "${status_lines[@]}"
}

#--- 生成摘要 ---
generate_summary() {
    # (此函数未修改，保持原样)
    log "生成部署摘要"
    local total_modules=${#ORDERED_MODULE_KEYS[@]}
    local success_rate=0
    if (( total_modules > 0 )); then
        success_rate=$(( ${#EXECUTED_MODULES[@]} * 100 / total_modules ))
    fi
    local total_time=$(( $(date +%s) - TOTAL_START_TIME ))
    
    local summary
    summary=$(cat <<-EOF
===============================================
Debian 系统部署摘要
===============================================
脚本版本: $SCRIPT_VERSION
部署时间: $(date '+%Y-%m-%d %H:%M:%S %Z')
总耗时: ${total_time}秒
主机: $(hostname)
IP地址: $(hostname -I | awk '{print $1}')

执行统计:
总模块: $total_modules, 成功: ${#EXECUTED_MODULES[@]}, 失败: ${#FAILED_MODULES[@]}, 成功率: ${success_rate}%

成功模块:
$(for module in "${EXECUTED_MODULES[@]}"; do echo "  - $module (${MODULE_EXEC_TIME[$module]}s)"; done)

失败模块:
$(for module in "${FAILED_MODULES[@]}"; do echo "  - $module"; done)

当前系统状态:
$(get_system_status | sed 's/^/  /')

文件位置:
  日志: $LOG_FILE
  摘要: $SUMMARY_FILE
===============================================
EOF
)
    echo "$summary" | tee "$SUMMARY_FILE"
    echo
    log "详细摘要已保存至: $SUMMARY_FILE" "info"
}

#--- 主程序 ---
main() {
    # 初始化
    mkdir -p "$(dirname "$LOG_FILE")" "$TEMP_DIR" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || true
    TOTAL_START_TIME=$(date +%s)
    
    # 启动
    clear 2>/dev/null || true
    print_line
    echo "Debian 系统部署脚本 v$SCRIPT_VERSION (全自动优化版)"
    print_line
    
    # 检查和准备
    check_system
    check_network
    install_dependencies
    system_update
    
    # [优化] 获取自定义SSH端口
    get_custom_ssh_port
    
    # [优化] 默认安装所有模块
    SELECTED_MODULES=("${ORDERED_MODULE_KEYS[@]}")
    log "默认模式: 将安装所有 ${#SELECTED_MODULES[@]} 个模块。"
    log "执行计划: ${SELECTED_MODULES[*]}"
    log "3秒后自动开始执行..."
    sleep 3
    
    # 执行模块
    echo
    print_line
    log "开始执行模块"
    print_line
    
    for module in "${SELECTED_MODULES[@]}"; do
        echo
        if download_module "$module"; then
            execute_module "$module"
        else
            FAILED_MODULES+=("$module")
        fi
    done
    
    # 完成
    generate_summary

    # SSH安全提醒
    if [[ " ${EXECUTED_MODULES[*]} " =~ " ssh-security " ]] && [[ -n "$CUSTOM_SSH_PORT" ]]; then
        echo
        log "重要提醒: SSH端口已更改为 $CUSTOM_SSH_PORT" "warn"
        log "请使用新端口重新连接: ssh user@$(hostname -I | awk '{print $1}') -p $CUSTOM_SSH_PORT" "warn"
    fi
}

# 执行主程序
main "$@"
