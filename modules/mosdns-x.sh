#!/bin/bash

#================================================================================
# mosdns-x 一键安装脚本 for Debian 13 (已修复)
#
# 更新日志:
#   - 修复了 systemd 服务启动命令。新版本需要使用 'start' 子命令。
#   - 修复了因上游发布包内二进制文件名变更导致的安装失败问题。
#     脚本现在会自动查找名为 'mosdns' 的文件并将其安装为 'mosdns-x'。
#
# 功能:
#   - 自动检测并下载最新的 mosdns-x 版本
#   - 安装必要的依赖 (unzip)
#   - 创建配置文件目录和文件
#   - 使用您提供的配置写入 config.yaml
#   - 创建并启动 systemd 服务，实现开机自启
#   - 清理临时文件
#
# 使用方法:
#   1. 将此脚本保存为 .sh 文件, 例如: install_mosdns.sh
#   2. 给予执行权限: chmod +x install_mosdns.sh
#   3. 使用 root 权限运行: sudo ./install_mosdns.sh
#================================================================================

# --- 全局变量 ---
# 二进制文件安装路径
INSTALL_PATH="/usr/local/bin"
# 配置文件路径
CONFIG_PATH="/etc/mosdns-x"
# systemd 服务文件路径
SERVICE_PATH="/etc/systemd/system/mosdns-x.service"
# 临时下载目录
TMP_DIR=$(mktemp -d)

# --- 函数定义 ---

# 打印信息
echo_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

# 打印错误并退出
echo_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
    # 清理临时目录
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    exit 1
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "请使用 root 权限运行此脚本 (例如: sudo ./script.sh)"
    fi
}

# 安装依赖
install_dependencies() {
    echo_info "正在更新软件包列表并安装依赖 (unzip, curl)..."
    if ! apt-get update || ! apt-get install -y unzip curl; then
        echo_error "依赖安装失败，请检查您的网络连接和软件源设置。"
    fi
}

# 获取最新版本号和下载链接
get_latest_release() {
    echo_info "正在获取 mosdns-x 最新版本信息..."
    LATEST_RELEASE_URL="https://api.github.com/repos/pmkol/mosdns-x/releases/latest"
    
    # 使用 curl 获取 API 信息，并通过 grep 和 sed 筛选下载链接
    DOWNLOAD_URL=$(curl -s $LATEST_RELEASE_URL | grep "browser_download_url.*linux-amd64.zip" | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo_error "无法获取最新的 mosdns-x 下载链接。请检查网络或访问 https://github.com/pmkol/mosdns-x/releases 页面。"
    fi
    echo_info "成功获取下载链接: $DOWNLOAD_URL"
}

# 下载并安装
download_and_install() {
    echo_info "正在下载 mosdns-x..."
    if ! wget -q -O "$TMP_DIR/mosdns.zip" "$DOWNLOAD_URL"; then
        echo_error "下载失败，请检查网络。"
    fi
    
    echo_info "正在解压文件..."
    if ! unzip -q -o "$TMP_DIR/mosdns.zip" -d "$TMP_DIR"; then
        echo_error "解压失败。"
    fi
    
    # 查找解压后的可执行文件，它现在通常叫 'mosdns'
    SOURCE_EXEC_NAME="mosdns"
    if [ ! -f "$TMP_DIR/$SOURCE_EXEC_NAME" ]; then
        echo_error "在解压的文件中找不到名为 '$SOURCE_EXEC_NAME' 的可执行文件。"
    fi

    echo_info "正在安装 $SOURCE_EXEC_NAME 到 $INSTALL_PATH/mosdns-x..."
    # 安装时将其重命名为 mosdns-x 以保持脚本统一性
    if ! install -m 755 "$TMP_DIR/$SOURCE_EXEC_NAME" "$INSTALL_PATH/mosdns-x"; then
        echo_error "安装二进制文件失败。"
    fi
}

# 创建配置文件
create_config_file() {
    echo_info "正在创建配置文件到 $CONFIG_PATH/config.yaml..."
    mkdir -p "$CONFIG_PATH"
    
    # 使用 cat 和 EOF 创建配置文件
    cat > "$CONFIG_PATH/config.yaml" << EOF
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

    if [ $? -ne 0 ]; then
        echo_error "创建配置文件失败。"
    fi
}

# 创建 systemd 服务
create_systemd_service() {
    echo_info "正在创建 systemd 服务..."
    
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=mosdns-x - A DNS forwarder
Documentation=https://github.com/pmkol/mosdns-x/wiki
After=network.target

[Service]
Type=simple
# **[修复]** 新版本需要 'start' 子命令来运行
ExecStart=$INSTALL_PATH/mosdns-x start -c $CONFIG_PATH/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        echo_error "创建 systemd 服务文件失败。"
    fi
}

# 启动并设置开机自启
start_service() {
    echo_info "正在重载 systemd 并启动 mosdns-x 服务..."
    systemctl daemon-reload
    systemctl enable mosdns-x > /dev/null 2>&1
    systemctl restart mosdns-x
    
    # 等待一小会儿，然后检查状态
    sleep 2
    if systemctl is-active --quiet mosdns-x; then
        echo_info "mosdns-x 服务已成功启动！"
    else
        echo_error "mosdns-x 服务启动失败。请使用 'journalctl -u mosdns-x' 查看日志。"
    fi
}

# 清理工作
cleanup() {
    echo_info "正在清理临时文件..."
    rm -rf "$TMP_DIR"
}

# --- 主程序 ---
main() {
    # 确保在脚本退出时执行清理
    trap cleanup EXIT

    check_root
    install_dependencies
    get_latest_release
    download_and_install
    create_config_file
    create_systemd_service
    start_service
    
    echo_info "============================================================"
    echo_info "          mosdns-x 安装完成!"
    echo_info "  配置文件: $CONFIG_PATH/config.yaml"
    echo_info "  DNS 服务监听地址: 127.0.0.1:5533 (TCP/UDP)"
    echo_info "  常用命令:"
    echo_info "    - 启动服务: sudo systemctl start mosdns-x"
    echo_info "    - 停止服务: sudo systemctl stop mosdns-x"
    echo_info "    - 重启服务: sudo systemctl restart mosdns-x"
    echo_info "    - 查看状态: sudo systemctl status mosdns-x"
    echo_info "    - 查看日志: sudo journalctl -u mosdns-x -f"
    echo_info "============================================================"
}

# 执行主程序
main
