#!/bin/bash
# mosdns-x 一键安装脚本 - 针对 Debian 12/13 优化

set -euo pipefail
umask 022

readonly INSTALL_PATH="/usr/local/bin"
readonly CONFIG_DIR="/etc/mosdns-x"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yaml"
readonly SERVICE_FILE="/etc/systemd/system/mosdns-x.service"
readonly TMP_DIR="$(mktemp -d /tmp/mosdns-x.XXXXXX)"
readonly SUPPORTED_DEBIAN_MAJOR_VERSIONS=("12" "13")
readonly SUPPORTED_DEBIAN_CODENAMES=("bookworm" "trixie")

DEBIAN_ID=""
DEBIAN_MAJOR_VERSION=""
DEBIAN_CODENAME=""
APT_UPDATED=0
ARCH=""
DOWNLOAD_URL=""

log() {
    local msg="$1" level="${2:-info}"
    local color
    case "$level" in
        info)    color="\033[0;36m" ;;
        warn)    color="\033[0;33m" ;;
        error)   color="\033[0;31m" ;;
        success) color="\033[0;32m" ;;
        *)       color="\033[0m" ;;
    esac
    echo -e "${color}[$(date '+%H:%M:%S')] $msg\033[0m" >&2
}

abort() {
    log "$1" "error"
    exit 1
}

cleanup() {
    local status=$?
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
    if (( status != 0 )); then
        log "脚本执行失败，请参考上述输出。" "error"
    fi
}

ensure_root() {
    if (( EUID != 0 )); then
        abort "请使用 root 权限运行此脚本。"
    fi
}

detect_debian_release() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DEBIAN_ID="${ID:-}"
        DEBIAN_CODENAME="${VERSION_CODENAME:-}"
        DEBIAN_MAJOR_VERSION="${VERSION_ID%%.*}"
    fi

    local id_like="${ID_LIKE:-}"
    if [[ "${DEBIAN_ID}" != "debian" && "${id_like}" != *debian* ]]; then
        log "检测到的系统并非 Debian 系，脚本仅在 Debian 12/13 上验证。" "warn"
    fi

    if [[ -z "$DEBIAN_MAJOR_VERSION" && -n "$DEBIAN_CODENAME" ]]; then
        case "$DEBIAN_CODENAME" in
            bookworm) DEBIAN_MAJOR_VERSION="12" ;;
            trixie)   DEBIAN_MAJOR_VERSION="13" ;;
        esac
    fi

    local supported=0 version codename
    if [[ -n "$DEBIAN_MAJOR_VERSION" ]]; then
        for version in "${SUPPORTED_DEBIAN_MAJOR_VERSIONS[@]}"; do
            if [[ "$version" == "$DEBIAN_MAJOR_VERSION" ]]; then
                supported=1
                break
            fi
        done
    fi

    if (( !supported )) && [[ -n "$DEBIAN_CODENAME" ]]; then
        for codename in "${SUPPORTED_DEBIAN_CODENAMES[@]}"; do
            if [[ "$codename" == "$DEBIAN_CODENAME" ]]; then
                supported=1
                break
            fi
        done
    fi

    if (( supported )); then
        log "检测到 Debian ${DEBIAN_MAJOR_VERSION:-unknown}${DEBIAN_CODENAME:+ (${DEBIAN_CODENAME})}。" "info"
    else
        log "当前系统版本 ${DEBIAN_MAJOR_VERSION:-unknown}${DEBIAN_CODENAME:+ (${DEBIAN_CODENAME})} 未列入官方支持范围，继续执行请谨慎。" "warn"
    fi
}

ensure_systemd() {
    if [[ ! -d /run/systemd/system ]]; then
        abort "未检测到 systemd 运行环境，无法创建服务。"
    fi
}

ensure_apt_updated() {
    if (( APT_UPDATED )); then
        return 0
    fi
    log "刷新 APT 软件源索引..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
        abort "APT 更新失败，请检查网络或软件源配置。"
    fi
    APT_UPDATED=1
}

ensure_packages() {
    local pkg missing=()
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    (( ${#missing[@]} )) || return 0

    ensure_apt_updated
    log "安装缺失的依赖: ${missing[*]}"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" >/dev/null; then
        abort "安装依赖失败: ${missing[*]}"
    fi
}

resolve_architecture() {
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$ARCH" in
        amd64|x86_64) ARCH="linux-amd64.zip" ;;
        arm64|aarch64) ARCH="linux-arm64.zip" ;;
        *)
            log "未识别的架构: $ARCH，将尝试使用 linux-amd64 版本。" "warn"
            ARCH="linux-amd64.zip"
            ;;
    esac
}

fetch_latest_release_url() {
    local api_url="https://api.github.com/repos/pmkol/mosdns-x/releases/latest"
    log "获取 mosdns-x 最新版本信息..."
    local response
    if ! response=$(curl -fsSL "$api_url"); then
        abort "无法从 GitHub API 获取版本信息。"
    fi

    DOWNLOAD_URL=$(printf '%s' "$response" | grep -Eo '"browser_download_url"[^"]+"([^"]+)' | grep "$ARCH" | sed -E 's/.*"([^"\n]+)$/\1/' | head -n1)

    if [[ -z "$DOWNLOAD_URL" ]]; then
        abort "未找到与架构匹配的下载地址 ($ARCH)。"
    fi
    log "已解析下载链接: $DOWNLOAD_URL"
}

download_and_extract() {
    log "下载 mosdns-x 包..."
    local archive="$TMP_DIR/mosdns-x.zip"
    if ! curl -fL "$DOWNLOAD_URL" -o "$archive"; then
        abort "下载 mosdns-x 失败。"
    fi

    log "解压归档文件..."
    if ! unzip -q -o "$archive" -d "$TMP_DIR"; then
        abort "解压 mosdns-x 包失败。"
    fi
}

install_binary() {
    log "安装 mosdns-x 二进制文件..."
    local source
    source=$(find "$TMP_DIR" -maxdepth 1 -type f -name 'mosdns*' | head -n1 || true)
    if [[ -z "$source" ]]; then
        abort "未在解压目录中找到 mosdns 可执行文件。"
    fi

    install -m 755 "$source" "$INSTALL_PATH/mosdns-x"
    log "已安装到 $INSTALL_PATH/mosdns-x" "success"
}

write_default_config() {
    log "写入默认配置到 $CONFIG_FILE..."
    install -d -m 755 "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'EOF'
log:
  level: info
  file: ""

plugins:
  - tag: forward_dot_servers
    type: fast_forward
    args:
      upstream:
        - addr: tls://1.1.1.1
        - addr: tls://8.8.8.8
        - addr: tls://9.9.9.9

servers:
  - exec: forward_dot_servers
    listeners:
      - protocol: udp
        addr: 127.0.0.1:53
      - protocol: tcp
        addr: 127.0.0.1:53
EOF
    log "默认配置已写入。" "success"
}

create_service_unit() {
    log "创建 systemd 服务单元..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=mosdns-x DNS forwarder
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/mosdns-x start -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    log "服务文件已生成 ($SERVICE_FILE)。" "success"
}

configure_system_dns() {
    log "配置系统 DNS 以使用 mosdns-x..."

    local resolv_conf="/etc/resolv.conf"
    local backup="${resolv_conf}.mosdns-x.backup"
    local resolv_link_target=""

    if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        if systemctl is-active --quiet systemd-resolved; then
            log "检测到 systemd-resolved 正在运行，尝试停止以释放 53 端口..."
            if systemctl stop systemd-resolved >/dev/null 2>&1; then
                log "systemd-resolved 已停止。" "success"
            else
                log "无法停止 systemd-resolved，可能会导致端口冲突。" "warn"
            fi
        fi
        if systemctl is-enabled --quiet systemd-resolved; then
            if systemctl disable systemd-resolved >/dev/null 2>&1; then
                log "已禁用 systemd-resolved 开机自启。" "info"
            else
                log "无法禁用 systemd-resolved 开机自启，请手动确认。" "warn"
            fi
        fi
    fi

    if [[ -L "$resolv_conf" ]]; then
        resolv_link_target=$(readlink -f "$resolv_conf" || true)
        if [[ -n "$resolv_link_target" && -f "$resolv_link_target" && ! -e "$backup" ]]; then
            cp "$resolv_link_target" "$backup"
            log "已备份原 DNS 配置到 $backup" "info"
        elif [[ ! -e "$backup" ]]; then
            cp "$resolv_conf" "$backup" 2>/dev/null || true
            [[ -f "$backup" ]] && log "已备份原 DNS 配置到 $backup" "info"
        fi
        rm -f "$resolv_conf"
    else
        if [[ -f "$resolv_conf" && ! -e "$backup" ]]; then
            cp "$resolv_conf" "$backup"
            log "已备份原 DNS 配置到 $backup" "info"
        fi
    fi

    cat > "$resolv_conf" <<'EOF'
nameserver 127.0.0.1
options edns0 trust-ad
EOF
    chmod 644 "$resolv_conf"

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    fi

    log "系统 DNS 已指向 127.0.0.1，由 mosdns-x 接管。" "success"
}

reload_and_enable_service() {
    log "重载 systemd 守护进程..."
    systemctl daemon-reload
    systemctl enable mosdns-x >/dev/null 2>&1 || true
    log "启动 mosdns-x 服务..."
    if systemctl restart mosdns-x; then
        if systemctl is-active --quiet mosdns-x; then
            log "mosdns-x 服务已成功启动。" "success"
        else
            abort "mosdns-x 服务未能保持运行，请检查日志。"
        fi
    else
        abort "无法启动 mosdns-x 服务。"
    fi
}

print_summary() {
    echo
    log "================ 安装完成 ================"
    echo "  二进制路径 : ${INSTALL_PATH}/mosdns-x"
    echo "  配置文件   : ${CONFIG_FILE}"
    echo "  服务管理   : systemctl [start|stop|restart] mosdns-x"
    echo "  查看日志   : journalctl -u mosdns-x -f"
    echo "  DNS 地址   : 127.0.0.1:53 (TCP/UDP)"
    echo
}

main() {
    trap cleanup EXIT
    ensure_root
    detect_debian_release
    ensure_systemd
    ensure_packages curl unzip ca-certificates
    resolve_architecture
    fetch_latest_release_url
    download_and_extract
    install_binary
    write_default_config
    create_service_unit
    configure_system_dns
    reload_and_enable_service
    print_summary
}

main "$@"
