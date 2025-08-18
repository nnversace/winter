#!/bin/bash
# Docker & Docker Compose 一键部署脚本
# 专为 Debian 13 "Trixie" 优化，提供全自动安装与配置。

# --- 安全设置 ---
# -e: 如果命令返回非零退出状态，则立即退出。
# -u: 将未设置的变量视为错误。
# -o pipefail: 如果管道中的任何命令失败，则整个管道的退出状态为失败。
set -euo pipefail

# === 常量与变量定义 ===
readonly DOCKER_CONFIG_DIR="/etc/docker"
readonly DOCKER_DAEMON_CONFIG="$DOCKER_CONFIG_DIR/daemon.json"
readonly TARGET_OS_NAME="Debian GNU/Linux"
readonly TARGET_OS_VERSION="13"

# === 日志与输出函数 ===
# 使用颜色代码，使输出信息更易读
log() {
    local msg="$1"
    local level="${2:-INFO}"
    local color_code

    case "$level" in
        INFO) color_code="\033[0;36m" ;;  # 青色
        SUCCESS) color_code="\033[0;32m" ;; # 绿色
        WARN) color_code="\033[0;33m" ;;   # 黄色
        ERROR) color_code="\033[0;31m" ;;  # 红色
        *) color_code="\033[0m" ;;         # 默认
    esac
    # 输出带有时间戳和颜色标记的日志
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${color_code}${msg}\033[0m"
}

# 脚本执行出错时的处理函数
handle_error() {
    log "脚本在行号 $1 处意外终止。" "ERROR"
    log "请检查上述错误信息并重试。" "ERROR"
    exit 1
}

# 捕获ERR信号，执行错误处理函数
trap 'handle_error $LINENO' ERR

# === 环境检查函数 ===
# 检查脚本是否以 root 用户权限运行
check_root_privileges() {
    log "检查管理员权限..." "INFO"
    if [[ "$(id -u)" -ne 0 ]]; then
        log "错误：此脚本需要以 root 或 sudo 权限运行。" "ERROR"
        exit 1
    fi
    log "权限检查通过。" "SUCCESS"
}

# 检查操作系统是否为 Debian 13
check_os_compatibility() {
    log "检查操作系统兼容性..." "INFO"
    if [[ -f /etc/os-release ]]; then
        # 从 /etc/os-release 文件中获取操作系统信息
        source /etc/os-release
        if [[ "${NAME}" == "${TARGET_OS_NAME}" && "${VERSION_ID}" == "${TARGET_OS_VERSION}" ]]; then
            log "检测到操作系统: ${PRETTY_NAME}，符合要求。" "SUCCESS"
        else
            log "警告：当前系统为 ${PRETTY_NAME}，并非 Debian 13。" "WARN"
            log "脚本将继续尝试，但可能存在兼容性问题。" "WARN"
        fi
    else
        log "警告：无法确定操作系统版本，将继续执行。" "WARN"
    fi
}

# === 核心功能函数 ===
# 安装系统依赖
install_dependencies() {
    log "更新软件包列表并安装依赖 (curl, gpg)..." "INFO"
    # 使用 apt-get 进行静默安装
    if apt-get update -qq && apt-get install -y -qq curl gpg; then
        log "依赖安装成功。" "SUCCESS"
    else
        log "依赖安装失败，请检查网络连接或软件包源。" "ERROR"
        exit 1
    fi
}

# 安装 Docker Engine
install_docker() {
    log "开始安装 Docker Engine..." "INFO"
    if command -v docker &>/dev/null; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log "Docker 已安装，版本: v${docker_version}。跳过安装。" "SUCCESS"
        return
    fi

    log "正在从官方源下载并安装 Docker..." "INFO"
    # 使用官方安装脚本进行静默安装
    if curl -fsSL https://get.docker.com | sh > /dev/null 2>&1; then
        # 验证安装是否成功
        if ! command -v docker &>/dev/null; then
            log "Docker 安装失败，请检查网络或官方脚本支持情况。" "ERROR"
            exit 1
        fi
        log "Docker Engine 安装成功。" "SUCCESS"
    else
        log "Docker 安装脚本执行失败。" "ERROR"
        exit 1
    fi
}

# 安装 Docker Compose
install_docker_compose() {
    log "开始安装 Docker Compose..." "INFO"
    if command -v docker-compose &>/dev/null; then
        local compose_version
        compose_version=$(docker-compose --version | awk '{print $NF}')
        log "Docker Compose 已安装，版本: v${compose_version}。跳过安装。" "SUCCESS"
        return
    fi
    
    log "正在从 GitHub 获取最新的 Docker Compose 版本..." "INFO"
    # 自动获取最新稳定版
    local latest_compose_version
    latest_compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$latest_compose_version" ]]; then
        log "无法获取 Docker Compose 最新版本号，请检查网络。" "ERROR"
        exit 1
    fi

    log "正在下载 Docker Compose ${latest_compose_version}..." "INFO"
    local os arch
    os=$(uname -s)
    arch=$(uname -m)
    local compose_url="https://github.com/docker/compose/releases/download/${latest_compose_version}/docker-compose-${os}-${arch}"
    
    # 下载并安装到 /usr/local/bin
    if curl -fsSL "${compose_url}" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        # 验证安装
        if ! command -v docker-compose &>/dev/null; then
            log "Docker Compose 安装失败。" "ERROR"
            exit 1
        fi
        log "Docker Compose ${latest_compose_version} 安装成功。" "SUCCESS"
    else
        log "Docker Compose 下载失败。" "ERROR"
        exit 1
    fi
}

# 配置 Docker 并优化
configure_docker() {
    log "开始配置和优化 Docker..." "INFO"
    
    # 创建配置目录
    if ! mkdir -p "${DOCKER_CONFIG_DIR}"; then
        log "创建 Docker 配置目录失败。" "ERROR"
        exit 1
    fi
    
    log "正在生成 daemon.json 配置文件..." "INFO"
    # 写入优化配置，包括日志轮转和国内镜像加速
    cat > "${DOCKER_DAEMON_CONFIG}" << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF
    log "配置文件已写入: ${DOCKER_DAEMON_CONFIG}" "SUCCESS"

    log "启用并重启 Docker 服务以应用新配置..." "INFO"
    # 确保 Docker 服务开机自启并立即启动
    if systemctl enable --now docker >/dev/null 2>&1 && systemctl restart docker; then
        log "Docker 服务已启动并设置为开机自启。" "SUCCESS"
    else
        log "Docker 服务启动或重启失败。" "ERROR"
        exit 1
    fi
}

# 显示最终的配置摘要
show_summary() {
    local docker_version="未安装"
    local compose_version="未安装"
    local service_status="\033[0;31m未运行\033[0m" # 红色

    if command -v docker &>/dev/null; then
        docker_version="v$(docker --version | awk '{print $3}' | tr -d ',')"
    fi
    
    if command -v docker-compose &>/dev/null; then
        compose_version="v$(docker-compose --version | awk '{print $NF}')"
    fi

    if systemctl is-active --quiet docker; then
        service_status="\033[0;32m运行中\033[0m" # 绿色
    fi

    echo
    echo -e "\033[1;34m===================================================\033[0m"
    echo -e "\033[1;34m          Docker 环境部署完成 - 摘要          \033[0m"
    echo -e "\033[1;34m===================================================\033[0m"
    echo
    echo -e "  \033[1m操作系统:\033[0m           $(source /etc/os-release && echo "$PRETTY_NAME")"
    echo -e "  \033[1mDocker Engine 版本:\033[0m  ${docker_version}"
    echo -e "  \033[1mDocker Compose 版本:\033[0m ${compose_version}"
    echo -e "  \033[1mDocker 服务状态:\033[0m    ${service_status}"
    echo -e "  \033[1m配置文件:\033[0m           ${DOCKER_DAEMON_CONFIG}"
    echo
    echo -e "  \033[1;32m常用命令:\033[0m"
    echo -e "    - 查看运行中的容器: \033[0;36mdocker ps\033[0m"
    echo -e "    - 查看所有镜像:     \033[0;36mdocker images\033[0m"
    echo -e "    - 清理系统资源:     \033[0;36mdocker system prune -f\033[0m"
    echo
    echo -e "\033[1;34m===================================================\033[0m"
}

# === 主流程 ===
main() {
    log "欢迎使用 Docker 一键部署脚本！" "INFO"
    echo "---------------------------------------------------"
    
    check_root_privileges
    check_os_compatibility
    install_dependencies
    install_docker
    install_docker_compose
    configure_docker
    show_summary
    
    echo "---------------------------------------------------"
    log "所有操作已成功完成！" "SUCCESS"
}

# --- 脚本执行入口 ---
main "$@"
