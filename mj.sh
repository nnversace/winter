#!/bin/bash

# ==============================================================================
# 一键部署 chatgpt-web-midjourney-proxy 项目脚本
#
# 适配系统: Debian 13 (Trixie)
# 脚本作者: Gemini
#
# 功能:
#   - 安装系统依赖 (Git, Curl, Nginx, Certbot)
#   - 自动安装 Docker 和 Docker Compose
#   - 克隆最新的项目代码
#   - 引导用户完成 .env 文件的基本配置
#   - 使用 Docker Compose 启动服务
#   - 配置 Nginx 反向代理和 SSL 证书 (HTTPS)
# ==============================================================================

# --- 配置变量 ---
# 项目将被安装到这个目录
PROJECT_DIR="/opt/chatgpt-web-midjourney-proxy"
# 项目的 Git 仓库地址
REPO_URL="https://github.com/Dooy/chatgpt-web-midjourney-proxy.git"

# --- 颜色定义 ---
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# --- 辅助函数 ---

# 打印信息
# 参数1: 消息类型 (info, success, warning, error)
# 参数2: 消息内容
function print_message() {
    case "$1" in
        "info")    echo -e "[${YELLOW}INFO${NC}] $2" ;;
        "success") echo -e "[${GREEN}SUCCESS${NC}] $2" ;;
        "warning") echo -e "[${YELLOW}WARNING${NC}] $2" ;;
        "error")   echo -e "[${RED}ERROR${NC}] $2" >&2 ;;
    esac
}

# 检查是否以 root 身份运行
function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_message "error" "此脚本必须以 root 身份运行。请使用 'sudo bash $0'。"
        exit 1
    fi
}

# 安装系统基础依赖
function install_dependencies() {
    print_message "info" "正在更新系统软件包并安装基础依赖..."
    apt-get update
    apt-get install -y git curl wget nano nginx python3-certbot-nginx
    print_message "success" "基础依赖安装完成。"
}

# 安装 Docker 和 Docker Compose
function install_docker() {
    if command -v docker &> /dev/null; then
        print_message "info" "Docker 已安装，跳过安装步骤。"
    else
        print_message "info" "正在安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        print_message "success" "Docker 安装完成。"
    fi

    # 启用并启动 Docker 服务
    systemctl enable docker
    systemctl start docker

    print_message "success" "Docker 服务已启动并设置为开机自启。"
}

# 克隆并设置项目
function setup_project() {
    print_message "info" "正在从 GitHub 克隆项目..."
    if [ -d "$PROJECT_DIR" ]; then
        print_message "warning" "目录 ${PROJECT_DIR} 已存在。将尝试更新..."
        cd "$PROJECT_DIR"
        git pull
    else
        git clone "$REPO_URL" "$PROJECT_DIR"
        cd "$PROJECT_DIR"
    fi
    print_message "success" "项目克隆/更新完成。"

    print_message "info" "正在创建 .env 配置文件..."
    if [ ! -f ".env" ]; then
        cp .env.example .env
        print_message "success" ".env 文件已创建。"
    else
        print_message "info" ".env 文件已存在，跳过创建。"
    fi

    print_message "warning" "===================== 重要配置提醒 ====================="
    print_message "warning" "脚本即将使用 nano 打开配置文件: ${PROJECT_DIR}/.env"
    print_message "warning" "请务必修改以下几项，否则服务无法正常运行:"
    echo -e "  - ${YELLOW}AUTH_SECRET_KEY${NC} : 访问密码，请设置为一个复杂的随机字符串。"
    echo -e "  - ${YELLOW}MJ_SERVER${NC}       : 你的 Midjourney-Proxy 服务地址，例如: https://your-mj-proxy.com"
    echo -e "  - ${YELLOW}MJ_API_SECRET${NC}   : 你的 Midjourney-Proxy 的 API 密钥。"
    echo -e "  - ${YELLOW}OPENAI_API_KEY${NC}  : 你的 OpenAI API Key (可选，如果需要使用官方GPT模型)。"
    echo -e "  - ${YELLOW}OPENAI_API_BASE_URL${NC}: OpenAI API 代理地址 (可选)。"
    print_message "warning" "========================================================="
    read -p "准备好后，请按 [Enter] 键继续..."

    # 使用 nano 打开 .env 文件供用户编辑
    nano .env

    print_message "info" "配置文件编辑完成。正在使用 Docker Compose 启动服务..."
    # 使用 docker compose 启动，确保 docker-compose v2 语法兼容
    if ! docker compose up -d; then
        print_message "error" "Docker Compose 启动失败！请检查 .env 配置或 Docker 日志。"
        exit 1
    fi
    print_message "success" "服务已在后台成功启动！"
}

# 配置 Nginx 反向代理
function configure_nginx() {
    print_message "info" "现在开始配置 Nginx 反向代理。"
    read -p "请输入你的域名 (例如: chat.yourdomain.com): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        print_message "error" "域名不能为空！"
        exit 1
    fi

    # 创建 Nginx 配置文件
    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
    print_message "info" "正在创建 Nginx 配置文件: ${NGINX_CONF}"

    cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # 用于 Certbot 验证
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    # 启用站点
    if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}" ]; then
        ln -s "$NGINX_CONF" "/etc/nginx/sites-enabled/"
    fi

    # 测试并重载 Nginx
    if nginx -t; then
        systemctl restart nginx
        print_message "success" "Nginx 配置成功并已重载。"
    else
        print_message "error" "Nginx 配置错误，请检查！"
        exit 1
    fi
}

# 配置 SSL 证书
function setup_ssl() {
    print_message "info" "正在使用 Certbot 为 ${DOMAIN} 申请 SSL 证书..."
    # --non-interactive: 非交互模式
    # --redirect: 自动将 HTTP 重定向到 HTTPS
    # --agree-tos: 同意 Let's Encrypt 的服务条款
    # -m: 你的邮箱地址，用于接收证书续订通知
    read -p "请输入你的电子邮箱 (用于SSL证书续订通知): " EMAIL
    certbot --nginx -d "${DOMAIN}" --non-interactive --redirect --agree-tos -m "${EMAIL}"
    print_message "success" "SSL 证书配置完成！"
}


# --- 主函数 ---
function main() {
    check_root
    print_message "info" "欢迎使用 chatgpt-web-midjourney-proxy 一键部署脚本！"
    
    install_dependencies
    install_docker
    setup_project
    configure_nginx
    setup_ssl

    print_message "success" "===================== 部署完成 ====================="
    print_message "success" "你的服务现已可以通过以下地址访问:"
    echo -e "  => ${GREEN}https://${DOMAIN}${NC}"
    print_message "info" "你可以使用以下命令查看服务日志:"
    echo -e "  cd ${PROJECT_DIR} && docker compose logs -f"
    print_message "info" "如需停止服务，请运行:"
    echo -e "  cd ${PROJECT_DIR} && docker compose down"
    print_message "info" "======================================================"
}

# --- 脚本入口 ---
main
