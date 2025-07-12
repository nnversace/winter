#!/bin/bash
# -----------------------------------------------------------------------------
# 适用系统: Debian 12+
# 功能: 模块化部署 Node.js, Claude Code, Mise, Docker, 网络优化, SSH 加固等
# -----------------------------------------------------------------------------

set -e # 发生错误时立即退出

# --- 全局变量和常量 ---
SCRIPT_VERSION="2.1.0"
STATUS_FILE="/var/lib/system-deploy-status.json"
MODULE_BASE_URL="https://raw.githubusercontent.com/LucaLin233/Luca_Conf/refs/heads/main/Other/modules"
TEMP_DIR="/tmp/debian_setup_modules"
RERUN_MODE=false
INTERACTIVE_MODE=true
declare -A MODULES_TO_RUN

# --- 基础函数 ---
log() {
    # 移除了颜色代码，只进行标准输出
    echo -e "$1"
}

step_start() { log "▶ $1..."; }
step_end() { log "✓ $1 完成\n"; }
step_fail() { log "✗ $1 失败"; exit 1; }

# --- 模块管理函数 ---
download_module() {
    local module_name="$1"
    local module_file="$TEMP_DIR/${module_name}.sh"
    log "  Downloading module: $module_name"
    if curl -fsSL "$MODULE_BASE_URL/${module_name}.sh" -o "$module_file"; then
        chmod +x "$module_file"
        log "  Module $module_name downloaded successfully."
        return 0
    else
        log "  Module $module_name download failed."
        return 1
    fi
}

execute_module() {
    local module_name="$1"
    local module_file="$TEMP_DIR/${module_name}.sh"
    [ ! -f "$module_file" ] && { log "  Module file not found: $module_file"; return 1; }

    log "  Executing module: $module_name"
    if bash "$module_file"; then
        log "  Module $module_name executed successfully."
        return 0
    else
        log "  Module $module_name execution failed."
        return 1
    fi
}

# --- Node.js 和 Claude Code 安装函数 ---
install_nodejs_claude() {
    log "  Installing Node.js LTS..."
    
    # 添加 NodeSource 官方源
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    
    # 安装 Node.js
    apt-get install -y nodejs
    
    # 验证安装
    local node_version=$(node --version)
    log "  Node.js installed: $node_version"
    
    # 安装 Claude Code
    log "  Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    
    # 验证 Claude Code 安装
    local claude_version=$(claude --version)
    log "  Claude Code installed: $claude_version"
    
    return 0
}

# --- 状态与交互函数 ---
was_module_executed_successfully() {
    local module_name="$1"
    if [ ! -f "$STATUS_FILE" ]; then return 1; fi
    # 使用 jq 安全地检查模块是否在 executed_modules 数组中
    if command -v jq &>/dev/null; then
        jq -e --arg mod "$module_name" '.executed_modules | index($mod) != null' "$STATUS_FILE" &>/dev/null
    else
        # 降级方案: 使用 grep
        grep '"executed_modules"' "$STATUS_FILE" | grep -q "\"$module_name\""
    fi
}

ask_user_for_module() {
    local module_name="$1"
    local description="$2"
    local choice
    local prompt_msg="? 是否执行 $description 模块?"

    # 如果指定了特定模块，则直接返回成功
    if [ ${#MODULES_TO_RUN[@]} -gt 0 ]; then
        [[ -n "${MODULES_TO_RUN[$module_name]}" ]] && return 0 || return 1
    fi

    # 非交互模式直接返回成功
    if ! $INTERACTIVE_MODE; then return 0; fi

    # 交互模式下，根据历史记录调整默认值
    if $RERUN_MODE && was_module_executed_successfully "$module_name"; then
        read -p "$prompt_msg (已执行过，建议选 n) [y/N]: " choice
        choice="${choice:-N}"
    else
        read -p "$prompt_msg [Y/n]: " choice
        choice="${choice:-Y}"
    fi

    [[ "$choice" =~ ^[Yy]$ ]]
}

# --- 主要逻辑 ---
main() {
    # --- 步骤 0: 解析命令行参数 ---
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -y|--yes) INTERACTIVE_MODE=false; shift ;;
            -m|--module)
                if [[ -n "$2" && "$2" != -* ]]; then
                    MODULES_TO_RUN["$2"]=1
                    shift 2
                else
                    log "错误: --module 参数需要一个模块名"; exit 1
                fi
                ;;
            *) log "未知参数: $1"; exit 1 ;;
        esac
    done

    # --- 步骤 1: 基础环境检查 ---
    step_start "步骤 1: 基础环境检查和准备"

    # 权限和系统检查
    [ "$(id -u)" != "0" ] && step_fail "此脚本必须以 root 用户身份运行"
    [ ! -f /etc/debian_version ] && step_fail "此脚本仅适用于 Debian 系统"

    debian_version=$(cut -d. -f1 < /etc/debian_version)
    if [ "$debian_version" -lt 12 ]; then
        log "警告: 此脚本为 Debian 12+ 优化。当前版本: $(cat /etc/debian_version)"
        if $INTERACTIVE_MODE; then
            read -p "确定继续? (y/n): " continue_install
            [[ "$continue_install" != "y" ]] && exit 1
        fi
    fi

    [ -f "$STATUS_FILE" ] && RERUN_MODE=true && log "检测到之前的部署记录，以更新模式执行。"

    # 网络检查
    log "正在检查网络连接..."
    if ! curl -fsSL --connect-timeout 5 https://cp.cloudflare.com > /dev/null; then
        log "警告: 网络连接不稳定或无法访问外部网络。"
        if $INTERACTIVE_MODE; then
            read -p "继续执行? (y/n): " continue_install
            [[ "$continue_install" != "y" ]] && exit 1
        fi
    fi
    log "网络连接正常。"

    # 安装基础工具
    log "正在检查和安装基础工具..."
    apt-get update -qq
    for cmd in curl wget apt git jq; do
        if ! command -v $cmd &>/dev/null; then
            log "安装基础工具: $cmd"
            apt-get install -y -qq $cmd || step_fail "安装 $cmd 失败"
        fi
    done

    mkdir -p "$TEMP_DIR"
    step_end "步骤 1"

    # --- 步骤 2: 系统更新 ---
    step_start "步骤 2: 系统更新"

    apt-get update
    if $RERUN_MODE; then
        log "更新模式: 执行软件包升级 (apt upgrade)"
        apt-get upgrade -y
    else
        log "首次运行: 执行完整系统升级 (apt full-upgrade)"
        apt-get full-upgrade -y
    fi
    apt-get autoremove -y && apt-get autoclean -y

    # 安装核心软件包
    CORE_PACKAGES=(dnsutils rsync chrony cron tuned)
    MISSING_PACKAGES=()
    for pkg in "${CORE_PACKAGES[@]}"; do
        ! dpkg -s "$pkg" &>/dev/null && MISSING_PACKAGES+=("$pkg")
    done

    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        log "安装核心软件包: ${MISSING_PACKAGES[*]}"
        apt-get install -y "${MISSING_PACKAGES[@]}" || step_fail "核心软件包安装失败"
    fi

    # 修复 hosts 文件
    HOSTNAME=$(hostname)
    if ! grep -q "^127.0.1.1.*$HOSTNAME" /etc/hosts; then
        log "修复 hosts 文件..."
        sed -i "/^127.0.1.1/d" /etc/hosts
        echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    fi
    step_end "步骤 2"

    # --- 步骤 3: 模块化部署 ---
    step_start "步骤 3: 模块化功能部署"

    declare -A MODULES=(
        ["system-optimize"]="系统优化 (Zram, 时区, 服务管理)"
        ["nodejs-claude"]="Node.js 和 Claude Code 安装"
        ["mise-setup"]="Mise 版本管理器 (Python 环境)"
        ["docker-setup"]="Docker 容器化平台"
        ["network-optimize"]="网络性能优化 (BBR + fq_codel)"
        ["ssh-security"]="SSH 安全配置"
        ["auto-update-setup"]="自动更新系统"
    )
    MODULE_ORDER=("system-optimize" "nodejs-claude" "mise-setup" "docker-setup" "network-optimize" "ssh-security" "auto-update-setup")

    EXECUTED_MODULES=()
    FAILED_MODULES=()

    for module in "${MODULE_ORDER[@]}"; do
        description="${MODULES[$module]}"

        if ask_user_for_module "$module" "$description"; then
            log "\n处理模块: $module"
            
            # 特殊处理 nodejs-claude 模块
            if [ "$module" = "nodejs-claude" ]; then
                if install_nodejs_claude; then
                    EXECUTED_MODULES+=("$module")
                else
                    FAILED_MODULES+=("$module")
                fi
            else
                # 处理其他模块
                if download_module "$module"; then
                    if execute_module "$module"; then
                        EXECUTED_MODULES+=("$module")
                    else
                        FAILED_MODULES+=("$module")
                    fi
                else
                    FAILED_MODULES+=("$module")
                fi
            fi
        else
            log "跳过模块: $module"
        fi
    done
    step_end "步骤 3"

    # --- 步骤 4: 部署摘要 ---
    step_start "步骤 4: 生成部署摘要"

    log "\n╔═════════════════════════════════════════╗"
    log "║           系统部署完成摘要                ║"
    log "╚═════════════════════════════════════════╝"

    show_info() { log " • $1: $2"; }

    show_info "脚本版本" "$SCRIPT_VERSION"
    show_info "部署模式" "$(if $RERUN_MODE; then echo "更新模式"; else echo "首次部署"; fi)"
    show_info "操作系统" "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo 'Debian')"
    show_info "内核版本" "$(uname -r)"

    if [ ${#EXECUTED_MODULES[@]} -gt 0 ]; then
        log "\n✅ 成功执行的模块:"
        printf "   • %s\n" "${EXECUTED_MODULES[@]}"
    fi

    if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
        log "\n❌ 执行失败的模块:"
        printf "   • %s\n" "${FAILED_MODULES[@]}"
    fi

    log "\n📊 当前系统状态:"
    if command -v node &>/dev/null; then show_info "Node.js" "已安装 ($(node --version 2>/dev/null))"; else show_info "Node.js" "未安装"; fi
    if command -v claude &>/dev/null; then show_info "Claude Code" "已安装 ($(claude --version 2>/dev/null))"; else show_info "Claude Code" "未安装"; fi
    if command -v docker &>/dev/null; then show_info "Docker" "已安装 ($(docker --version 2>/dev/null))"; else show_info "Docker" "未安装"; fi
    SSH_PORT=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    show_info "SSH 端口" "$SSH_PORT"
    CURR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    show_info "网络拥塞控制" "$CURR_CC"

    log "\n──────────────────────────────────────────────────"
    log " 部署完成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log "──────────────────────────────────────────────────\n"

    step_end "步骤 4"

    # --- 步骤 5: 保存部署状态 ---
    step_start "步骤 5: 保存部署状态"

    if command -v jq &>/dev/null; then
        jq -n \
          --arg version "$SCRIPT_VERSION" \
          --arg last_run "$(date '+%Y-%m-%d %H:%M:%S')" \
          --argjson executed "$(jq -n '$ARGS.positional' --args "${EXECUTED_MODULES[@]}")" \
          --argjson failed "$(jq -n '$ARGS.positional' --args "${FAILED_MODULES[@]}")" \
          --arg os "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')" \
          --arg kernel "$(uname -r)" \
          --arg ssh_port "$SSH_PORT" \
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
        log "警告: 'jq' 命令未找到，使用原生方式生成状态文件，可能不稳定。"
        # Fallback to the original method
        executed_json=$(printf '"%s",' "${EXECUTED_MODULES[@]}" | sed 's/,$//')
        failed_json=$(printf '"%s",' "${FAILED_MODULES[@]}" | sed 's/,$//')
        cat > "$STATUS_FILE" << EOF
{
  "script_version": "$SCRIPT_VERSION",
  "last_run": "$(date '+%Y-%m-%d %H:%M:%S')",
  "executed_modules": [${executed_json}],
  "failed_modules": [${failed_json}],
  "system_info": {
    "os": "$(grep 'PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"')",
    "kernel": "$(uname -r)",
    "ssh_port": "$SSH_PORT"
  }
}
EOF
    fi
    step_end "步骤 5"

    # --- 清理和最终提示 ---
    rm -rf "$TEMP_DIR"
    log "✅ 所有部署任务完成!"

    if [[ " ${EXECUTED_MODULES[@]} " =~ " ssh-security " ]]; then
        if [ "$SSH_PORT" != "22" ] && [ -n "$SSH_PORT" ]; then
            log "⚠️  重要: SSH 端口已更改为 $SSH_PORT"
            log "   请使用新端口连接: ssh -p $SSH_PORT user@server"
        fi
    fi
    if [[ " ${EXECUTED_MODULES[@]} " =~ " nodejs-claude " ]]; then
        log "🔧 Node.js 和 Claude Code 使用提示:"
        log "   • 检查 Node.js 版本: node --version"
        log "   • 检查 Claude Code 版本: claude --version"
        log "   • 开始使用 Claude Code: claude --help"
    fi

    log "🔄 可随时重新运行此脚本进行更新或维护。"
    log "📄 部署状态已保存到: $STATUS_FILE"
}

# --- 脚本入口 ---
main "$@"
exit 0
