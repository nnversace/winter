#!/bin/bash

#================================================================================
# Snell v5 一键安装脚本 (Debian 13 优化版)
#
# 功能:
#   - 自动下载并安装 Snell Server v5
#   - 配置 systemd 服务
#   - 生成随机 PSK 密钥
#   - 支持多架构 (amd64, arm64, armv7)
#
# 适用系统: Debian 12/13+, Ubuntu 20+
#================================================================================

set -euo pipefail

#--- 全局变量 ---
readonly INSTALL_PATH="/usr/local/bin"
readonly CONFIG_PATH="/etc/snell"
readonly SERVICE_PATH="/etc/systemd/system/snell.service"
readonly SNELL_VERSION="${SNELL_VERSION:-5.0.0}"
readonly DEFAULT_PORT="6160"

#--- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#--- 函数定义 ---

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

echo_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo_error "请使用 root 权限运行此脚本 (例如: sudo $0)"
    fi
}

detect_architecture() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7)
            echo "armv7l"
            ;;
        *)
            echo_error "不支持的系统架构: $arch"
            ;;
    esac
}

install_dependencies() {
    echo_info "检查并安装依赖..."
    
    local missing_deps=()
    for dep in wget unzip; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if (( ${#missing_deps[@]} > 0 )); then
        echo_info "安装依赖: ${missing_deps[*]}"
        if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null; then
            echo_warn "apt update 失败，继续尝试安装..."
        fi
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_deps[@]}" 2>/dev/null; then
            echo_error "依赖安装失败，请检查网络连接。"
        fi
    fi
    
    echo_success "依赖检查完成。"
}

download_and_install() {
    local arch_name
    arch_name=$(detect_architecture)
    
    echo_info "检测到系统架构: $arch_name"
    echo_info "正在下载 Snell Server v${SNELL_VERSION}..."
    
    local download_url="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${arch_name}.zip"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if ! wget -q --timeout=30 --tries=3 -O "${temp_dir}/snell.zip" "$download_url"; then
        rm -rf "$temp_dir"
        echo_error "下载 Snell Server 失败，请检查网络连接或版本号。"
    fi
    
    echo_info "正在解压..."
    if ! unzip -q -o "${temp_dir}/snell.zip" -d "$temp_dir" 2>/dev/null; then
        rm -rf "$temp_dir"
        echo_error "解压失败。"
    fi
    
    echo_info "正在安装到 ${INSTALL_PATH}/snell-server..."
    if ! install -m 755 "${temp_dir}/snell-server" "${INSTALL_PATH}/snell-server"; then
        rm -rf "$temp_dir"
        echo_error "安装二进制文件失败。"
    fi
    
    rm -rf "$temp_dir"
    echo_success "Snell Server v${SNELL_VERSION} 安装成功。"
}

generate_psk() {
    if command -v openssl &>/dev/null; then
        openssl rand -base64 32 | tr -d '\n'
    else
        # 备用方法：使用 /dev/urandom
        head -c 32 /dev/urandom | base64 | tr -d '\n'
    fi
}

get_server_ip() {
    local server_ip
    # 尝试多种方法获取公网 IP
    server_ip=$(curl -s --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 5 --max-time 10 https://ifconfig.me 2>/dev/null || \
                curl -s --connect-timeout 5 --max-time 10 https://icanhazip.com 2>/dev/null || \
                hostname -I | awk '{print $1}')
    
    echo "$server_ip"
}

create_config() {
    echo_info "创建配置文件..."
    mkdir -p "$CONFIG_PATH"
    
    local psk
    psk=$(generate_psk)
    
    local port
    read -p "请输入监听端口 [默认: ${DEFAULT_PORT}]: " port
    port=${port:-$DEFAULT_PORT}
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo_warn "无效的端口号，使用默认端口: ${DEFAULT_PORT}"
        port=$DEFAULT_PORT
    fi
    
    cat > "${CONFIG_PATH}/snell-server.conf" << EOF
[snell-server]
# Snell Server v5 配置文件
listen = 0.0.0.0:${port}
psk = ${psk}
ipv6 = true
dns = 8.8.8.8, 1.1.1.1

# Obfs 混淆 (可选，取消注释启用)
# obfs = tls
# obfs-host = www.bing.com
EOF
    
    echo_success "配置文件创建成功: ${CONFIG_PATH}/snell-server.conf"
    
    # 显示配置信息
    local server_ip
    server_ip=$(get_server_ip)
    
    echo
    echo "================================================================================"
    echo "                    Snell v5 配置信息"
    echo "================================================================================"
    echo "服务器地址: ${server_ip}"
    echo "监听端口:   ${port}"
    echo "密钥 (PSK): ${psk}"
    echo "版本:       5"
    echo
    echo "客户端配置示例 (Surge/Shadowrocket):"
    echo "--------------------------------"
    echo "[Proxy]"
    echo "Snell = snell, ${server_ip}, ${port}, psk=${psk}, version=5"
    echo
    echo "或使用 URI 格式:"
    echo "snell://${server_ip}:${port}?psk=${psk}&version=5"
    echo "================================================================================"
    echo
    
    # 保存配置信息到文件
    cat > "${CONFIG_PATH}/client-config.txt" << EOF
Snell v5 客户端配置信息
======================

服务器地址: ${server_ip}
端口: ${port}
PSK: ${psk}
版本: 5

Surge/Shadowrocket 配置:
Snell = snell, ${server_ip}, ${port}, psk=${psk}, version=5

URI 格式:
snell://${server_ip}:${port}?psk=${psk}&version=5
EOF
    
    echo_info "配置信息已保存到: ${CONFIG_PATH}/client-config.txt"
}

create_systemd_service() {
    echo_info "创建 systemd 服务..."
    
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Snell Proxy Server v5
Documentation=https://manual.nssurge.com/others/snell.html
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/snell-server -c ${CONFIG_PATH}/snell-server.conf
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    echo_success "Systemd 服务创建成功。"
}

start_service() {
    echo_info "启动 Snell 服务..."
    
    systemctl daemon-reload
    
    if systemctl is-enabled snell &>/dev/null; then
        echo_info "服务已启用，正在重启..."
        systemctl restart snell
    else
        systemctl enable snell 2>/dev/null || true
        systemctl start snell
    fi
    
    sleep 2
    
    if systemctl is-active --quiet snell; then
        echo_success "Snell 服务已成功启动！"
    else
        echo_warn "Snell 服务启动失败。"
        echo_warn "请使用 'journalctl -u snell -n 50' 查看日志。"
        return 1
    fi
}

verify_installation() {
    echo_info "验证安装..."
    
    if [[ -x "${INSTALL_PATH}/snell-server" ]]; then
        local version
        version=$("${INSTALL_PATH}/snell-server" --version 2>/dev/null | head -1 || echo "未知版本")
        echo_info "二进制文件: ${INSTALL_PATH}/snell-server ($version)"
    else
        echo_warn "二进制文件验证失败"
    fi
    
    if [[ -f "${CONFIG_PATH}/snell-server.conf" ]]; then
        echo_info "配置文件: ${CONFIG_PATH}/snell-server.conf"
    else
        echo_warn "配置文件验证失败"
    fi
    
    if systemctl is-active --quiet snell; then
        echo_info "服务状态: 运行中"
    else
        echo_warn "服务状态: 未运行"
    fi
}

show_management_commands() {
    echo
    echo "================================================================================"
    echo "                    常用管理命令"
    echo "================================================================================"
    echo "  启动服务:   sudo systemctl start snell"
    echo "  停止服务:   sudo systemctl stop snell"
    echo "  重启服务:   sudo systemctl restart snell"
    echo "  查看状态:   sudo systemctl status snell"
    echo "  查看日志:   sudo journalctl -u snell -f"
    echo "  查看配置:   cat ${CONFIG_PATH}/snell-server.conf"
    echo "  客户端配置: cat ${CONFIG_PATH}/client-config.txt"
    echo
    echo "  卸载 Snell:"
    echo "    sudo systemctl stop snell && sudo systemctl disable snell"
    echo "    sudo rm -f ${INSTALL_PATH}/snell-server"
    echo "    sudo rm -f ${SERVICE_PATH}"
    echo "    sudo rm -rf ${CONFIG_PATH}"
    echo "================================================================================"
    echo
}

#--- 主程序 ---
main() {
    trap 'echo_error "脚本在行号 $LINENO 处意外退出"' ERR

    clear
    echo "================================================================================"
    echo "              Snell Server v5 一键安装脚本 (Debian 13 优化版)"
    echo "================================================================================"
    echo
    
    check_root
    install_dependencies
    
    # 检查是否已安装
    if [[ -f "${INSTALL_PATH}/snell-server" ]]; then
        local reinstall
        read -p "检测到已安装 Snell Server，是否重新安装? [y/N]: " -r reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            echo_info "取消安装。"
            exit 0
        fi
        # 停止服务
        systemctl stop snell 2>/dev/null || true
    fi
    
    download_and_install
    
    # 如果配置文件已存在，询问是否覆盖
    if [[ -f "${CONFIG_PATH}/snell-server.conf" ]]; then
        local overwrite
        read -p "配置文件已存在，是否覆盖? [y/N]: " -r overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            create_config
        else
            echo_info "保留现有配置文件。"
        fi
    else
        create_config
    fi
    
    create_systemd_service
    start_service
    
    verify_installation
    show_management_commands
    
    echo_success "Snell Server v5 安装完成！"
}

main "$@"
