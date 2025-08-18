#!/bin/bash
# 系统工具一键安装脚本 - for Debian 13
# 功能: 非交互式地安装常用系统和网络工具，并自动处理依赖和迁移。

# --- 脚本配置 ---
# 遇到错误时立即退出
set -euo pipefail

# --- 常量定义 ---
# 工具列表定义
# 格式: "命令名称:版本检查命令:安装包名或源:工具描述"
readonly TOOLS=(
    "nexttrace:nexttrace --version:apt-nexttrace:强大的网络路由追踪工具"
    "speedtest:speedtest --version:speedtest-cli:命令行网络测速工具"
    "htop:htop --version:htop:交互式进程查看器"
    "jq:jq --version:jq:JSON 命令行处理工具"
    "tree:tree --version:tree:以树状图列出目录内容"
    "curl:curl --version:curl:强大的数据传输工具"
    "wget:wget --version:wget:非交互式文件下载工具"
)

# --- 日志函数 ---
# 带有颜色的日志输出
# 参数1: 消息
# 参数2: 日志级别 (info, warn, error, success)
log() {
    local msg="$1" level="${2:-info}"
    local color_prefix
    case "$level" in
        info) color_prefix="\033[0;36m" ;;  # 青色
        warn) color_prefix="\033[0;33m" ;;  # 黄色
        error) color_prefix="\033[0;31m" ;; # 红色
        success) color_prefix="\033[0;32m" ;; # 绿色
        *) color_prefix="\033[0m" ;;
    esac
    echo -e "${color_prefix} [${level^^}] ${msg}\033[0m"
}

# --- 核心功能函数 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "此脚本需要以 root 权限运行。" "error"
        exit 1
    fi
}

# 处理现有的 nexttrace 安装（从脚本迁移到 apt）
handle_existing_nexttrace() {
    # 刷新命令缓存，确保检测准确
    hash -r 2>/dev/null || true
    
    # 如果命令不存在，则无需迁移
    if ! command -v nexttrace >/dev/null 2>&1; then
        return 0
    fi
    
    # 检查是否已通过 apt 安装
    if dpkg-query -W -f='${Status}' nexttrace 2>/dev/null | grep -q "install ok installed"; then
        return 0 # 已经是 apt 安装，无需迁移
    fi
    
    log "检测到旧版脚本安装的 nexttrace，将自动迁移到 apt 源..." "warn"
    
    # 删除旧的脚本安装版本
    local old_path
    old_path=$(command -v nexttrace)
    if [[ -n "$old_path" && -f "$old_path" ]]; then
        rm -f "$old_path"
        log "已删除旧版本: $old_path" "info"
    fi
    
    # 清理 PATH 缓存，为新安装做准备
    hash -r 2>/dev/null || true
}

# 安装单个工具
install_tool() {
    local tool_name="$1"
    local install_source="$2"
    
    log "正在安装 $tool_name..." "info"
    
    local success=false
    
    # 针对 nexttrace 的特殊 apt 源安装逻辑
    if [[ "$install_source" == "apt-nexttrace" ]]; then
        # 添加官方 apt 源（如果不存在）
        if [[ ! -f /etc/apt/sources.list.d/nexttrace.list ]]; then
            log "配置 nexttrace 官方 apt 源..." "info"
            echo "deb [trusted=yes] https://github.com/nxtrace/nexttrace-debs/releases/latest/download ./" | tee /etc/apt/sources.list.d/nexttrace.list >/dev/null
        fi
        # 更新包列表并安装
        if apt-get install -y nexttrace --allow-unauthenticated >/dev/null 2>&1; then
            success=true
        fi
    else
        # 标准 apt 包安装
        if apt-get install -y "$install_source" >/dev/null 2>&1; then
            success=true
        fi
    fi
    
    if $success; then
        log "$tool_name 安装成功。" "success"
    else
        log "$tool_name 安装失败。" "error"
    fi
    return 0
}

# 显示配置摘要
show_summary() {
    echo
    log "========== 系统工具配置摘要 ==========" "info"
    
    for tool_info in "${TOOLS[@]}"; do
        local tool_name="${tool_info%%:*}"
        local description="${tool_info##*:}"
        
        if command -v "$tool_name" &>/dev/null; then
            local version_output
            # 尝试获取版本号
            version_output=$($tool_name --version 2>/dev/null | head -n1 || echo "版本未知")
            log "✓ ${tool_name} - ${description} (已安装: ${version_output})" "success"
        else
            log "✗ ${tool_name} - ${description} (未安装)" "warn"
        fi
    done
    
    echo
    log "常用命令提示:" "info"
    echo "  - 网络路由追踪: nexttrace ip.sb"
    echo "  - 网络速度测试: speedtest"
    echo "  - 系统进程监控: htop"
    echo "  - 目录结构查看: tree /some/path"
    echo "  - JSON 格式化: echo '{\"key\":\"value\"}' | jq"
    log "========================================" "info"
}


# --- 主流程 ---
main() {
    check_root
    log "开始自动化配置系统工具 (Debian 13)..." "info"
    
    # 1. 更新 apt 包列表
    log "正在更新 apt 包列表..." "info"
    if ! apt-get update -qq >/dev/null 2>&1; then
        log "apt 更新失败，请检查您的网络或软件源配置。" "error"
        exit 1
    fi
    log "apt 包列表更新完成。" "success"
    
    # 2. 遍历并安装所有工具
    for tool_info in "${TOOLS[@]}"; do
        # 解析工具信息
        IFS=':' read -r tool_name check_cmd install_source description <<< "$tool_info"
        
        # 特殊处理 nexttrace 的迁移
        if [[ "$tool_name" == "nexttrace" ]]; then
            handle_existing_nexttrace
        fi
        
        # 检查工具是否已安装
        if command -v "$tool_name" &>/dev/null; then
            log "$tool_name 已安装，跳过。" "info"
        else
            install_tool "$tool_name" "$install_source"
        fi
    done
    
    # 3. 显示最终摘要
    show_summary
    
    log "所有工具已配置完成！" "success"
}

# --- 脚本执行入口 ---
main "$@"
