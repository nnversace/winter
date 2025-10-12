#!/bin/bash
# 系统工具一键安装脚本 - for Debian 13
# 功能: 非交互式地安装常用系统和网络工具，并自动处理依赖和迁移。
# 特点: 幂等设计，可安全重复运行；自动为 nexttrace 配置官方 apt 源。

# --- 脚本配置 ---
# 遇到错误时立即退出
set -euo pipefail

# --- 常量定义 ---
# 工具列表定义
# 格式: "命令名称:安装包名:工具描述"
# 说明: 'apt-nexttrace' 是一个特殊标识，用于触发添加源的逻辑。
readonly TOOLS=(
    "nexttrace:apt-nexttrace:强大的网络路由追踪工具"
    "speedtest:speedtest-cli:命令行网络测速工具"
    "htop:htop:交互式进程查看器"
    "jq:jq:JSON 命令行处理工具"
    "tree:tree:以树状图列出目录内容"
    "curl:curl:强大的数据传输工具"
    "wget:wget:非交互式文件下载工具"
)

# nexttrace 官方 apt 源配置文件路径
readonly NEXTTRACE_APT_SOURCE_FILE="/etc/apt/sources.list.d/nexttrace.list"

# --- 日志函数 ---
# 带有颜色的日志输出
# 参数1: 消息
# 参数2: 日志级别 (info, warn, error, success)
log() {
    local msg="$1" level="${2:-info}"
    local color_prefix=""
    case "$level" in
        info) color_prefix="\033[0;36m" ;;  # 青色
        warn) color_prefix="\033[0;33m" ;;  # 黄色
        error) color_prefix="\033[0;31m" ;; # 红色
        success) color_prefix="\033[0;32m" ;; # 绿色
    esac
    # 将日志输出到 stderr，以区分脚本的正常输出
    >&2 echo -e "${color_prefix}[${level^^}] ${msg}\033[0m"
}

# --- 核心功能函数 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "此脚本需要以 root 权限运行。" "error"
        exit 1
    fi
}

# 迁移旧的手动安装版 nexttrace
# 即使 apt 可以覆盖，也建议清理旧文件以避免 PATH 混乱
migrate_old_nexttrace() {
    # 查找旧的、非 dpkg 管理的 nexttrace 路径
    local old_path
    old_path=$(command -v nexttrace || true)
    
    if [[ -n "$old_path" && ! $(dpkg-query -S "$old_path" 2>/dev/null) ]]; then
        log "检测到旧版手动安装的 nexttrace，将尝试移除: $old_path" "warn"
        if rm -f "$old_path"; then
            log "已移除旧版本。" "success"
            hash -r # 清理 shell 的命令路径缓存
        else
            log "移除旧版本失败，请手动检查: $old_path" "error"
        fi
    fi
}

# 为 nexttrace 配置官方 apt 源
setup_nexttrace_repo() {
    if [[ -f "$NEXTTRACE_APT_SOURCE_FILE" ]]; then
        log "nexttrace apt 源已存在，无需配置。" "info"
        return 0
    fi
    
    log "正在为 nexttrace 配置官方 apt 源..." "info"
    
    # 定义源内容
    local repo_line="deb [signed-by=/usr/share/keyrings/nexttrace.gpg] https://github.com/nxtrace/nexttrace-debs/releases/latest/download ./"
    local gpg_key_url="https://github.com/nxtrace/nexttrace-debs/raw/main/nexttrace.gpg"
    local gpg_key_path="/usr/share/keyrings/nexttrace.gpg"

    # 使用 curl 下载 GPG 密钥
    if ! curl -fsSL "$gpg_key_url" -o "$gpg_key_path"; then
        log "下载 nexttrace GPG 密钥失败。" "error"
        return 1
    fi
    
    # 写入源配置文件
    if ! echo "$repo_line" | tee "$NEXTTRACE_APT_SOURCE_FILE" > /dev/null; then
        log "写入 nexttrace apt 源配置失败。" "error"
        rm -f "$gpg_key_path" # 清理失败时下载的密钥
        return 1
    fi
    
    log "nexttrace apt 源配置成功，将刷新 apt 列表。" "success"
    # 添加新源后，强制执行一次更新
    apt-get update -qq
}

# 安装单个工具
install_tool() {
    local tool_name="$1"
    local install_source="$2"
    
    log "--- 开始安装 $tool_name ---" "info"
    
    local package_name="$install_source"
    
    # 特殊处理 nexttrace：配置源并设置正确的包名
    if [[ "$install_source" == "apt-nexttrace" ]]; then
        migrate_old_nexttrace
        if ! setup_nexttrace_repo; then
            log "$tool_name 的前置配置失败，跳过安装。" "error"
            return 1
        fi
        package_name="nexttrace" # 将包名修正为实际的 apt 包名
    fi
    
    # 执行安装
    log "正在通过 apt 安装 $package_name..." "info"
    if apt-get install -y "$package_name" >/dev/null; then
        log "$tool_name 安装成功。" "success"
    else
        log "$tool_name ($package_name) 安装失败，请检查 apt 输出。" "error"
        return 1
    fi
    return 0
}

# 显示配置摘要
show_summary() {
    echo
    log "========== 系统工具配置摘要 ==========" "info"
    
    for tool_info in "${TOOLS[@]}"; do
        IFS=':' read -r tool_name _ description <<< "$tool_info"
        
        if command -v "$tool_name" &>/dev/null; then
            # 尝试获取版本信息，优先使用 --version，失败则尝试 -V
            local version_output
            version_output=$($tool_name --version 2>/dev/null || $tool_name -V 2>/dev/null || echo "版本未知")
            # 清理版本输出，只取第一行
            version_output=$(echo "$version_output" | head -n 1)
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
    echo "  - JSON 格式化: echo '{\"key\":\"value\"}' | jq ."
    log "========================================" "info"
}


# --- 主流程 ---
main() {
    check_root
    log "开始自动化配置系统工具 (Debian 13)..." "info"
    
    # 1. 初始更新 apt 包列表
    log "正在更新 apt 包列表..." "info"
    if ! apt-get update -qq; then
        log "apt 更新失败，请检查您的网络或软件源配置。" "error"
        exit 1
    fi
    log "apt 包列表更新完成。" "success"
    
    # 2. 遍历并安装所有工具
    for tool_info in "${TOOLS[@]}"; do
        IFS=':' read -r tool_name install_source description <<< "$tool_info"
        
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
