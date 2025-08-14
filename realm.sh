#!/bin/bash

# Realm 一键安装配置脚本
# 支持系统: Ubuntu/Debian/CentOS/RHEL
# 作者: Auto Generated Script

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统架构
detect_arch() {
    case $(uname -m) in
        x86_64)
            ARCH="x86_64"
            ;;
        aarch64)
            ARCH="aarch64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            print_error "不支持的系统架构: $(uname -m)"
            exit 1
            ;;
    esac
    print_info "检测到系统架构: $ARCH"
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    print_info "检测到操作系统: $OS $VERSION"
}

# 安装依赖
install_dependencies() {
    print_info "安装依赖包..."
    case $OS in
        ubuntu|debian)
            apt update
            apt install -y wget curl tar systemd
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y wget curl tar systemd
            else
                yum install -y wget curl tar systemd
            fi
            ;;
        *)
            print_warning "未知操作系统，跳过依赖安装"
            ;;
    esac
}

# 获取最新版本
get_latest_version() {
    print_info "获取 Realm 最新版本信息..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then
        print_error "无法获取最新版本信息"
        exit 1
    fi
    print_success "最新版本: $LATEST_VERSION"
}

# 下载 Realm
download_realm() {
    print_info "下载 Realm $LATEST_VERSION..."
    
    # 构建下载URL
    case $ARCH in
        x86_64)
            DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}/realm-${ARCH}-unknown-linux-gnu.tar.gz"
            ;;
        aarch64)
            DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}/realm-${ARCH}-unknown-linux-gnu.tar.gz"
            ;;
        armv7)
            DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}/realm-${ARCH}-unknown-linux-gnueabihf.tar.gz"
            ;;
    esac
    
    # 下载文件
    cd /tmp
    wget -O realm.tar.gz "$DOWNLOAD_URL" || {
        print_error "下载失败"
        exit 1
    }
    
    # 解压文件
    tar -xzf realm.tar.gz || {
        print_error "解压失败"
        exit 1
    }
    
    print_success "下载完成"
}

# 安装 Realm
install_realm() {
    print_info "安装 Realm..."
    
    # 创建目录
    mkdir -p /usr/local/bin
    mkdir -p /etc/realm
    mkdir -p /var/log/realm
    
    # 复制可执行文件
    cp /tmp/realm /usr/local/bin/realm
    chmod +x /usr/local/bin/realm
    
    # 清理临时文件
    rm -f /tmp/realm.tar.gz /tmp/realm
    
    print_success "Realm 安装完成"
}

# 创建配置文件
create_config() {
    print_info "创建配置文件..."
    
    cat > /etc/realm/config.toml << 'EOF'
[log]
level = "warn"
output = "/var/log/realm/realm.log"

[[endpoints]]
listen = "0.0.0.0:1080"
remote = "8.8.8.8:53"

# 示例配置
# [[endpoints]]
# listen = "0.0.0.0:8080"
# remote = "example.com:80"

# [[endpoints]]
# listen = "[::]:9090"
# remote = "example.com:9090"
EOF

    print_success "配置文件创建完成: /etc/realm/config.toml"
}

# 创建systemd服务
create_service() {
    print_info "创建systemd服务..."
    
    cat > /etc/systemd/system/realm.service << 'EOF'
[Unit]
Description=Realm - A simple, high performance relay server written in rust
Documentation=https://github.com/zhboner/realm
After=network.target
Wants=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/realm -c /etc/realm/config.toml
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=5
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # 重载systemd配置
    systemctl daemon-reload
    
    print_success "systemd服务创建完成"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        print_info "检测到UFW防火墙"
        read -p "是否配置UFW防火墙规则? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ufw allow 1080/tcp
            print_success "UFW规则已添加"
        fi
    fi
    
    # firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd >/dev/null 2>&1; then
        print_info "检测到firewalld防火墙"
        read -p "是否配置firewalld规则? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            firewall-cmd --permanent --add-port=1080/tcp
            firewall-cmd --reload
            print_success "firewalld规则已添加"
        fi
    fi
}

# 显示使用方法
show_usage() {
    print_success "Realm 安装完成！"
    echo
    echo "配置文件位置: /etc/realm/config.toml"
    echo "日志文件位置: /var/log/realm/realm.log"
    echo
    echo "常用命令:"
    echo "  启动服务: systemctl start realm"
    echo "  停止服务: systemctl stop realm"
    echo "  重启服务: systemctl restart realm"
    echo "  查看状态: systemctl status realm"
    echo "  开机启动: systemctl enable realm"
    echo "  查看日志: journalctl -u realm -f"
    echo "  编辑配置: nano /etc/realm/config.toml"
    echo
    echo "配置文件说明:"
    echo "  - 默认监听端口: 1080"
    echo "  - 默认转发到: 8.8.8.8:53"
    echo "  - 请根据需要修改配置文件"
    echo
    print_warning "请记得修改配置文件后重启服务!"
}

# 主菜单
main_menu() {
    echo "================================="
    echo "    Realm 一键安装配置脚本"
    echo "================================="
    echo "1. 全新安装"
    echo "2. 更新 Realm"
    echo "3. 卸载 Realm"
    echo "4. 查看状态"
    echo "5. 重启服务"
    echo "6. 查看日志"
    echo "0. 退出"
    echo "================================="
    read -p "请选择操作 [0-6]: " choice

    case $choice in
        1)
            install_full
            ;;
        2)
            update_realm
            ;;
        3)
            uninstall_realm
            ;;
        4)
            check_status
            ;;
        5)
            restart_service
            ;;
        6)
            view_logs
            ;;
        0)
            exit 0
            ;;
        *)
            print_error "无效选择"
            main_menu
            ;;
    esac
}

# 完整安装
install_full() {
    print_info "开始安装 Realm..."
    detect_arch
    detect_os
    install_dependencies
    get_latest_version
    download_realm
    install_realm
    create_config
    create_service
    configure_firewall
    show_usage
    
    read -p "是否现在启动 Realm 服务? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start realm
        systemctl enable realm
        print_success "Realm 服务已启动并设置为开机启动"
    fi
}

# 更新 Realm
update_realm() {
    print_info "更新 Realm..."
    if [[ ! -f /usr/local/bin/realm ]]; then
        print_error "Realm 未安装"
        return
    fi
    
    systemctl stop realm 2>/dev/null || true
    detect_arch
    get_latest_version
    download_realm
    cp /tmp/realm /usr/local/bin/realm
    chmod +x /usr/local/bin/realm
    rm -f /tmp/realm.tar.gz /tmp/realm
    systemctl start realm
    print_success "Realm 更新完成"
}

# 卸载 Realm
uninstall_realm() {
    print_warning "这将完全卸载 Realm 及其所有配置文件"
    read -p "确定要卸载吗? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl stop realm 2>/dev/null || true
        systemctl disable realm 2>/dev/null || true
        rm -f /etc/systemd/system/realm.service
        rm -f /usr/local/bin/realm
        rm -rf /etc/realm
        rm -rf /var/log/realm
        systemctl daemon-reload
        print_success "Realm 已卸载"
    fi
}

# 查看状态
check_status() {
    if systemctl is-active --quiet realm; then
        print_success "Realm 服务正在运行"
        systemctl status realm --no-pager
    else
        print_warning "Realm 服务未运行"
        systemctl status realm --no-pager
    fi
}

# 重启服务
restart_service() {
    print_info "重启 Realm 服务..."
    systemctl restart realm
    print_success "服务已重启"
}

# 查看日志
view_logs() {
    print_info "显示 Realm 日志 (按 Ctrl+C 退出)..."
    journalctl -u realm -f --no-pager
}

# 主程序入口
main() {
    check_root
    
    # 如果没有参数，显示菜单
    if [[ $# -eq 0 ]]; then
        main_menu
    else
        case $1 in
            install)
                install_full
                ;;
            update)
                update_realm
                ;;
            uninstall)
                uninstall_realm
                ;;
            status)
                check_status
                ;;
            restart)
                restart_service
                ;;
            logs)
                view_logs
                ;;
            *)
                echo "用法: $0 [install|update|uninstall|status|restart|logs]"
                exit 1
                ;;
        esac
    fi
}

# 执行主程序
main "$@"
