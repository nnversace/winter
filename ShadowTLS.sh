#!/bin/bash

# ShadowTLS 一键部署脚本
# 作者: Auto Generated
# 版本: 1.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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

# 检查系统
check_system() {
    print_info "检查系统环境..."
    
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 用户运行此脚本"
        exit 1
    fi
    
    # 检查系统版本
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        print_info "检测到系统: $OS $VER"
    else
        print_error "无法检测系统版本"
        exit 1
    fi
}

# 安装 Docker 和 Docker Compose
install_docker() {
    print_info "检查 Docker 安装状态..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装"
    else
        print_info "安装 Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl start docker
        systemctl enable docker
        print_success "Docker 安装完成"
    fi
    
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose 已安装"
    else
        print_info "安装 Docker Compose..."
        if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
            apt-get update
            apt-get install -y docker-compose-plugin
        elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
            yum install -y docker-compose-plugin
        else
            # 通用安装方法
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        print_success "Docker Compose 安装完成"
    fi
}

# 生成随机密码
generate_password() {
    openssl rand -base64 24
}

# 配置参数
configure_shadowtls() {
    print_info "配置 ShadowTLS 参数..."
    
    echo
    echo "请输入配置参数（按回车使用默认值）："
    echo
    
    # 监听端口
    read -p "监听端口 [默认: 8443]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-8443}
    
    # 后端服务器地址
    read -p "后端服务器地址 [默认: 127.0.0.1:52171]: " SERVER_ADDR
    SERVER_ADDR=${SERVER_ADDR:-127.0.0.1:52171}
    
    # TLS 伪装域名
    echo "选择 TLS 伪装域名："
    echo "1. gateway.icloud.com:443 (默认)"
    echo "2. www.bing.com:443"
    echo "3. www.microsoft.com:443"
    echo "4. www.cloudflare.com:443"
    echo "5. 自定义"
    read -p "请选择 [1-5]: " TLS_CHOICE
    
    case $TLS_CHOICE in
        2)
            TLS_DOMAIN="www.bing.com:443"
            ;;
        3)
            TLS_DOMAIN="www.microsoft.com:443"
            ;;
        4)
            TLS_DOMAIN="www.cloudflare.com:443"
            ;;
        5)
            read -p "请输入自定义域名:端口: " TLS_DOMAIN
            ;;
        *)
            TLS_DOMAIN="gateway.icloud.com:443"
            ;;
    esac
    
    # 密码
    read -p "设置密码 [留空自动生成]: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(generate_password)
        print_info "自动生成密码: $PASSWORD"
    fi
    
    # 确认配置
    echo
    print_info "配置确认："
    echo "监听端口: $LISTEN_PORT"
    echo "后端服务器: $SERVER_ADDR"
    echo "TLS 伪装域名: $TLS_DOMAIN"
    echo "密码: $PASSWORD"
    echo
    
    read -p "确认配置无误？(y/n): " CONFIRM
    if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
        print_warning "配置已取消"
        exit 1
    fi
}

# 创建 Docker Compose 配置
create_docker_compose() {
    print_info "创建 Docker Compose 配置..."
    
    mkdir -p /opt/shadowtls
    cd /opt/shadowtls
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  shadow-tls:
    image: ghcr.io/ihciah/shadow-tls:latest
    container_name: shadow-tls
    restart: always
    network_mode: "host"
    environment:
      - MODE=server
      - LISTEN=::0:${LISTEN_PORT}
      - SERVER=${SERVER_ADDR}
      - TLS=${TLS_DOMAIN}
      - PASSWORD=${PASSWORD}
      - V3=1
      # - RUST_LOG=error
    security_opt:
      - seccomp:unconfined
EOF
    
    print_success "Docker Compose 配置已创建"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # 检查防火墙状态
    if command -v ufw &> /dev/null; then
        ufw allow ${LISTEN_PORT}
        print_success "UFW 防火墙规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${LISTEN_PORT}/tcp
        firewall-cmd --reload
        print_success "Firewalld 防火墙规则已添加"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport ${LISTEN_PORT} -j ACCEPT
        # 尝试保存 iptables 规则
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        print_success "Iptables 防火墙规则已添加"
    else
        print_warning "未检测到防火墙，请手动开放端口 ${LISTEN_PORT}"
    fi
}

# 启动服务
start_service() {
    print_info "启动 ShadowTLS 服务..."
    
    cd /opt/shadowtls
    docker-compose down 2>/dev/null || true
    docker-compose pull
    docker-compose up -d
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        print_success "ShadowTLS 服务启动成功"
    else
        print_error "ShadowTLS 服务启动失败"
        print_info "查看日志："
        docker-compose logs
        exit 1
    fi
}

# 生成客户端配置
generate_client_config() {
    print_info "生成客户端配置..."
    
    # 获取服务器 IP
    SERVER_IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    
    cat > /opt/shadowtls/client-config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080
    }
  ],
  "outbounds": [
    {
      "type": "shadowtls",
      "tag": "shadowtls-out",
      "server": "${SERVER_IP}",
      "server_port": ${LISTEN_PORT},
      "version": 3,
      "password": "${PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${TLS_DOMAIN%%:*}",
        "alpn": ["h2", "http/1.1"]
      },
      "detour": "direct"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "shadowtls-out"
  }
}
EOF
    
    print_success "客户端配置已保存到 /opt/shadowtls/client-config.json"
}

# 显示连接信息
show_connection_info() {
    SERVER_IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo
    echo "=========================================="
    print_success "ShadowTLS 部署完成！"
    echo "=========================================="
    echo
    echo "服务器信息："
    echo "  IP 地址: ${SERVER_IP}"
    echo "  端口: ${LISTEN_PORT}"
    echo "  密码: ${PASSWORD}"
    echo "  TLS 域名: ${TLS_DOMAIN}"
    echo "  协议版本: v3"
    echo
    echo "客户端配置文件: /opt/shadowtls/client-config.json"
    echo
    echo "管理命令："
    echo "  启动服务: cd /opt/shadowtls && docker-compose up -d"
    echo "  停止服务: cd /opt/shadowtls && docker-compose down"
    echo "  查看日志: cd /opt/shadowtls && docker-compose logs -f"
    echo "  重启服务: cd /opt/shadowtls && docker-compose restart"
    echo
    echo "=========================================="
}

# 主函数
main() {
    echo "========================================"
    echo "    ShadowTLS 一键部署脚本"
    echo "========================================"
    echo
    
    check_system
    install_docker
    configure_shadowtls
    create_docker_compose
    configure_firewall
    start_service
    generate_client_config
    show_connection_info
    
    print_success "部署完成！"
}

# 运行主函数
main "$@"
