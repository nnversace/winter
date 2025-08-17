#!/usr/bin/env bash
# mosdns-x one-key script for Debian 13 (trixie)
# Functions: install | uninstall | reinstall
set -Eeuo pipefail

REPO="pmkol/mosdns-x"
WORKDIR="/etc/mosdns"
BIN="/usr/local/bin/mosdns"
SERVICE_NAME="mosdns"
TMP_DIR="$(mktemp -d)"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"

msg() { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

need_root() {
  if [[ $EUID -ne 0 ]]; then
    err "请以 root 运行。用 sudo 再试。"; exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l|armv7) echo "arm-7" ;;
    armv6l|armv6) echo "arm-6" ;;
    armv5tel|armv5) echo "arm-5" ;;
    *) err "未知架构: $(uname -m)"; exit 1 ;;
  esac
}

ensure_deps() {
  msg "安装依赖：curl unzip jq"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl unzip jq
}

fetch_asset_url() {
  local arch="$1"
  local filter='.assets[] | select(.name=="mosdns-linux-'$arch'.zip" or (.name=="mosdns-linux-'$arch'-v3.zip" and "'$arch'"=="amd64")) | .browser_download_url'
  curl -fsSL "$API_LATEST" | jq -r "$filter" | head -n1
}

write_default_config() {
  local cfg="${WORKDIR}/config.yaml"
  if [[ -f "$cfg" ]]; then
    warn "检测到已存在配置：$cfg，跳过生成默认配置。"
    return 0
  fi

  # --- 你指定的 UDP+TCP 极简极速配置 ---
  cat >"$cfg" <<'YAML'
log: { level: info, file: "" }

plugins:
  - tag: cache
    type: cache
    args:
      size: 4096

  - tag: upstream
    type: fast_forward
    args:
      upstream:
        - addr: https://1.1.1.1/dns-query
        - addr: https://8.8.8.8/dns-query

  - tag: main
    type: sequence
    args: { exec: [cache, upstream] }

servers:
  - exec: main
    listeners:
      - { protocol: udp, addr: 127.0.0.1:53 }
      - { protocol: tcp, addr: 127.0.0.1:53 }
YAML
  msg "已写入默认配置：$cfg"
}

install_service() {
  "$BIN" service uninstall || true
  "$BIN" service install -d "$WORKDIR" -c "${WORKDIR}/config.yaml"
  "$BIN" service start || systemctl start "$SERVICE_NAME"
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl daemon-reload || true
}

do_install() {
  need_root
  ensure_deps
  mkdir -p "$WORKDIR"

  local arch url asset
  arch="$(detect_arch)"; msg "检测到架构：$arch"
  url="$(fetch_asset_url "$arch" || true)"
  if [[ -z "${url:-}" || "$url" == "null" ]]; then
    err "未找到对应架构的二进制，请检查 Release 页面。"; exit 1
  fi

  asset="$TMP_DIR/mosdns.zip"
  msg "下载 mosdns-x: $url"
  curl -fSL --retry 3 -o "$asset" "$url"

  msg "解压并安装至 $BIN"
  unzip -q "$asset" -d "$TMP_DIR"
  install -m 0755 "$TMP_DIR/mosdns" "$BIN"

  write_default_config
  install_service

  msg "安装完成。"
  echo "二进制: $BIN"
  echo "配置:   $WORKDIR/config.yaml"
  echo "服务:   systemctl status ${SERVICE_NAME}"
}

do_uninstall() {
  need_root
  warn "停止并卸载服务"
  if command -v mosdns >/dev/null 2>&1; then
    mosdns service stop || true
    mosdns service uninstall || true
  else
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  fi
  systemctl daemon-reload || true

  warn "删除二进制 $BIN"
  rm -f "$BIN"

  if [[ -d "$WORKDIR" ]]; then
    local bk="${WORKDIR}-backup-$(date +%Y%m%d%H%M%S)"
    mv "$WORKDIR" "$bk"
    msg "配置已备份到: $bk"
  fi

  msg "卸载完成。"
}

do_reinstall() {
  need_root
  local cfg_bak=""
  if [[ -f "${WORKDIR}/config.yaml" ]]; then
    cfg_bak="$(mktemp)"
    cp -f "${WORKDIR}/config.yaml" "$cfg_bak"
    msg "已备份现有配置。"
  fi
  do_uninstall
  do_install
  if [[ -n "${cfg_bak}" && -f "$cfg_bak" ]]; then
    cp -f "$cfg_bak" "${WORKDIR}/config.yaml"
    systemctl restart "$SERVICE_NAME" || true
    msg "已恢复原配置并重启服务。"
  fi
}

main() {
  case "${1:-}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    reinstall) do_reinstall ;;
    *) echo "用法: $0 {install|uninstall|reinstall}"; exit 1 ;;
  esac
}

main "$@"
