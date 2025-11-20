#!/bin/bash

#================================================================================
# sing-box 一键安装脚本 (Debian 13 优化版)
#
# 功能:
#   - 自动下载并安装最新版 sing-box
#   - 配置 systemd 服务
#   - 生成基础配置文件 (Shadowsocks 2022)
#   - 支持多架构 (amd64, arm64, armv7)
#
# 适用系统: Debian 12/13+, Ubuntu 20+
#================================================================================

set -euo pipefail

#--- 全局变量 ---
readonly INSTALL_PATH="/usr/local/bin"
readonly CONFIG_PATH="/etc/sing-box"
readonly SERVICE_PATH="/etc/systemd/system/sing-box.service"
readonly TMP_DIR=$(mktemp -d)
readonly DEFAULT_PORT="59271"
readonly DEFAULT_PASSWORD="IUmuU/NjIQhHPMdBz5WONA=="

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
    cleanup
    exit 1
}

echo_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR" 2>/dev/null || true
    fi
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
            echo "arm64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        *)
            echo_error "不支持的系统架构: $arch"
            ;;
    esac
}

install_dependencies() {
    echo_info "检查并安装依赖..."
    
    local missing_deps=()
    for dep in wget tar curl; do
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
            echo_error "依赖安装失败。"
        fi
    fi
    
    echo_success "依赖检查完成。"
}

get_latest_version() {
    echo_info "获取最新版本信息..."
    
    local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local version
    
    version=$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null | \
              grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
    
    if [[ -z "$version" ]]; then
        echo_error "无法获取最新版本信息。"
    fi
    
    echo_info "最新版本: $version"
    echo "$version"
}

download_and_install() {
    local arch_name
    arch_name=$(detect_architecture)
    
    local version
    version=$(get_latest_version)
    
    echo_info "正在下载 sing-box ${version} (${arch_name})..."
    
    local download_url="https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box-${version#v}-linux-${arch_name}.tar.gz"
    
    if ! wget -q --timeout=30 --tries=3 -O "${TMP_DIR}/sing-box.tar.gz" "$download_url"; then
        echo_error "下载失败，请检查网络连接。"
    fi
    
    echo_info "正在解压..."
    if ! tar -xzf "${TMP_DIR}/sing-box.tar.gz" -C "$TMP_DIR" 2>/dev/null; then
        echo_error "解压失败。"
    fi
    
    # 查找解压后的目录
    local extracted_dir
    extracted_dir=$(find "$TMP_DIR" -type d -name "sing-box-*" | head -1)
    
    if [[ -z "$extracted_dir" || ! -f "${extracted_dir}/sing-box" ]]; then
        echo_error "解压后未找到 sing-box 可执行文件。"
    fi
    
    echo_info "正在安装到 ${INSTALL_PATH}/sing-box..."
    if ! install -m 755 "${extracted_dir}/sing-box" "${INSTALL_PATH}/sing-box"; then
        echo_error "安装二进制文件失败。"
    fi
    
    echo_success "sing-box ${version} 安装成功。"
}

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

generate_private_key() {
    "${INSTALL_PATH}/sing-box" generate reality-keypair 2>/dev/null | grep "PrivateKey:" | awk '{print $2}'
}

generate_public_key() {
    local private_key="$1"
    "${INSTALL_PATH}/sing-box" generate reality-keypair --private-key "$private_key" 2>/dev/null | grep "PublicKey:" | awk '{print $2}'
}

generate_short_id() {
    openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | xxd -p
}

get_server_ip() {
    local server_ip
    server_ip=$(curl -s --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 5 --max-time 10 https://ifconfig.me 2>/dev/null || \
                curl -s --connect-timeout 5 --max-time 10 https://icanhazip.com 2>/dev/null || \
                hostname -I | awk '{print $1}')
    
    echo "$server_ip"
}

create_config() {
    echo_info "创建配置文件..."
    mkdir -p "$CONFIG_PATH"
    
    # 使用默认配置
    local port="${DEFAULT_PORT}"
    local password="${DEFAULT_PASSWORD}"
    
    # 创建配置文件
    cat > "${CONFIG_PATH}/config.json" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "DIRECT",
      "listen": "::",
      "listen_port": ${port},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${password}",
      "multiplex": {
        "enabled": true,
        "padding": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
    
    echo_success "配置文件创建成功: ${CONFIG_PATH}/config.json"
    
    # 显示配置信息
    local server_ip
    server_ip=$(get_server_ip)
    
    echo
    echo "================================================================================"
    echo "                    sing-box Shadowsocks 2022 配置信息"
    echo "================================================================================"
    echo "服务器地址:   ${server_ip}"
    echo "端口:         ${port}"
    echo "密码:         ${password}"
    echo "加密方式:     2022-blake3-aes-128-gcm"
    echo "多路复用:     启用"
    echo
    echo "客户端配置示例:"
    echo "--------------------------------"
    echo "协议:         Shadowsocks 2022"
    echo "地址:         ${server_ip}"
    echo "端口:         ${port}"
    echo "密码:         ${password}"
    echo "加密方式:     2022-blake3-aes-128-gcm"
    echo "================================================================================"
    echo
    
    # 保存配置信息到文件
    cat > "${CONFIG_PATH}/client-config.txt" << EOF
sing-box Shadowsocks 2022 客户端配置信息
========================================

服务器地址: ${server_ip}
端口: ${port}
密码: ${password}
加密方式: 2022-blake3-aes-128-gcm
多路复用: 启用

配置 URI:
ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206${password}@${server_ip}:${port}#sing-box-ss2022
EOF
    
    echo_info "配置信息已保存到: ${CONFIG_PATH}/client-config.txt"
}

create_systemd_service() {
    echo_info "创建 systemd 服务..."
    
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/sing-box run -c ${CONFIG_PATH}/config.json
ExecReload=/bin/kill -HUP \$MAINPID
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
    echo_info "启动 sing-box 服务..."
    
    systemctl daemon-reload
    
    if systemctl is-enabled sing-box &>/dev/null; then
        echo_info "服务已启用，正在重启..."
        systemctl restart sing-box
    else
        systemctl enable sing-box 2>/dev/null || true
        systemctl start sing-box
    fi
    
    sleep 2
    
    if systemctl is-active --quiet sing-box; then
        echo_success "sing-box 服务已成功启动！"
    else
        echo_warn "sing-box 服务启动失败。"
        echo_warn "请使用 'journalctl -u sing-box -n 50' 查看日志。"
        return 1
    fi
}

verify_installation() {
    echo_info "验证安装..."
    
    if [[ -x "${INSTALL_PATH}/sing-box" ]]; then
        local version
        version=$("${INSTALL_PATH}/sing-box" version 2>/dev/null | head -1 || echo "未知版本")
        echo_info "二进制文件: ${INSTALL_PATH}/sing-box ($version)"
    else
        echo_warn "二进制文件验证失败"
    fi
    
    if [[ -f "${CONFIG_PATH}/config.json" ]]; then
        echo_info "配置文件: ${CONFIG_PATH}/config.json"
    else
        echo_warn "配置文件验证失败"
    fi
    
    if systemctl is-active --quiet sing-box; then
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
    echo "  启动服务:   sudo systemctl start sing-box"
    echo "  停止服务:   sudo systemctl stop sing-box"
    echo "  重启服务:   sudo systemctl restart sing-box"
    echo "  查看状态:   sudo systemctl status sing-box"
    echo "  查看日志:   sudo journalctl -u sing-box -f"
    echo "  验证配置:   sudo sing-box check -c ${CONFIG_PATH}/config.json"
    echo "  查看配置:   cat ${CONFIG_PATH}/config.json"
    echo "  客户端配置: cat ${CONFIG_PATH}/client-config.txt"
    echo
    echo "  卸载 sing-box:"
    echo "    sudo systemctl stop sing-box && sudo systemctl disable sing-box"
    echo "    sudo rm -f ${INSTALL_PATH}/sing-box"
    echo "    sudo rm -f ${SERVICE_PATH}"
    echo "    sudo rm -rf ${CONFIG_PATH}"
    echo
    echo "  官方文档: https://sing-box.sagernet.org"
    echo "================================================================================"
    echo
}

#--- 主程序 ---
main() {
    trap cleanup EXIT
    trap 'echo_error "脚本在行号 $LINENO 处意外退出"' ERR

    clear
    echo "================================================================================"
    echo "            sing-box 一键安装脚本 (Debian 13 优化版)"
    echo "================================================================================"
    echo
    
    check_root
    install_dependencies
    
    # 检查是否已安装
    if [[ -f "${INSTALL_PATH}/sing-box" ]]; then
        local reinstall
        read -p "检测到已安装 sing-box，是否重新安装? [y/N]: " -r reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            echo_info "取消安装。"
            exit 0
        fi
        # 停止服务
        systemctl stop sing-box 2>/dev/null || true
    fi
    
    download_and_install
    
    # 如果配置文件已存在，询问是否覆盖
    if [[ -f "${CONFIG_PATH}/config.json" ]]; then
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
    
    echo_success "sing-box 安装完成！"
}

main "$@"
