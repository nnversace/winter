#!/bin/bash
# -----------------------------------------------------------------------------
# 适用系统: Debian 12+
# 功能: 模块化部署 Mise, Docker, 网络优化, SSH 加固等
# 版本: 2.2.0 (移除Zsh美化，优化性能)
# -----------------------------------------------------------------------------

set -e # 发生错误时立即退出
set -o pipefail # 管道命令失败时退出

# --- 全局变量和常量 ---
readonly SCRIPT_VERSION="2.2.0"
readonly STATUS_FILE="/var/lib/system-deploy-status.json"
readonly MODULE_BASE_URL="https://raw.githubusercontent.com/LucaLin233/Luca_Conf/refs/heads/main/Other/modules"
readonly TEMP_DIR="/tmp/debian_setup_modules"
readonly LOG_FILE="/var/log/debian-deploy.log"

RERUN_MODE=false
INTERACTIVE_MODE=true
declare -A MODULES_TO_RUN

# --- 日志函数 ---
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$message"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

step_start() { 
    log "▶ $1..."
}

step_end() { 
    log "✓ $1 完成\n"
}

step_fail() { 
    log "✗ $1 失败"
    exit 1
}

# --- 系统检查函数 ---
check_system_requirements() {
    # 权限检查
    if [ "$(id -u)" != "0" ]; then
        step_fail "此脚本必须以 root 用户身份运行"
    fi

    # 系统检查
    if [ ! -f /etc/debian_version ]; then
        step_fail "此脚本仅适用于 Debian 系统"
    fi

    # 版本检查
    local debian_version=$(cut -d. -f1 < /etc/debian_version 2>/dev/null || echo "0")
    if [ "$debian_version" -lt 12 ]; then
        log "警告: 此脚本为 Debian 12+ 优化。当前版本: $(cat /etc/debian_version)"
        if $INTERACTIVE_MODE; then
            read -p "确定继续? [y/N]: " continue_install
            [[ "$continue_install" != [Yy] ]] && exit 1
        fi
    fi
}

check_network_connectivity() {
    log "正在检查网络连接..."
    local test_urls=("https://cp.cloudflare.com" "https://www.google.com" "https://github.com")
    local connected=false
    
    for url in "${test_urls[@]}"; do
        if curl -fsSL --connect-timeout 5 --max-time 10 "$url" > /dev/null 2>&1; then
            connected=true
            break
        fi
    done
    
    if ! $connected; then
        log "警告: 网络连接不稳定或无法访问外部网络"
        if $INTERACTIVE_MODE; then
            read -p "继续执行? [y/N]: " continue_install
            [[ "$continue_install" != [Yy] ]] && exit 1
        fi
    else
        log "网络连接正常"
    fi
}

# --- 模块管理函数 ---
download_module() {
    local module_name="$1"
    local module_file="$TEMP_DIR/${module_name}.sh"
    local max_retries=3
    local retry_count=0
    
    log "  正在下载模块: $module_name"
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -fsSL --connect-timeout 10 --max-time 30 "$MODULE_BASE_URL/${module_name}.sh" -o "$module_file"; then
            chmod +x "$module_file"
            log "  模块 $module_name 下载成功"
            return 0
        else
            ((retry_count++))
            log "  模块 $module_name 下载失败，重试 $retry_count/$max_retries"
            sleep 2
        fi
    done
    
    log "  模块 $module_name 下载失败，已达到最大重试次数"
    return 1
}

execute_module() {
    local module_name="$1"
    local module_file="$TEMP_DIR/${module_name}.sh"
    
    if [ ! -f "$module_file" ]; then
        log "  模块文件不存在: $module_file"
        return 1
    fi

    log "  正在执行模块: $module_name"
    if timeout 300 bash "$module_file" 2>&1 | tee -a "$LOG_FILE"; then
        log "  模块 $module_name 执行成功"
        return 0
    else
        log "  模块 $module_name 执行失败"
        return 1
    fi
}

# --- 状态管理函数 ---
was_module_executed_successfully() {
    local module_name="$1"
    [ ! -f "$STATUS_FILE" ] && return 1
    
    if command -v jq &>/dev/null; then
        jq -e --arg mod "$module_name" '.executed_modules | index($mod) != null' "$STATUS_FILE" &>/dev/null
    else
        grep -q "\"$module_name\"" "$STATUS_FILE" 2>/dev/null
    fi
}

ask_user_for_module() {
    local module_name="$1"
    local description="$2"
    local choice
    local prompt_msg="? 是否执行 $description 模块?"

    # 如果指定了特定模块，直接返回结果
    if [ ${#MODULES_TO_RUN[@]} -gt 0 ]; then
        [[ -n "${MODULES_TO_RUN[$module_name]}" ]] && return 0 || return 1
    fi

    # 非交互模式直接返回成功
    if ! $INTERACTIVE_MODE; then 
        return 0
    fi

    # 交互模式，根据历史记录调整默认值
    if $RERUN_MODE && was_module_executed_successfully "$module_name"; then
        read -p "$prompt_msg (已执行过，建议选 n) [y/N]: " choice
        choice="${choice:-N}"
    else
        read -p "$prompt_msg [Y/n]: " choice
        choice="${choice:-Y}"
    fi

    [[ "$choice" =~ ^[Yy]$ ]]
}

# --- 系统更新函数 ---
update_system() {
    step_start "系统更新"
    
    # 更新包列表
    if ! apt-get update -qq 2>/dev/null; then
        log "警告: 包列表更新失败，尝试修复..."
        apt-get clean
        apt-get update
    fi
    
    # 根据运行模式选择更新策略
    if $RERUN_MODE; then
        log "更新模式: 执行安全更新"
        apt-get upgrade -y -qq
    else
        log "首次运行: 执行完整系统升级"
        DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    fi
    
    # 清理系统
    apt-get autoremove -y -qq
    apt-get autoclean -qq
    
    step_end "系统更新"
}

install_essential_packages() {
    step_start "安装基础工具"
    
    # 基础工具包
    local essential_packages=(
        "curl" "wget" "git" "jq" "htop" "vim" "nano"
        "dnsutils" "rsync" "chrony" "cron" "tuned"
        "apt-transport-https" "ca-certificates" "gnupg"
        "software-properties-common" "unattended-upgrades"
        "fail2ban" "ufw" "logrotate"
    )
    
    local missing_packages=()
    
    # 检查缺失的包
    for pkg in "${essential_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing_packages+=("$pkg")
        fi
    done
    
    # 安装缺失的包
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log "安装缺失的软件包: ${missing_packages[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}"
    else
        log "所有基础工具已安装"
    fi
    
    step_end "安装基础工具"
}

fix_system_configuration() {
    step_start "修复系统配置"
    
    # 修复 hosts 文件
    local hostname=$(hostname)
    if ! grep -q "^127.0.1.1.*$hostname" /etc/hosts; then
        log "修复 hosts 文件..."
        sed -i "/^127.0.1.1/d" /etc/hosts
        echo "127.0.1.1 $hostname" >> /etc/hosts
    fi
    
    # 确保时间同步
    if command -v chrony &>/dev/null; then
        systemctl enable chronyd --quiet 2>/dev/null || true
        systemctl restart chronyd --quiet 2>/dev/null || true
    fi
    
    # 启用基础服务
    systemctl enable cron --quiet 2>/dev/null || true
    systemctl enable fail2ban --quiet 2>/dev/null || true
    
    step_end "修复系统配置"
}

# --- 部署摘要函数 ---
generate_deployment_summary() {
    local executed_modules=("$@")
    local failed_modules=()
    
    # 获取失败模块（这里需要从全局变量获取）
    if [ -n "${FAILED_MODULES:-}" ]; then
        IFS=' ' read -ra failed_modules <<< "$FAILED_MODULES"
    fi
    
    log "\n╔═════════════════════════════════════════╗"
    log "║           系统部署完成摘要                ║"
    log "╚═════════════════════════════════════════╝"
    
    local show_info() { log " • $1: $2"; }
    
    show_info "脚本版本" "$SCRIPT_VERSION"
    show_info "部署模式" "$(if $RERUN_MODE; then echo "更新模式"; else echo "首次部署"; fi)"
    show_info "操作系统" "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo 'Debian')"
    show_info "内核版本" "$(uname -r)"
    show_info "部署时间" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    
    if [ ${#executed_modules[@]} -gt 0 ]; then
        log "\n✅ 成功执行的模块:"
        printf "   • %s\n" "${executed_modules[@]}"
    fi
    
    if [ ${#failed_modules[@]} -gt 0 ]; then
        log "\n❌ 执行失败的模块:"
        printf "   • %s\n" "${failed_modules[@]}"
    fi
    
    log "\n📊 当前系统状态:"
    
    # Docker 状态
    if command -v docker &>/dev/null; then
        show_info "Docker" "已安装 ($(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1))"
    else
        show_info "Docker" "未安装"
    fi
    
    # SSH 状态
    local ssh_port=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    show_info "SSH 端口" "$ssh_port"
    
    # 网络状态
    local tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    show_info "TCP 拥塞控制" "$tcp_cc"
    
    # 防火墙状态
    local ufw_status=$(ufw status 2>/dev/null | head -1 | cut -d' ' -f2 || echo "未知")
    show_info "UFW 防火墙" "$ufw_status"
    
    log "\n📄 日志文件: $LOG_FILE"
    log "📄 状态文件: $STATUS_FILE"
    log "──────────────────────────────────────────────────\n"
}

# --- 状态保存函数 ---
save_deployment_status() {
    local executed_modules=("$@")
    
    step_start "保存部署状态"
    
    local ssh_port=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    
    if command -v jq &>/dev/null; then
        jq -n \
          --arg version "$SCRIPT_VERSION" \
          --arg last_run "$(date '+%Y-%m-%d %H:%M:%S')" \
          --argjson executed "$(printf '%s\n' "${executed_modules[@]}" | jq -R . | jq -s .)" \
          --argjson failed "$(printf '%s\n' "${FAILED_MODULES[@]}" 2>/dev/null | jq -R . | jq -s . || echo '[]')" \
          --arg os "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo 'Debian')" \
          --arg kernel "$(uname -r)" \
          --arg ssh_port "$ssh_port" \
          '{
             "script_version": $version,
             "last_run": $last_run,
             "executed_modules": $executed,
             "failed_modules": $failed,
             "system_info": {
               "os": $os,
               "kernel": $kernel,
               "ssh_port": $ssh_port
             }
           }' > "$STATUS_FILE"
    else
        log "警告: jq 未安装，使用简化状态保存"
        cat > "$STATUS_FILE" << EOF
{
  "script_version": "$SCRIPT_VERSION",
  "last_run": "$(date '+%Y-%m-%d %H:%M:%S')",
  "executed_modules": ["$(IFS='","'; echo "${executed_modules[*]}")"],
  "system_info": {
    "os": "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo 'Debian')",
    "kernel": "$(uname -r)",
    "ssh_port": "$ssh_port"
  }
}
EOF
    fi
    
    step_end "保存部署状态"
}

# --- 主函数 ---
main() {
    # 创建日志文件
    touch "$LOG_FILE"
    log "开始执行 Debian 部署脚本 v$SCRIPT_VERSION"
    
    # --- 解析命令行参数 ---
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -y|--yes) 
                INTERACTIVE_MODE=false
                shift 
                ;;
            -m|--module)
                if [[ -n "$2" && "$2" != -* ]]; then
                    MODULES_TO_RUN["$2"]=1
                    shift 2
                else
                    log "错误: --module 参数需要一个模块名"
                    exit 1
                fi
                ;;
            -h|--help)
                cat << EOF
用法: $0 [选项]

选项:
  -y, --yes          非交互模式，自动确认所有操作
  -m, --module NAME  仅执行指定模块
  -h, --help         显示此帮助信息

可用模块:
  system-optimize    系统优化 (Zram, 时区, 服务管理)
  mise-setup         Mise 版本管理器 (Python 环境)
  docker-setup       Docker 容器化平台
  network-optimize   网络性能优化 (BBR + fq_codel)
  ssh-security       SSH 安全配置
  auto-update-setup  自动更新系统

示例:
  $0                        # 交互式运行所有模块
  $0 -y                     # 非交互式运行所有模块
  $0 -m docker-setup        # 仅运行 Docker 安装模块
  $0 -y -m ssh-security     # 非交互式运行 SSH 安全配置
EOF
                exit 0
                ;;
            *) 
                log "未知参数: $1"
                log "使用 $0 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # --- 步骤 1: 基础环境检查 ---
    step_start "步骤 1: 基础环境检查和准备"
    
    check_system_requirements
    
    # 检查重新运行模式
    if [ -f "$STATUS_FILE" ]; then
        RERUN_MODE=true
        log "检测到之前的部署记录，以更新模式执行"
    fi
    
    check_network_connectivity
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    step_end "步骤 1: 基础环境检查和准备"
    
    # --- 步骤 2: 系统更新和基础配置 ---
    update_system
    install_essential_packages
    fix_system_configuration
    
    # --- 步骤 3: 模块化部署 ---
    step_start "步骤 3: 模块化功能部署"
    
    # 定义可用模块（移除了 zsh-setup）
    declare -A MODULES=(
        ["system-optimize"]="系统优化 (Zram, 时区, 服务管理)"
        ["mise-setup"]="Mise 版本管理器 (Python 环境)"
        ["docker-setup"]="Docker 容器化平台"
        ["network-optimize"]="网络性能优化 (BBR + fq_codel)"
        ["ssh-security"]="SSH 安全配置"
        ["auto-update-setup"]="自动更新系统"
    )
    
    # 模块执行顺序
    local module_order=("system-optimize" "mise-setup" "docker-setup" "network-optimize" "ssh-security" "auto-update-setup")
    
    local executed_modules=()
    FAILED_MODULES=()
    
    for module in "${module_order[@]}"; do
        local description="${MODULES[$module]}"
        
        if ask_user_for_module "$module" "$description"; then
            log "\n处理模块: $module"
            if download_module "$module"; then
                if execute_module "$module"; then
                    executed_modules+=("$module")
                else
                    FAILED_MODULES+=("$module")
                fi
            else
                FAILED_MODULES+=("$module")
            fi
        else
            log "跳过模块: $module"
        fi
    done
    
    step_end "步骤 3: 模块化功能部署"
    
    # --- 步骤 4: 部署摘要 ---
    generate_deployment_summary "${executed_modules[@]}"
    
    # --- 步骤 5: 保存部署状态 ---
    save_deployment_status "${executed_modules[@]}"
    
    # --- 清理和最终提示 ---
    rm -rf "$TEMP_DIR"
    
    log "✅ 所有部署任务完成!"
    
    # 特殊提示
    if [[ " ${executed_modules[*]} " =~ " ssh-security " ]]; then
        local ssh_port=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        if [ "$ssh_port" != "22" ]; then
            log "⚠️  重要: SSH 端口已更改为 $ssh_port"
            log "   请使用新端口连接: ssh -p $ssh_port user@server"
        fi
    fi
    
    if [[ " ${executed_modules[*]} " =~ " docker-setup " ]]; then
        log "🐳 Docker 提示: 请重新登录以使用户加入 docker 组生效"
    fi
    
    log "🔄 可随时重新运行此脚本进行更新或维护"
    log "📋 详细日志请查看: $LOG_FILE"
}

# --- 信号处理 ---
cleanup() {
    log "脚本被中断，正在清理..."
    rm -rf "$TEMP_DIR"
    exit 1
}

trap cleanup INT TERM

# --- 脚本入口 ---
main "$@"
exit 0
