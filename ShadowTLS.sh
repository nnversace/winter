#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以root用户运行"
        exit 1
    fi
}

# 检查系统
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        error "不支持的操作系统"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    info "安装依赖..."
    
    if [[ "$OS" == "centos" ]]; then
        yum update -y
        yum install -y curl wget unzip
    else
        apt update -y
        apt install -y curl wget unzip
    fi
}

# 安装Docker
install_docker() {
    info "检查Docker状态..."
    
    if ! command -v docker &> /dev/null; then
        info "安装Docker..."
        if [[ "$OS" == "centos" ]]; then
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
        else
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update
            apt install -y docker-ce docker-ce-cli containerd.io
        fi
        
        systemctl start docker
        systemctl enable docker
        success "Docker 安装完成"
    else
        success "Docker 已存在"
    fi
}

# 安装Docker Compose
install_docker_compose() {
    info "检查Docker Compose状态..."
    
    if ! command -v docker-compose &> /dev/null; then
        info "安装Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        success "Docker Compose 安装完成"
    else
        success "Docker Compose 已存在"
    fi
}

# 创建配置目录
create_config_dir() {
    info "创建配置目录..."
    mkdir -p /opt/shadowtls
    cd /opt/shadowtls
}

# 生成随机密码
generate_password() {
    echo $(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
}

# 获取用户输入
get_user_input() {
    info "请输入配置信息:"
    
    read -p "请输入ShadowTLS监听端口 (默认: 443): " SHADOWTLS_PORT
    SHADOWTLS_PORT=${SHADOWTLS_PORT:-443}
    
    read -p "请输入Shadowsocks监听端口 (默认: 8388): " SS_PORT
    SS_PORT=${SS_PORT:-8388}
    
    read -p "请输入Shadowsocks密码 (回车自动生成): " SS_PASSWORD
    if [[ -z "$SS_PASSWORD" ]]; then
        SS_PASSWORD=$(generate_password)
        info "自动生成的密码: $SS_PASSWORD"
    fi
    
    read -p "请输入Shadowsocks加密方法 (默认: chacha20-ietf-poly1305): " SS_METHOD
    SS_METHOD=${SS_METHOD:-chacha20-ietf-poly1305}
    
    read -p "请输入TLS握手目标域名 (默认: www.bing.com): " TLS_TARGET
    TLS_TARGET=${TLS_TARGET:-www.bing.com}
    
    read -p "请输入ShadowTLS密码 (回车自动生成): " SHADOWTLS_PASSWORD
    if [[ -z "$SHADOWTLS_PASSWORD" ]]; then
        SHADOWTLS_PASSWORD=$(generate_password)
        info "自动生成的ShadowTLS密码: $SHADOWTLS_PASSWORD"
    fi
}

# 创建docker-compose.yml
create_docker_compose() {
    info "创建Docker Compose配置..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  shadowsocks:
    image: shadowsocks/shadowsocks-libev:latest
    container_name: shadowsocks
    restart: unless-stopped
    ports:
      - "127.0.0.1:${SS_PORT}:${SS_PORT}"
    environment:
      - METHOD=${SS_METHOD}
      - PASSWORD=${SS_PASSWORD}
      - SERVER_PORT=${SS_PORT}
    command: ss-server -s 0.0.0.0 -p ${SS_PORT} -k ${SS_PASSWORD} -m ${SS_METHOD} -u
    networks:
      - shadowtls_network

  shadowtls:
    image: ihciah/shadow-tls:latest
    container_name: shadowtls
    restart: unless-stopped
    ports:
      - "${SHADOWTLS_PORT}:${SHADOWTLS_PORT}"
    environment:
      - RUST_LOG=info
    command: shadow-tls --v3 server --listen 0.0.0.0:${SHADOWTLS_PORT} --server 127.0.0.1:${SS_PORT} --tls ${TLS_TARGET}:443 --password ${SHADOWTLS_PASSWORD}
    depends_on:
      - shadowsocks
    networks:
      - shadowtls_network

networks:
  shadowtls_network:
    driver: bridge
EOF
    
    success "Docker Compose 配置已创建"
}

# 启动服务
start_service() {
    info "启动 ShadowTLS 服务..."
    
    docker-compose down 2>/dev/null
    docker-compose up -d
    
    if [[ $? -eq 0 ]]; then
        success "ShadowTLS 服务启动成功"
    else
        error "ShadowTLS 服务启动失败"
        exit 1
    fi
}

# 显示配置信息
show_config() {
    echo ""
    echo "==================== ShadowTLS 配置信息 ===================="
    echo "服务器地址: $(curl -s ifconfig.me)"
    echo "ShadowTLS端口: $SHADOWTLS_PORT"
    echo "ShadowTLS密码: $SHADOWTLS_PASSWORD"
    echo "Shadowsocks端口: $SS_PORT"
    echo "Shadowsocks密码: $SS_PASSWORD"
    echo "Shadowsocks加密方法: $SS_METHOD"
    echo "TLS握手目标: $TLS_TARGET"
    echo "=============================================================="
    echo ""
    echo "客户端配置示例:"
    echo "shadow-tls --v3 client --listen 127.0.0.1:1080 --server $(curl -s ifconfig.me):$SHADOWTLS_PORT --tls $TLS_TARGET:443 --password $SHADOWTLS_PASSWORD"
    echo ""
}

# 保存配置
save_config() {
    info "保存配置到文件..."
    
    cat > shadowtls_config.txt << EOF
ShadowTLS 配置信息
==================
服务器地址: $(curl -s ifconfig.me)
ShadowTLS端口: $SHADOWTLS_PORT
ShadowTLS密码: $SHADOWTLS_PASSWORD
Shadowsocks端口: $SS_PORT
Shadowsocks密码: $SS_PASSWORD
Shadowsocks加密方法: $SS_METHOD
TLS握手目标: $TLS_TARGET

客户端配置命令:
shadow-tls --v3 client --listen 127.0.0.1:1080 --server $(curl -s ifconfig.me):$SHADOWTLS_PORT --tls $TLS_TARGET:443 --password $SHADOWTLS_PASSWORD
EOF
    
    success "配置已保存到 shadowtls_config.txt"
}

# 管理菜单
show_menu() {
    echo ""
    echo "==================== ShadowTLS 管理菜单 ===================="
    echo "1. 安装 ShadowTLS"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看状态"
    echo "6. 查看日志"
    echo "7. 卸载 ShadowTLS"
    echo "0. 退出"
    echo "=============================================================="
}

# 查看服务状态
check_status() {
    info "检查服务状态..."
    cd /opt/shadowtls
    docker-compose ps
}

# 查看日志
view_logs() {
    info "查看服务日志..."
    cd /opt/shadowtls
    docker-compose logs -f
}

# 停止服务
stop_service() {
    info "停止服务..."
    cd /opt/shadowtls
    docker-compose down
    success "服务已停止"
}

# 重启服务
restart_service() {
    info "重启服务..."
    cd /opt/shadowtls
    docker-compose restart
    success "服务已重启"
}

# 卸载服务
uninstall_service() {
    warning "确定要卸载 ShadowTLS 吗？这将删除所有配置文件。"
    read -p "输入 'yes' 确认卸载: " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        info "卸载 ShadowTLS..."
        cd /opt/shadowtls
        docker-compose down
        docker rmi shadowsocks/shadowsocks-libev:latest ihciah/shadow-tls:latest 2>/dev/null
        cd /
        rm -rf /opt/shadowtls
        success "ShadowTLS 已卸载"
    else
        info "取消卸载"
    fi
}

# 主安装流程
install_shadowtls() {
    check_root
    check_system
    install_dependencies
    install_docker
    install_docker_compose
    create_config_dir
    get_user_input
    create_docker_compose
    start_service
    show_config
    save_config
}

# 主程序
main() {
    if [[ $1 == "install" ]]; then
        install_shadowtls
    else
        while true; do
            show_menu
            read -p "请选择操作: " choice
            
            case $choice in
                1)
                    install_shadowtls
                    ;;
                2)
                    start_service
                    ;;
                3)
                    stop_service
                    ;;
                4)
                    restart_service
                    ;;
                5)
                    check_status
                    ;;
                6)
                    view_logs
                    ;;
                7)
                    uninstall_service
                    ;;
                0)
                    info "退出脚本"
                    exit 0
                    ;;
                *)
                    warning "无效选择，请重新输入"
                    ;;
            esac
        done
    fi
}

# 运行主程序
main "$@"
