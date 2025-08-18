#!/bin/bash

#====================================================================================================
# mosdns-x 一键管理脚本 for Debian 13
#
# 功能:
#   - 安装: 下载、配置并启动 mosdns-x 服务
#   - 卸载: 停止并移除 mosdns-x 相关文件
#   - 重装: 先执行卸载，再执行安装
#
# GitHub: https://github.com/pmkol/mosdns-x
#====================================================================================================

# --- 配置 ---
# 二进制文件安装路径
INSTALL_PATH="/usr/local/bin"
# 配置文件目录
CONFIG_PATH="/etc/mosdns-x"
# systemd 服务文件路径
SERVICE_PATH="/etc/systemd/system/mosdns-x.service"
# 临时下载目录
TMP_DIR="/tmp/mosdns_x_install"

# --- 颜色定义 ---
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
NC="\033[0m" # No Color

# --- 辅助函数 ---

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要 root 权限运行。请使用 'sudo' 或以 root 用户身份执行。${NC}"
        exit 1
    fi
}

# 打印信息
log_info() {
    echo -e "${GREEN}[信息] $1${NC}"
}

# 打印警告
log_warn() {
    echo -e "${YELLOW}[警告] $1${NC}"
}

# 打印错误并退出
log_error() {
    echo -e "${RED}[错误] $1${NC}"
    exit 1
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            log_error "不支持的系统架构: ${ARCH}。仅支持 x86_64 和 aarch64。"
            ;;
    esac
    log_info "检测到系统架构: ${ARCH}"
}

# 创建配置文件
create_config_file() {
    log_info "创建配置文件目录: ${CONFIG_PATH}"
    mkdir -p "${CONFIG_PATH}"

    log_info "写入默认配置文件到 ${CONFIG_PATH}/config.yaml"
    cat > "${CONFIG_PATH}/config.yaml" <<EOF
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
}

# 创建 systemd 服务文件
create_systemd_service() {
    log_info "创建 systemd 服务文件: ${SERVICE_PATH}"
    cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=mosdns-x - A DNS forwarder
Documentation=https://github.com/pmkol/mosdns-x
After=network.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_PATH}/mosdns-x -c ${CONFIG_PATH}/config.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

# --- 主要功能函数 ---

# 安装 mosdns-x
do_install() {
    log_info "开始安装 mosdns-x..."
    
    # 1. 检查环境
    detect_arch
    
    # 2. 安装依赖
    log_info "更新软件包列表并安装依赖 (wget, unzip, ca-certificates)..."
    apt-get update > /dev/null
    apt-get install -y wget unzip ca-certificates > /dev/null
    if [ $? -ne 0 ]; then
        log_error "依赖安装失败，请检查网络连接和 apt 源。"
    fi

    # 3. 下载最新版本
    log_info "正在获取最新版本号..."
    LATEST_TAG=$(wget -qO- "https://api.github.com/repos/pmkol/mosdns-x/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "${LATEST_TAG}" ]; then
        log_error "获取最新版本号失败，请检查网络或 GitHub API 限制。"
    fi
    log_info "最新版本为: ${LATEST_TAG}"

    DOWNLOAD_URL="https://github.com/pmkol/mosdns-x/releases/download/${LATEST_TAG}/mosdns-x-linux-${ARCH}.zip"
    
    log_info "准备下载: ${DOWNLOAD_URL}"
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    wget -O "${TMP_DIR}/mosdns-x.zip" "${DOWNLOAD_URL}"
    if [ $? -ne 0 ]; then
        log_error "下载失败，请检查网络连接。"
    fi

    # 4. 解压并安装
    log_info "解压文件..."
    unzip -o "${TMP_DIR}/mosdns-x.zip" -d "${TMP_DIR}"
    if [ $? -ne 0 ]; then
        log_error "解压失败。"
    fi
    
    log_info "安装二进制文件到 ${INSTALL_PATH}/mosdns-x"
    install -m 755 "${TMP_DIR}/mosdns-x" "${INSTALL_PATH}/mosdns-x"

    # 5. 创建配置
    create_config_file

    # 6. 创建并启动服务
    create_systemd_service
    log_info "重载 systemd 服务..."
    systemctl daemon-reload
    log_info "设置 mosdns-x 开机自启..."
    systemctl enable mosdns-x
    log_info "启动 mosdns-x 服务..."
    systemctl start mosdns-x

    # 7. 清理临时文件
    log_info "清理临时文件..."
    rm -rf "${TMP_DIR}"
    
    # 8. 检查状态
    sleep 2
    SERVICE_STATUS=$(systemctl is-active mosdns-x)
    if [ "${SERVICE_STATUS}" = "active" ]; then
        log_info "mosdns-x 安装成功并已成功启动！"
        log_info "DNS 服务器正在监听: 127.0.0.1:5533 (TCP/UDP)"
        log_info "您可以通过 'systemctl status mosdns-x' 查看服务状态。"
    else
        log_error "mosdns-x 服务启动失败。请运行 'journalctl -u mosdns-x -n 50' 查看日志以排查问题。"
    fi
}

# 卸载 mosdns-x
do_uninstall() {
    log_info "开始卸载 mosdns-x..."

    # 1. 停止并禁用服务
    if [ -f "${SERVICE_PATH}" ]; then
        log_info "停止并禁用 mosdns-x 服务..."
        systemctl stop mosdns-x
        systemctl disable mosdns-x
    else
        log_warn "未找到 systemd 服务文件，跳过服务停止步骤。"
    fi

    # 2. 删除文件
    log_info "删除二进制文件: ${INSTALL_PATH}/mosdns-x"
    rm -f "${INSTALL_PATH}/mosdns-x"
    
    log_info "删除配置文件目录: ${CONFIG_PATH}"
    rm -rf "${CONFIG_PATH}"
    
    if [ -f "${SERVICE_PATH}" ]; then
        log_info "删除 systemd 服务文件: ${SERVICE_PATH}"
        rm -f "${SERVICE_PATH}"
        log_info "重载 systemd 服务..."
        systemctl daemon-reload
    fi
    
    log_info "mosdns-x 卸载完成。"
}

# 显示用法
show_usage() {
    echo "用法: $0 [install|uninstall|reinstall]"
    echo "  install    : 安装 mosdns-x"
    echo "  uninstall  : 卸载 mosdns-x"
    echo "  reinstall  : 重新安装 mosdns-x"
}

# --- 主逻辑 ---
main() {
    check_root
    
    case "$1" in
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        reinstall)
            log_info "开始重装 mosdns-x..."
            do_uninstall
            do_install
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
