#!/bin/bash

# ShadowTLS 一键安装与管理脚本（精简优化版）
# 版本: v2.1
# 作者: ChatGPT 优化
set -euo pipefail

# 配置常量
readonly RED='\033[0;31m'; readonly GREEN='\033[0;32m'; readonly YELLOW='\033[1;33m'; readonly NC='\033[0m'
readonly SCRIPT_DIR="/opt/shadowtls"
readonly CONFIG_FILE="$SCRIPT_DIR/shadowtls_config.txt"
readonly COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
readonly DOCKER_IMAGE="ghcr.io/ihciah/shadow-tls:latest"
readonly FIXED_PASSWORD="IUmuU/NjIQhHPMdBz5WONA=="

info() { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; }
step() { echo -e "${GREEN}--- $1${NC}"; }

trap 'err "发生错误 (行 $LINENO)"' ERR

check_root() { [[ $EUID -eq 0 ]] || { err "请以root运行。"; exit 1; }; }

# 检查并安装依赖
install_deps() {
  step "安装依赖..."
  if command -v apt &>/dev/null; then
    apt update -qq; apt install -y curl wget ca-certificates lsb-release >/dev/null
  elif command -v yum &>/dev/null; then
    yum install -y curl wget ca-certificates >/dev/null
  elif command -v dnf &>/dev/null; then
    dnf install -y curl wget ca-certificates >/dev/null
  else
    err "不支持的操作系统"; exit 1
  fi
}

# Docker 检查/安装
install_docker() {
  step "检测/安装 Docker..."
  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh >/dev/null
    systemctl enable --now docker
  fi
  info "Docker 已准备"
}

# Docker Compose 检查（新版优先，旧版兼容）
compose_cmd() {
  if command -v docker-compose &>/dev/null; then echo "docker-compose"
  elif docker compose version &>/dev/null; then echo "docker compose"
  else install_docker_compose; echo "docker compose"; fi
}
install_docker_compose() {
  step "安装 Docker Compose..."
  if ! docker compose version &>/dev/null; then
    local latest v
    latest=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)
    v="docker-compose-$(uname -s)-$(uname -m)"
    curl -L "https://github.com/docker/compose/releases/download/${latest}/${v}" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || true
  fi
}

# 获取公网IP
get_ip() {
  curl -s https://api.ip.sb/ip || curl -s ifconfig.me || echo "x.x.x.x"
}

# 配置收集
get_user_config() {
  mkdir -p "$SCRIPT_DIR"
  cd "$SCRIPT_DIR"
  step "ShadowTLS 配置向导"
  read -p "监听端口[8443]: " LISTEN_PORT; LISTEN_PORT=${LISTEN_PORT:-8443}
  read -p "后端服务器[127.0.0.1:52171]: " SERVER_ADDR; SERVER_ADDR=${SERVER_ADDR:-127.0.0.1:52171}
  read -p "TLS握手目标域名[gateway.icloud.com]: " TLS_TARGET; TLS_TARGET=${TLS_TARGET:-gateway.icloud.com}
  echo "监听地址: 1) 0.0.0.0  2) ::  3) ::0 (推荐)"
  read -p "选择[3]: " ADDR_CHOICE
  case "${ADDR_CHOICE:-3}" in 1) LISTEN_ADDR="0.0.0.0";; 2) LISTEN_ADDR="::";; *) LISTEN_ADDR="::0";; esac
  read -p "详细日志? (y/N): " DBG; [[ "$DBG" =~ ^[Yy]$ ]] && RUST_LOG="debug" || RUST_LOG="error"
  SHADOWTLS_PASSWORD="$FIXED_PASSWORD"
}

# 写 compose 文件
write_compose() {
  step "生成 compose 文件..."
  cat > "$COMPOSE_FILE" << EOF
services:
  shadow-tls:
    image: $DOCKER_IMAGE
    network_mode: host
    restart: unless-stopped
    environment:
      - MODE=server
      - LISTEN=${LISTEN_ADDR}:${LISTEN_PORT}
      - SERVER=${SERVER_ADDR}
      - TLS=${TLS_TARGET}:443
      - PASSWORD=${SHADOWTLS_PASSWORD}
      - V3=1
      - RUST_LOG=${RUST_LOG}
EOF
}

# 启动服务
start_service() {
  cd "$SCRIPT_DIR"
  $_COMPOSE down >/dev/null 2>&1 || true
  $_COMPOSE up -d
  sleep 2
  $_COMPOSE ps
  info "服务已启动"
}

# 生成并显示配置信息
show_info() {
  local ip=$(get_ip)
  cat > "$CONFIG_FILE" << EOF
# ShadowTLS 配置信息 $(date +%F" "%T)
服务器: $ip:$LISTEN_PORT
密码: $SHADOWTLS_PASSWORD
后端: $SERVER_ADDR
TLS目标: $TLS_TARGET
连接示例:
shadow-tls --v3 client --listen 127.0.0.1:1080 --server $ip:$LISTEN_PORT --tls $TLS_TARGET:443 --password $SHADOWTLS_PASSWORD
EOF
  echo -e "${GREEN}===== 配置信息 =====${NC}"
  cat "$CONFIG_FILE"
  echo -e "${YELLOW}如需开放端口: ufw allow $LISTEN_PORT/tcp 或 firewall-cmd ...${NC}"
}

# 入口命令处理
case "${1:-}" in
  install|"")
    check_root
    install_deps
    install_docker
    _COMPOSE=$(compose_cmd)
    get_user_config
    write_compose
    $_COMPOSE pull
    start_service
    show_info
    ;;
  start)
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE up -d; info "已启动"
    ;;
  stop)
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE down; info "已停止"
    ;;
  restart)
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE restart; info "已重启"
    ;;
  status)
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE ps
    ;;
  logs)
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE logs -f --tail=50
    ;;
  config)
    [[ -f "$CONFIG_FILE" ]] && cat "$CONFIG_FILE" || warn "未找到配置"
    ;;
  update)
    check_root; _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE down
    get_user_config; write_compose
    start_service; show_info
    ;;
  upgrade)
    check_root; _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE down
    $_COMPOSE pull; $_COMPOSE up -d; info "已升级并重启"
    ;;
  uninstall)
    warn "即将删除服务及配置，输入CONFIRM继续:"
    read -r input; [[ "$input" != "CONFIRM" ]] && { info "已取消"; exit 0; }
    _COMPOSE=$(compose_cmd); cd "$SCRIPT_DIR"; $_COMPOSE down || true
    docker rmi "$DOCKER_IMAGE" || true; rm -rf "$SCRIPT_DIR"
    info "已卸载"
    ;;
  *)
    echo -e "用法: $0 [install|start|stop|restart|status|logs|config|update|upgrade|uninstall]"
    ;;
esac
