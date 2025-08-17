#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# mosdns-x 一键安装/卸载/重装脚本（systemd）
# ===========================================
# 用法示例：
#   安装（自动取最新）：
#     sudo bash mosdns-x-install.sh
#   指定版本与端口：
#     sudo bash mosdns-x-install.sh --version v25.08.15 --port 53
#   卸载（保留配置）：
#     sudo bash mosdns-x-install.sh --uninstall
#   卸载并清理配置（purge）：
#     sudo bash mosdns-x-install.sh --uninstall --purge
#   重装（保留配置；等价于 先卸载再安装）：
#     sudo bash mosdns-x-install.sh --reinstall
#   重装并清理配置后重建：
#     sudo bash mosdns-x-install.sh --reinstall --purge

# -------------------------------
# 默认参数（可被覆盖）
# -------------------------------
MODE="install"                  # install | uninstall | reinstall
PURGE="0"                       # 1=清理配置
VERSION=""                      # 空=自动获取最新
PREFIX="/usr/local"
WORKDIR="/etc/mosdns"
PORT="53"
WITH_EASY="0"
START_AFTER="1"

# -------------------------------
# 参数解析
# -------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --with-easymosdns) WITH_EASY="1"; shift 1 ;;
    --no-start) START_AFTER="0"; shift 1 ;;
    --uninstall) MODE="uninstall"; shift 1 ;;
    --reinstall) MODE="reinstall"; shift 1 ;;
    --purge) PURGE="1"; shift 1 ;;
    -h|--help)
      cat <<EOF
用法：sudo bash $0 [选项]
  安装（默认）：
    --version <tag>       指定版本（默认自动获取最新）
    --prefix <dir>        安装前缀（默认 /usr/local）
    --workdir <dir>       工作目录（默认 /etc/mosdns）
    --port <53>           监听端口（默认 53）
    --with-easymosdns     使用 EasyMosdns 预置配置
    --no-start            安装后不立即启动

  卸载：
    --uninstall           卸载（默认保留配置）
    --purge               搭配 --uninstall 或 --reinstall 时，连配置一起清理

  重装（先卸载再安装）：
    --reinstall           先卸载再安装（默认保留配置）
    --purge               重装前清理旧配置后重建
EOF
      exit 0
      ;;
    *) echo "未知参数：$1" ; exit 1 ;;
  esac
done

# -------------------------------
# Root 检查
# -------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "本脚本需要 root 权限，请使用 sudo 运行。"
  exit 1
fi

# -------------------------------
# OS/Arch 检测
# -------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [[ "$OS" != "linux" ]]; then
  echo "当前系统：$OS。本脚本仅支持 Linux（systemd）。"
  exit 1
fi

case "$ARCH" in
  x86_64|amd64)   ASSET_ARCH="linux-amd64" ;;
  aarch64|arm64)  ASSET_ARCH="linux-arm64" ;;
  armv7l|armv7)   ASSET_ARCH="linux-arm-7" ;;
  armv6l|armv6)   ASSET_ARCH="linux-arm-6" ;;
  armv5l|armv5)   ASSET_ARCH="linux-arm-5" ;;
  mips64le)       ASSET_ARCH="linux-mips64le-hardfloat" ;;
  *)
    echo "未识别的架构: $ARCH"
    exit 1
    ;;
esac

REPO="pmkol/mosdns-x"
BIN_DIR="${PREFIX}/bin"
SERVICE_NAME="mosdns"   # 由 'mosdns service install' 创建

# -------------------------------
# 通用函数
# -------------------------------
log(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[×] %s\033[0m\n" "$*"; }

mosdns_bin_path() {
  if command -v mosdns >/dev/null 2>&1; then
    command -v mosdns
  elif [[ -x "${BIN_DIR}/mosdns" ]]; then
    echo "${BIN_DIR}/mosdns"
  else
    echo ""
  fi
}

stop_and_disable_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

daemon_reload() {
  command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
}

open_port() {
  local p="$1"
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-port="${p}/udp" --permanent || true
