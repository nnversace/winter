#!/bin/bash

# Mosdns-x 一键安装脚本
# 适用于 Linux 系统
# 作者: 基于 pmkol/mosdns-x 项目制作

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="pmkol/mosdns-x"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/mosdns"
SERVICE_NAME="mosdns"
LATEST_VERSION=""

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            exit 1
            ;;
    esac
}

# 检查系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo $ID
    else
        echo "unknown"
    fi
}

# 安装必要的依赖
install_dependencies() {
    log_info "安装必要的依赖包..."
    
    local os=$(detect_os)
    case $os in
        ubuntu|debian)
            apt update
            apt install -y curl wget tar unzip systemd
            ;;
        centos|rhel|fedora|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget tar unzip systemd
            else
                yum install -y curl wget tar unzip systemd
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm curl wget tar unzip systemd
            ;;
        *)
            log_warning "未知的操作系统，请手动安装: curl, wget, tar, unzip, systemd"
            ;;
    esac
}

# 获取最新版本号
get_latest_version() {
    log_info "获取最新版本信息..."
    
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
                     grep '"tag_name"' | \
                     sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_VERSION" ]]; then
        log_error "无法获取最新版本信息"
        exit 1
    fi
    
    log_success "最新版本: $LATEST_VERSION"
}

# 下载 mosdns-x 二进制文件
download_mosdns() {
    local arch=$(detect_arch)
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$LATEST_VERSION/mosdns-linux-$arch.zip"
    
    log_info "下载 mosdns-x $LATEST_VERSION for linux-$arch..."
    
    # 检查 unzip 命令是否存在
    if ! command -v unzip &> /dev/null; then
        log_error "unzip 命令未找到，正在尝试安装..."
        local os=$(detect_os)
        case $os in
            ubuntu|debian)
                apt install -y unzip
                ;;
            centos|rhel|fedora|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf install -y unzip
                else
                    yum install -y unzip
                fi
                ;;
            arch|manjaro)
                pacman -S --noconfirm unzip
                ;;
            *)
                log_error "请手动安装 unzip 命令后重试"
                exit 1
                ;;
        esac
    fi
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 下载文件
    if ! wget -q --show-progress "$download_url" -O "mosdns-linux-$arch.zip"; then
        log_error "下载失败，请检查网络连接"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 解压文件
    unzip -q "mosdns-linux-$arch.zip"
    
    # 移动二进制文件到目标目录
    chmod +x mosdns
    mv mosdns "$INSTALL_DIR/"
    
    log_success "mosdns-x 二进制文件安装完成"
    
    # 清理临时文件
    rm -rf "$temp_dir"
}

# 创建配置目录和基本配置文件
create_config() {
    log_info "创建配置目录和基本配置文件..."
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 创建基本配置文件
    cat > "$CONFIG_DIR/config.yaml" << 'EOF'
log:
  level: info
  file: "/var/log/mosdns.log"

include: []

plugins:
  # 缓存
  - tag: cache
    type: cache
    args:
      size: 8192

  # DNS上游
  - tag: forward
    type: fast_forward
    args:
      upstream:
        - addr: "8.8.8.8"
        - addr: "1.1.1.1"

  # 主序列
  - tag: main_sequence
    type: sequence
    args:
      exec:
        - cache
        - forward

servers:
  - exec: main_sequence
    listeners:
      - protocol: udp
        addr: "0.0.0.0:53"
      - protocol: tcp
        addr: "0.0.0.0:53"
EOF

    log_success "基本配置文件创建完成"
}

# 创建系统服务文件
create_systemd_service() {
    log_info "创建 systemd 服务文件..."
    
    cat > "/etc/systemd/system/mosdns.service" << EOF
[Unit]
Description=Mosdns-x DNS Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/mosdns start -c $CONFIG_DIR/config.yaml -d $CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "systemd 服务文件创建完成"
}

# 启动服务
start_service() {
    log_info "启动 mosdns 服务..."
    
    systemctl enable mosdns
    systemctl start mosdns
    
    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet mosdns; then
        log_success "mosdns 服务启动成功"
    else
        log_error "mosdns 服务启动失败"
        log_info "请检查配置文件或运行: journalctl -u mosdns -f"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    # 检查并配置 ufw (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        ufw allow 53/udp
        ufw allow 53/tcp
        log_success "ufw 防火墙规则已配置"
    fi
    
    # 检查并配置 firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=53/udp
        firewall-cmd --permanent --add-port=53/tcp
        firewall-cmd --reload
        log_success "firewalld 防火墙规则已配置"
    fi
    
    # 检查并配置 iptables
    if command -v iptables &> /dev/null && ! command -v ufw &> /dev/null && ! systemctl is-active --quiet firewalld; then
        iptables -A INPUT -p udp --dport 53 -j ACCEPT
        iptables -A INPUT -p tcp --dport 53 -j ACCEPT
        log_success "iptables 防火墙规则已配置"
        log_warning "请注意保存 iptables 规则以确保重启后生效"
    fi
}

# 显示安装后信息
show_completion_info() {
    echo
    log_success "mosdns-x 安装完成！"
    echo
    echo "=========================================="
    echo -e "${GREEN}安装信息:${NC}"
    echo "  二进制文件: $INSTALL_DIR/mosdns"
    echo "  配置目录: $CONFIG_DIR"
    echo "  配置文件: $CONFIG_DIR/config.yaml"
    echo "  日志文件: /var/log/mosdns.log"
    echo
    echo -e "${GREEN}常用命令:${NC}"
    echo "  启动服务: systemctl start mosdns"
    echo "  停止服务: systemctl stop mosdns"
    echo "  重启服务: systemctl restart mosdns"
    echo "  查看状态: systemctl status mosdns"
    echo "  查看日志: journalctl -u mosdns -f"
    echo "  测试DNS: nslookup google.com 127.0.0.1"
    echo
    echo -e "${GREEN}配置文件:${NC}"
    echo "  编辑配置: nano $CONFIG_DIR/config.yaml"
    echo "  重载配置: systemctl reload mosdns"
    echo
    echo -e "${GREEN}版本信息:${NC}"
    echo "  当前版本: $LATEST_VERSION"
    echo "  检查版本: $INSTALL_DIR/mosdns version"
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. 默认监听 53 端口，请确保没有其他DNS服务占用"
    echo "  2. 可根据需要修改配置文件 $CONFIG_DIR/config.yaml"
    echo "  3. 配置文件详细说明请参考: https://github.com/pmkol/mosdns-x/wiki"
    echo "=========================================="
}

# 卸载功能
uninstall() {
    log_info "卸载 mosdns-x..."
    
    # 停止并禁用服务
    if systemctl is-active --quiet mosdns; then
        systemctl stop mosdns
    fi
    
    if systemctl is-enabled --quiet mosdns 2>/dev/null; then
        systemctl disable mosdns
    fi
    
    # 删除服务文件
    rm -f /etc/systemd/system/mosdns.service
    systemctl daemon-reload
    
    # 删除二进制文件
    rm -f "$INSTALL_DIR/mosdns"
    
    # 询问是否删除配置文件
    read -p "是否删除配置文件? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f /var/log/mosdns.log
        log_success "配置文件已删除"
    fi
    
    log_success "mosdns-x 卸载完成"
}

# 显示帮助信息
show_help() {
    echo "Mosdns-x 一键安装脚本"
    echo
    echo "用法:"
    echo "  $0 [选项]"
    echo
    echo "选项:"
    echo "  install     安装 mosdns-x (默认)"
    echo "  uninstall   卸载 mosdns-x"
    echo "  help        显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0                 # 安装 mosdns-x"
    echo "  $0 install         # 安装 mosdns-x" 
    echo "  $0 uninstall       # 卸载 mosdns-x"
}

# 主函数
main() {
    case "${1:-install}" in
        install)
            log_info "开始安装 mosdns-x..."
            check_root
            install_dependencies
            get_latest_version
            download_mosdns
            create_config
            create_systemd_service
            start_service
            configure_firewall
            show_completion_info
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
