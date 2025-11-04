#!/bin/bash

# Caddy 一键安装配置脚本 - 反向代理 localhost:4173
# 支持系统: Ubuntu/Debian
# 功能: 自动安装 Caddy、配置反向代理、设置 systemd 服务

set -e
set -o pipefail

# --- 全局变量和常量 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CADDY_CONFIG_DIR="/etc/caddy"
CADDY_CONFIG_FILE="${CADDY_CONFIG_DIR}/Caddyfile"
CADDY_SERVICE_FILE="/etc/systemd/system/caddy.service"
CADDY_DATA_DIR="/var/lib/caddy"
CADDY_LOG_DIR="/var/log/caddy"

# 默认配置
DEFAULT_LISTEN_PORT="80"
DEFAULT_UPSTREAM="localhost:4173"

# --- 基础函数 ---

# 统一格式化输出
print_msg() {
    local color=$1
    local level=$2
    local message=$3
    echo -e "${color}[${level}]${NC} ${message}"
}

print_info() {
    print_msg "${BLUE}" "INFO" "$1"
}

print_success() {
    print_msg "${GREEN}" "SUCCESS" "$1"
}

print_warning() {
    print_msg "${YELLOW}" "WARNING" "$1"
}

print_error() {
    print_msg "${RED}" "ERROR" "$1" >&2
}

# --- 核心功能函数 ---

# 检查脚本是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请尝试使用: sudo $0"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        print_info "检测到操作系统: $OS $OS_VERSION"
    else
        print_error "无法检测到操作系统"
        exit 1
    fi

    # 检查是否为 Debian/Ubuntu 系列
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "此脚本主要针对 Ubuntu/Debian 系统优化"
        print_warning "其他系统可能需要手动调整"
    fi
}

# 安装 Caddy
install_caddy() {
    print_info "开始安装 Caddy..."
    
    # 检查是否已安装
    if command -v caddy >/dev/null 2>&1; then
        local installed_version
        installed_version=$(caddy version | head -n1)
        print_warning "Caddy 已安装: $installed_version"
        read -p "是否继续重新安装/更新? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "跳过 Caddy 安装"
            return
        fi
    fi

    # 安装依赖
    print_info "安装依赖包..."
    apt-get update -y
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl

    # 添加 Caddy 官方源
    print_info "添加 Caddy 官方 APT 源..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list

    # 安装 Caddy
    print_info "安装 Caddy..."
    apt-get update -y
    apt-get install -y caddy

    print_success "Caddy 安装完成"
    caddy version
}

# 创建配置目录
create_directories() {
    print_info "创建必要的目录..."
    mkdir -p "$CADDY_CONFIG_DIR"
    mkdir -p "$CADDY_DATA_DIR"
    mkdir -p "$CADDY_LOG_DIR"
    print_success "目录创建完成"
}

# 创建 Caddyfile 配置
create_config() {
    print_info "创建 Caddy 配置文件..."
    
    echo "====================================="
    echo "请选择反向代理配置模式:"
    echo "====================================="
    echo "1. HTTP 模式 - 监听指定端口 (默认:80)"
    echo "2. HTTPS 模式 - 使用域名和自动 HTTPS"
    echo "3. 自定义配置"
    echo "====================================="
    read -p "请输入您的选择 [1-3] (默认:1): " config_mode
    config_mode=${config_mode:-1}

    case $config_mode in
        1)
            create_http_config
            ;;
        2)
            create_https_config
            ;;
        3)
            create_custom_config
            ;;
        *)
            print_error "无效的选择"
            exit 1
            ;;
    esac
}

# 创建 HTTP 配置
create_http_config() {
    read -p "请输入监听端口 (默认: 80): " listen_port
    listen_port=${listen_port:-$DEFAULT_LISTEN_PORT}
    
    read -p "请输入后端地址 (默认: localhost:4173): " upstream
    upstream=${upstream:-$DEFAULT_UPSTREAM}

    cat > "$CADDY_CONFIG_FILE" << EOF
# Caddy 反向代理配置 - HTTP 模式
# 监听端口: ${listen_port}
# 后端服务: ${upstream}

:${listen_port} {
    # 反向代理到后端服务
    reverse_proxy ${upstream}

    # 日志配置
    log {
        output file ${CADDY_LOG_DIR}/access.log
        format json
    }

    # 请求头配置
    header {
        # 安全头
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "no-referrer-when-downgrade"
        
        # 隐藏服务器信息
        -Server
    }
}
EOF

    print_success "HTTP 配置文件创建成功: $CADDY_CONFIG_FILE"
    print_info "访问地址: http://YOUR_SERVER_IP:${listen_port}"
}

# 创建 HTTPS 配置
create_https_config() {
    read -p "请输入您的域名 (例如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        exit 1
    fi
    
    read -p "请输入后端地址 (默认: localhost:4173): " upstream
    upstream=${upstream:-$DEFAULT_UPSTREAM}
    
    read -p "请输入您的邮箱 (用于 Let's Encrypt 证书申请): " email

    cat > "$CADDY_CONFIG_FILE" << EOF
# Caddy 反向代理配置 - HTTPS 模式
# 域名: ${domain}
# 后端服务: ${upstream}
# 自动 HTTPS: 启用 (Let's Encrypt)

${domain} {
    # 反向代理到后端服务
    reverse_proxy ${upstream}

    # 日志配置
    log {
        output file ${CADDY_LOG_DIR}/access.log
        format json
    }

    # 请求头配置
    header {
        # 安全头
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "no-referrer-when-downgrade"
        
        # 隐藏服务器信息
        -Server
    }

    # TLS 配置
    tls ${email}
}
EOF

    print_success "HTTPS 配置文件创建成功: $CADDY_CONFIG_FILE"
    print_warning "请确保域名 ${domain} 已正确解析到此服务器"
    print_info "访问地址: https://${domain}"
}

# 创建自定义配置
create_custom_config() {
    read -p "请输入完整的监听地址 (例如: :8080 或 example.com): " listen_addr
    
    if [[ -z "$listen_addr" ]]; then
        print_error "监听地址不能为空"
        exit 1
    fi
    
    read -p "请输入后端地址 (默认: localhost:4173): " upstream
    upstream=${upstream:-$DEFAULT_UPSTREAM}

    cat > "$CADDY_CONFIG_FILE" << EOF
# Caddy 反向代理配置 - 自定义模式
# 监听地址: ${listen_addr}
# 后端服务: ${upstream}

${listen_addr} {
    # 反向代理到后端服务
    reverse_proxy ${upstream}

    # 日志配置
    log {
        output file ${CADDY_LOG_DIR}/access.log
        format json
    }

    # 请求头配置
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        -Server
    }
}
EOF

    print_success "自定义配置文件创建成功: $CADDY_CONFIG_FILE"
}

# 验证配置文件
validate_config() {
    print_info "验证配置文件..."
    if caddy validate --config "$CADDY_CONFIG_FILE" --adapter caddyfile; then
        print_success "配置文件验证通过"
    else
        print_error "配置文件验证失败，请检查配置"
        exit 1
    fi
}

# 设置权限
set_permissions() {
    print_info "设置文件和目录权限..."
    
    # 配置目录权限
    chown -R root:root "$CADDY_CONFIG_DIR"
    chmod 755 "$CADDY_CONFIG_DIR"
    chmod 644 "$CADDY_CONFIG_FILE"
    
    # 数据目录权限 (Caddy 需要写入权限用于证书存储)
    chown -R caddy:caddy "$CADDY_DATA_DIR" 2>/dev/null || chown -R www-data:www-data "$CADDY_DATA_DIR"
    chmod 755 "$CADDY_DATA_DIR"
    
    # 日志目录权限
    chown -R caddy:caddy "$CADDY_LOG_DIR" 2>/dev/null || chown -R www-data:www-data "$CADDY_LOG_DIR"
    chmod 755 "$CADDY_LOG_DIR"
    
    print_success "权限设置完成"
}

# 创建或更新 systemd 服务
create_service() {
    print_info "配置 systemd 服务..."
    
    # Caddy 通常自带 systemd 服务文件，我们检查是否存在
    if [[ -f /lib/systemd/system/caddy.service ]]; then
        print_info "使用 Caddy 自带的 systemd 服务文件"
    else
        # 创建自定义服务文件
        cat > "$CADDY_SERVICE_FILE" << 'EOF'
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
        print_info "已创建自定义 systemd 服务文件"
    fi
    
    systemctl daemon-reload
    print_success "systemd 服务配置完成"
}

# 显示使用说明
show_usage() {
    print_success "Caddy 反向代理配置完成！"
    echo
    echo "=============================================="
    echo -e "配置文件: ${YELLOW}${CADDY_CONFIG_FILE}${NC}"
    echo -e "日志目录: ${YELLOW}${CADDY_LOG_DIR}${NC}"
    echo -e "数据目录: ${YELLOW}${CADDY_DATA_DIR}${NC}"
    echo "=============================================="
    echo
    echo "常用命令:"
    echo "  systemctl start caddy      # 启动服务"
    echo "  systemctl stop caddy       # 停止服务"
    echo "  systemctl restart caddy    # 重启服务"
    echo "  systemctl status caddy     # 查看状态"
    echo "  systemctl enable caddy     # 设置开机启动"
    echo "  systemctl reload caddy     # 重载配置 (无中断)"
    echo "  journalctl -u caddy -f     # 实时查看日志"
    echo "  caddy validate --config ${CADDY_CONFIG_FILE} --adapter caddyfile  # 验证配置"
    echo
    echo "配置文件修改后重载:"
    echo "  sudo systemctl reload caddy"
    echo
    print_info "查看当前配置:"
    echo "  cat ${CADDY_CONFIG_FILE}"
}

# 卸载 Caddy
uninstall_caddy() {
    print_warning "这将停止 Caddy 服务并删除配置文件 (但保留 Caddy 二进制程序)"
    read -p "您确定要继续吗? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return
    fi
    
    print_info "停止并禁用 Caddy 服务..."
    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    
    print_info "删除配置文件..."
    rm -rf "$CADDY_CONFIG_DIR"
    rm -rf "$CADDY_LOG_DIR"
    
    read -p "是否同时删除 Caddy 程序? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get remove -y caddy
        apt-get autoremove -y
        rm -rf "$CADDY_DATA_DIR"
        print_success "Caddy 已完全卸载"
    else
        print_success "已删除配置文件，Caddy 程序保留"
    fi
}

# 完整安装流程
do_install() {
    print_info "开始 Caddy 反向代理安装配置..."
    
    detect_os
    install_caddy
    create_directories
    create_config
    validate_config
    set_permissions
    create_service
    show_usage
    
    echo
    read -p "是否立即启动 Caddy 并设置开机自启? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl enable caddy
        systemctl start caddy
        print_success "Caddy 服务已启动并设为开机自启"
        echo
        systemctl status caddy --no-pager
    else
        print_info "您可以稍后使用以下命令启动: systemctl start caddy"
    fi
}

# 重新配置
do_reconfigure() {
    print_info "重新配置 Caddy..."
    
    if [[ ! -f "$CADDY_CONFIG_FILE" ]]; then
        print_warning "配置文件不存在，将创建新配置"
        create_directories
    else
        # 备份旧配置
        local backup_file="${CADDY_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CADDY_CONFIG_FILE" "$backup_file"
        print_info "旧配置已备份到: $backup_file"
    fi
    
    create_config
    validate_config
    set_permissions
    
    read -p "是否重启 Caddy 服务以应用新配置? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl reload caddy || systemctl restart caddy
        print_success "配置已重载"
        systemctl status caddy --no-pager
    fi
}

# --- 主逻辑 ---

main() {
    check_root
    
    if [[ $# -gt 0 ]]; then
        case $1 in
            install) do_install ;;
            reconfigure|reconfig) do_reconfigure ;;
            uninstall) uninstall_caddy ;;
            *) 
                echo "用法: $0 [install|reconfigure|uninstall]"
                exit 1
                ;;
        esac
        exit 0
    fi

    echo "==========================================="
    echo "  Caddy 反向代理配置脚本"
    echo "  目标服务: localhost:4173"
    echo "==========================================="
    echo "1. 安装并配置 Caddy"
    echo "2. 重新配置 Caddy"
    echo "3. 卸载配置"
    echo "-------------------------------------------"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 重启服务"
    echo "7. 重载配置"
    echo "8. 查看状态"
    echo "9. 查看日志"
    echo "10. 验证配置"
    echo "0. 退出脚本"
    echo "==========================================="
    read -p "请输入您的选择 [0-10]: " choice

    case $choice in
        1) do_install ;;
        2) do_reconfigure ;;
        3) uninstall_caddy ;;
        4) systemctl start caddy && print_success "服务已启动" ;;
        5) systemctl stop caddy && print_success "服务已停止" ;;
        6) systemctl restart caddy && print_success "服务已重启" ;;
        7) systemctl reload caddy && print_success "配置已重载" ;;
        8) systemctl status caddy --no-pager ;;
        9) journalctl -u caddy -f ;;
        10) caddy validate --config "$CADDY_CONFIG_FILE" --adapter caddyfile ;;
        0) exit 0 ;;
        *) print_error "无效输入！" ;;
    esac
}

# 脚本执行入口
main "$@"
