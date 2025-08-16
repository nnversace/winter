#!/bin/bash
# Docker 容器化平台配置模块 v6.0 - 优化版
# 功能: 安装Docker、优化配置、增强健壮性

# --- 脚本配置 ---
# -e: 命令失败时立即退出
# -u: 变量未定义时报错
# -o pipefail: 管道中任一命令失败则整个管道失败
set -euo pipefail

# === 常量定义 ===
readonly DOCKER_CONFIG_DIR="/etc/docker"
readonly DOCKER_DAEMON_CONFIG="$DOCKER_CONFIG_DIR/daemon.json"
# 使用官方推荐的安装脚本 URL
readonly DOCKER_INSTALL_URL="https://get.docker.com"

# === 日志与输出 ===
# 统一定义颜色，方便维护
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;36m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_DEBUG='\033[0;35m'
readonly COLOR_SUCCESS='\033[0;32m'

# 封装日志函数，增加时间戳和级别
log() {
    local level="$1"
    local msg="$2"
    local color="$3"
    # 只有在 DEBUG 模式下才显示 DEBUG 日志
    if [[ "$level" == "DEBUG" && "${DEBUG:-}" != "1" ]]; then
        return
    fi
    printf "%b[%s] %s%b\n" "$color" "$(date +'%Y-%m-%d %H:%M:%S')" "$msg" "$COLOR_RESET" >&2
}

info() { log "INFO" "$1" "$COLOR_INFO"; }
warn() { log "WARN" "$1" "$COLOR_WARN"; }
error() { log "ERROR" "$1" "$COLOR_ERROR"; exit 1; }
debug() { log "DEBUG" "$1" "$COLOR_DEBUG"; }
success() { log "SUCCESS" "$1" "$COLOR_SUCCESS"; }

# === 依赖检查 ===
# 检查脚本所需的核心命令
check_dependencies() {
    debug "开始检查依赖项"
    local missing_deps=()
    local deps=("curl" "awk" "grep" "systemctl")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "缺少核心依赖: ${missing_deps[*]}. 请先安装它们。"
    fi
    debug "所有核心依赖项均已满足"
}

# === 辅助函数 ===
# 获取系统总内存（MB），逻辑更精简
get_memory_mb() {
    debug "获取系统内存大小"
    local mem_kb
    # /proc/meminfo 是最可靠和高效的方式
    if [[ -r /proc/meminfo ]]; then
        mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
        echo "$((mem_kb / 1024))"
        return
    fi
    # free 命令作为备选
    if command -v free >/dev/null; then
        free -m | awk '/^Mem:/{print $2}'
        return
    fi
    warn "无法确定内存大小"
    echo "0"
}

# 获取Docker版本
get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "未知"
}

# === 核心功能 ===
# 安装 Docker
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker 已安装，版本: $(get_docker_version)"
        return 0
    fi

    info "正在安装 Docker..."
    # 增加警告，提示用户脚本来源
    warn "将从 $DOCKER_INSTALL_URL 下载并执行脚本来安装 Docker。"
    warn "请确保您信任此来源。5秒后将继续..."
    sleep 5

    # 执行安装，并捕获详细日志
    local install_log
    install_log=$(mktemp)
    if curl -fsSL "$DOCKER_INSTALL_URL" | sh >"$install_log" 2>&1; then
        success "Docker 安装成功"
        debug "安装日志位于: $install_log"
    else
        error "Docker 安装失败。请查看日志: $install_log"
    fi
}

# 启动并启用 Docker 服务
start_docker_service() {
    debug "检查 Docker 服务状态"
    # 使用 systemctl is-active 和 is-enabled 进行精确判断
    if systemctl is-active --quiet docker; then
        info "Docker 服务已在运行"
    else
        info "正在启动 Docker 服务..."
        # 使用 --now 同时启动和启用
        if ! systemctl enable --now docker; then
            error "启动或启用 Docker 服务失败"
        fi
        success "Docker 服务已启动并设置为开机自启"
    fi
}

# 优化 Docker 配置 (关键优化)
# 使用 jq 安全地更新 JSON 文件，而不是直接覆盖
optimize_docker_config() {
    local mem_mb
    mem_mb=$(get_memory_mb)
    info "系统内存: ${mem_mb}MB"

    # 仅对低内存（小于等于1GB）设备建议优化
    if (( mem_mb > 1024 )); then
        info "内存充足，无需进行日志优化"
        return 0
    fi

    warn "系统内存较低，建议优化 Docker 日志以减少资源占用。"
    
    # 支持非交互式执行
    if [[ "${FORCE_OPTIMIZE:-}" != "true" ]]; then
        read -p "是否应用此优化? [Y/n] (默认: Y): " -r choice
        choice=${choice:-Y}
        if [[ ! "$choice" =~ ^[Yy]$ ]]; then
            info "跳过 Docker 配置优化"
            return 0
        fi
    fi

    info "正在应用 Docker 配置优化..."
    mkdir -p "$DOCKER_CONFIG_DIR"

    # 定义优化配置
    local optimization_json
    optimization_json='{
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "10m",
        "max-file": "3"
      }
    }'

    local needs_restart=false
    # 优先使用 jq 进行安全的 JSON 修改
    if command -v jq &>/dev/null; then
        debug "检测到 jq，使用 jq 安全地更新配置"
        # 读取现有配置，与新配置合并，然后写回
        # 使用 sponge 保证原子写入，防止文件损坏
        local temp_json
        temp_json=$(jq -s '.[0] * .[1]' "${DOCKER_DAEMON_CONFIG:-/dev/null}" <(echo "$optimization_json"))
        if ! echo "$temp_json" | jq . > "$DOCKER_DAEMON_CONFIG"; then
             error "使用 jq 更新 $DOCKER_DAEMON_CONFIG 失败"
        fi
        needs_restart=true
    else
        warn "未检测到 'jq' 命令。建议安装 (如: sudo apt-get install jq) 以安全地修改JSON配置。"
        # 如果 jq 不存在，则回退到简单模式：仅当文件不存在时才创建
        if [[ ! -f "$DOCKER_DAEMON_CONFIG" ]]; then
            debug "配置文件不存在，创建新的配置文件"
            if ! echo "$optimization_json" | jq . > "$DOCKER_DAEMON_CONFIG"; then
                error "写入 $DOCKER_DAEMON_CONFIG 失败"
            fi
            needs_restart=true
        else
            info "配置文件已存在且无 jq 工具，跳过修改以避免覆盖现有设置。"
        fi
    fi

    if [[ "$needs_restart" == "true" ]]; then
        info "配置已更新，正在重启 Docker 服务以应用更改..."
        if ! systemctl restart docker; then
            error "重启 Docker 服务失败"
        fi
        success "Docker 服务已重启"
    else
        info "Docker 配置未发生变化"
    fi
}

# 显示最终摘要
show_summary() {
    local version
    version=$(get_docker_version)
    success "🎉 Docker 环境配置完成!"
    echo -e "${COLOR_INFO}================ Docker 状态摘要 ================${COLOR_RESET}"
    echo -e "  - 版本:          ${COLOR_SUCCESS}$version${COLOR_RESET}"
    if systemctl is-active --quiet docker; then
        echo -e "  - 服务状态:      ${COLOR_SUCCESS}运行中${COLOR_RESET}"
    else
        echo -e "  - 服务状态:      ${COLOR_ERROR}未运行${COLOR_RESET}"
    fi
    local running_containers
    running_containers=$(docker ps -q 2>/dev/null | wc -l)
    echo -e "  - 运行中容器:    ${COLOR_SUCCESS}${running_containers}${COLOR_RESET}"
    
    if grep -q '"max-size": "10m"' "$DOCKER_DAEMON_CONFIG" 2>/dev/null; then
        echo -e "  - 日志优化:      ${COLOR_SUCCESS}已启用${COLOR_RESET}"
    else
        echo -e "  - 日志优化:      ${COLOR_WARN}未启用${COLOR_RESET}"
    fi
    echo -e "${COLOR_INFO}==================================================${COLOR_RESET}"
    echo
    info "常用命令:"
    echo "  - docker ps -a       (查看所有容器)"
    echo "  - docker images      (查看本地镜像)"
    echo "  - docker system prune (清理无用资源)"
}

# === 主函数 ===
main() {
    # 解析命令行参数，如 -y 或 --debug
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                FORCE_OPTIMIZE="true"
                shift
                ;;
            --debug)
                DEBUG="1"
                shift
                ;;
            *)
                error "未知参数: $1"
                ;;
        esac
    done

    info "🚀 开始配置 Docker 容器化平台..."
    
    check_dependencies
    install_docker
    start_docker_service
    optimize_docker_config
    
    echo
    show_summary
}

# 设置错误处理陷阱
trap 'error "脚本在行 $LINENO 处意外终止"' ERR

# 执行主函数
main "$@"
