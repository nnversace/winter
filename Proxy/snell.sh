#!/bin/bash

set -euo pipefail

SNELL_VERSION="v5.0.0"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="snell"
CONFIG_DIR="/etc/snell"
CONFIG_PATH="${CONFIG_DIR}/snell-server.conf"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
SNELL_PORT=53100
SNELL_PSK="IUmuU/NjIQhHPMdBz5WONA=="

log_info() {
  printf '\033[32m[INFO]\033[0m %s\n' "$*"
}

log_warn() {
  printf '\033[33m[WARN]\033[0m %s\n' "$*"
}

log_error() {
  printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2
}

ensure_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "此脚本必须以 root 权限运行"
    exit 1
  fi
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "未找到依赖命令: $1"
    exit 1
  fi
}

detect_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)
      echo "amd64"
      ;;
    i386|i686)
      echo "i386"
      ;;
    aarch64)
      echo "aarch64"
      ;;
    armv7l)
      echo "armv7l"
      ;;
    *)
      log_error "不支持的架构: $arch"
      exit 1
      ;;
  esac
}

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    log_error "无效的端口号: $port"
    exit 1
  fi
}

write_config() {
  local port="$1" psk="$2"

  install -d -m 755 "$CONFIG_DIR"

  if [[ -f "$CONFIG_PATH" ]]; then
    local backup="${CONFIG_PATH}.$(date +%Y%m%d%H%M%S).bak"
    cp "$CONFIG_PATH" "$backup"
    log_info "已备份现有配置到 $backup"
  fi

  cat >"$CONFIG_PATH" <<EOF
[snell-server]
listen = 0.0.0.0:${port}
psk = ${psk}
EOF

  chmod 600 "$CONFIG_PATH"
}

write_service() {
  cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=${INSTALL_DIR}/snell-server -c ${CONFIG_PATH}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

install_snell() {
  local arch="$1"
  local temp_dir=""
  temp_dir=$(mktemp -d)
  trap '[[ -n "${temp_dir:-}" ]] && rm -rf "${temp_dir:-}"' EXIT

  local url="https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-${arch}.zip"
  log_info "正在下载 Snell ${SNELL_VERSION} (${arch})..."
  wget -qO "${temp_dir}/snell.zip" "$url" || {
    log_error "下载失败，请检查网络或下载地址: $url"
    exit 1
  }

  log_info "正在解压 Snell..."
  unzip -oq "${temp_dir}/snell.zip" -d "$temp_dir"

  install -m 755 "${temp_dir}/snell-server" "${INSTALL_DIR}/snell-server"
  log_info "Snell 已安装到 ${INSTALL_DIR}/snell-server"

  rm -rf "$temp_dir"
  trap - EXIT
}

configure_systemd() {
  log_info "正在写入 systemd 服务配置..."
  write_service
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

print_summary() {
  local port="$1" psk="$2"
  echo "Snell ${SNELL_VERSION} 安装完成!"
  echo "------------------------------"
  echo "服务器地址: $(hostname -I | awk '{print $1}')"
  echo "端口: ${port}"
  echo "PSK: ${psk}"
  echo "配置文件: ${CONFIG_PATH}"
  echo "服务: systemctl status ${SERVICE_NAME}"
  echo "------------------------------"
}

main() {
  ensure_root
  ensure_command wget
  ensure_command unzip
  ensure_command systemctl

  local arch port psk
  arch=$(detect_arch)

  port="$SNELL_PORT"
  validate_port "$port"

  psk="$SNELL_PSK"

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_info "检测到已运行的 Snell 服务，正在停止..."
    systemctl stop "$SERVICE_NAME"
  fi

  install_snell "$arch"
  write_config "$port" "$psk"
  configure_systemd
  print_summary "$port" "$psk"
}

main "$@"
