#!/bin/bash

#================================================================================
# MosDNS-X 一键安装脚本 (Debian 13 优化版)
#
# 功能:
#   - 自动检测并下载最新的 mosdns-x 版本
#   - 安装必要的依赖 (unzip, curl)
#   - 创建配置文件目录和文件
#   - 创建并启动 systemd 服务，实现开机自启
#   - 清理临时文件
#
# 适用系统: Debian 12/13+, Ubuntu 20+
#================================================================================

set -euo pipefail

#--- 全局变量 ---
readonly INSTALL_PATH="/usr/local/bin"
readonly CONFIG_PATH="/etc/mosdns-x"
readonly SERVICE_PATH="/etc/systemd/system/mosdns-x.service"
readonly TMP_DIR=$(mktemp -d)

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

install_dependencies() {
    echo_info "正在更新软件包列表并安装依赖 (unzip, curl)..."
    
    if ! apt-get update -qq 2>/dev/null; then
        echo_warn "apt update 失败，继续尝试安装依赖..."
    fi
    
    local missing_deps=()
    for dep in unzip curl wget; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if (( ${#missing_deps[@]} > 0 )); then
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_deps[@]}" 2>/dev/null; then
            echo_error "依赖安装失败，请检查您的网络连接和软件源设置。"
        fi
        echo_info "已安装依赖: ${missing_deps[*]}"
    else
        echo_info "所有依赖已满足。"
    fi
}

detect_architecture() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            echo "linux-amd64"
            ;;
        aarch64|arm64)
            echo "linux-arm64"
            ;;
        armv7l|armv7)
            echo "linux-armv7"
            ;;
        *)
            echo_error "不支持的系统架构: $arch"
            ;;
    esac
}

get_latest_release() {
    echo_info "正在获取 mosdns-x 最新版本信息..."
    
    local arch_name
    arch_name=$(detect_architecture)
    
    local api_url="https://api.github.com/repos/pmkol/mosdns-x/releases/latest"
    
    local download_url
    download_url=$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null | \
                   grep "browser_download_url.*${arch_name}.zip" | \
                   sed -E 's/.*"([^"]+)".*/\1/' | head -1)
    
    if [[ -z "$download_url" ]]; then
        echo_error "无法获取 mosdns-x 下载链接 (架构: $arch_name)。请检查网络或访问 https://github.com/pmkol/mosdns-x/releases"
    fi
    
    echo_info "下载链接: $download_url"
    echo "$download_url"
}

download_and_install() {
    local download_url="$1"
    
    echo_info "正在下载 mosdns-x..."
    if ! curl -fsSL --connect-timeout 10 --max-time 300 "$download_url" -o "$TMP_DIR/mosdns.zip"; then
        if ! wget -q --timeout=10 --tries=3 -O "$TMP_DIR/mosdns.zip" "$download_url"; then
            echo_error "下载失败，请检查网络。"
        fi
    fi
    
    echo_info "正在解压文件..."
    if ! unzip -q -o "$TMP_DIR/mosdns.zip" -d "$TMP_DIR" 2>/dev/null; then
        echo_error "解压失败。"
    fi
    
    local source_exec_name="mosdns"
    if [[ ! -f "$TMP_DIR/$source_exec_name" ]]; then
        echo_error "在解压的文件中找不到名为 '$source_exec_name' 的可执行文件。"
    fi

    echo_info "正在安装 $source_exec_name 到 $INSTALL_PATH/mosdns-x..."
    if ! install -m 755 "$TMP_DIR/$source_exec_name" "$INSTALL_PATH/mosdns-x"; then
        echo_error "安装二进制文件失败。"
    fi
    
    echo_success "MosDNS-X 安装成功。"
}

create_config_file() {
    echo_info "正在创建配置文件到 $CONFIG_PATH/config.yaml..."
    mkdir -p "$CONFIG_PATH"
    
    cat > "$CONFIG_PATH/config.yaml" << 'EOF'
log:
  level: info
  file: ""

plugins:
  - tag: forward_dot_servers
    type: fast_forward
    args:
      upstream:
        - addr: tls://1.1.1.1      # Cloudflare DNS
        - addr: tls://8.8.8.8      # Google DNS
        - addr: tls://9.9.9.9      # Quad9 DNS

servers:
  - exec: forward_dot_servers
    listeners:
      - protocol: udp
        addr: 127.0.0.1:5533
      - protocol: tcp
        addr: 127.0.0.1:5533
EOF

    if [[ $? -ne 0 ]]; then
        echo_error "创建配置文件失败。"
    fi
    
    echo_success "配置文件创建成功。"
}

create_systemd_service() {
    echo_info "正在创建 systemd 服务..."
    
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=MosDNS-X - DNS Forwarder (Debian 13 Optimized)
Documentation=https://github.com/pmkol/mosdns-x/wiki
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_PATH/mosdns-x start -c $CONFIG_PATH/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    if [[ $? -ne 0 ]]; then
        echo_error "创建 systemd 服务文件失败。"
    fi
    
    echo_success "Systemd 服务创建成功。"
}

start_service() {
    echo_info "正在重载 systemd 并启动 mosdns-x 服务..."
    
    systemctl daemon-reload
    
    if systemctl is-enabled mosdns-x &>/dev/null; then
        echo_info "服务已启用，正在重启..."
        systemctl restart mosdns-x
    else
        systemctl enable mosdns-x 2>/dev/null || true
        systemctl start mosdns-x
    fi
    
    sleep 2
    
    if systemctl is-active --quiet mosdns-x; then
        echo_success "mosdns-x 服务已成功启动！"
    else
        echo_warn "mosdns-x 服务启动失败。"
        echo_warn "请使用 'journalctl -u mosdns-x -n 50' 查看日志。"
        return 1
    fi
}

verify_installation() {
    echo_info "验证安装..."
    
    if [[ -x "$INSTALL_PATH/mosdns-x" ]]; then
        local version
        version=$("$INSTALL_PATH/mosdns-x" version 2>/dev/null | head -1 || echo "未知版本")
        echo_info "二进制文件: $INSTALL_PATH/mosdns-x ($version)"
    else
        echo_warn "二进制文件验证失败"
    fi
    
    if [[ -f "$CONFIG_PATH/config.yaml" ]]; then
        echo_info "配置文件: $CONFIG_PATH/config.yaml"
    else
        echo_warn "配置文件验证失败"
    fi
    
    if systemctl is-active --quiet mosdns-x; then
        echo_info "服务状态: 运行中"
    else
        echo_warn "服务状态: 未运行"
    fi
}

show_summary() {
    echo
    echo "============================================================"
    echo "          MosDNS-X 安装完成 (Debian 13 优化版)"
    echo "============================================================"
    echo "  配置文件: $CONFIG_PATH/config.yaml"
    echo "  DNS 服务监听地址: 127.0.0.1:5533 (TCP/UDP)"
    echo
    echo "  常用命令:"
    echo "    - 启动服务: sudo systemctl start mosdns-x"
    echo "    - 停止服务: sudo systemctl stop mosdns-x"
    echo "    - 重启服务: sudo systemctl restart mosdns-x"
    echo "    - 查看状态: sudo systemctl status mosdns-x"
    echo "    - 查看日志: sudo journalctl -u mosdns-x -f"
    echo "    - 测试DNS:  dig @127.0.0.1 -p 5533 google.com"
    echo "============================================================"
    echo
}

#--- 主程序 ---
main() {
    trap cleanup EXIT
    trap 'echo_error "脚本在行号 $LINENO 处意外退出"' ERR

    check_root
    install_dependencies
    
    local download_url
    download_url=$(get_latest_release)
    
    download_and_install "$download_url"
    create_config_file
    create_systemd_service
    start_service
    
    verify_installation
    show_summary
}

main "$@"
