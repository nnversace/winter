#!/usr/bin/env bash
#=============================================================================
# mosdns-x One-Key Script for Debian 13 (Trixie)
#
# Original Author: pmkol/mosdns-x
# Optimizer: Gemini based on LucaLin233's script style
# Functions: install | uninstall | reinstall | menu
#=============================================================================

set -Eeuo pipefail

#--- Global Constants ---
readonly REPO="pmkol/mosdns-x"
readonly WORKDIR="/etc/mosdns"
readonly BIN="/usr/local/bin/mosdns"
readonly SERVICE_NAME="mosdns"
readonly API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"
readonly TMP_DIR="$(mktemp -d)"

#--- Color Definitions ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#--- Logging and Utility Functions ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "info")    echo -e "${GREEN}✅ [INFO] $msg${NC}" ;;
        "warn")    echo -e "${YELLOW}⚠️  [WARN] $msg${NC}" ;;
        "error")   echo -e "${RED}❌ [ERROR] $msg${NC}" ;;
        "success") echo -e "${GREEN}🎉 [SUCCESS] $msg${NC}" ;;
    esac
    # Optionally log to a file, similar to the main script
    # echo "[$timestamp] [$level] $msg" >> "/var/log/mosdns-setup.log" 2>/dev/null || true
}

print_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '='
}

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

#--- Pre-flight Checks and Dependency Management ---
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script requires root privileges. Please run with sudo." "error"
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)   echo "amd64" ;;
        aarch64)  echo "arm64" ;;
        armv7*)   echo "arm-7" ;;
        armv6*)   echo "arm-6" ;;
        armv5*)   echo "arm-5" ;;
        *)
            log "Unsupported architecture: $(uname -m)" "error"
            exit 1
            ;;
    esac
}

ensure_deps() {
    log "Checking for dependencies (curl, unzip, jq)..."
    local missing_deps=()
    for cmd in curl unzip jq; do
        command -v "$cmd" &>/dev/null || missing_deps+=("$cmd")
    done

    if (( ${#missing_deps[@]} > 0 )); then
        log "Installing missing dependencies: ${missing_deps[*]}"
        apt-get update -qq
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing_deps[@]}"; then
            log "Failed to install dependencies. Aborting." "error"
            exit 1
        fi
    fi
    log "Dependencies are satisfied."
}

#--- Core Logic Functions ---
fetch_asset_url() {
    local arch="$1"
    # Redirect this log message to stderr to prevent it from being captured by command substitution.
    log "Fetching latest release URL for arch '$arch'..." >&2
    # This filter correctly handles the v3 naming for amd64
    local filter='.assets[] | select(.name | test("mosdns-linux-'"$arch"'(-v[0-9]+)?\\.zip$")) | .browser_download_url'
    local url
    url=$(curl -fsSL --connect-timeout 10 "$API_LATEST" | jq -r "$filter" | head -n1)

    if [[ -z "$url" || "$url" == "null" ]]; then
        log "Could not find a download URL for the '$arch' architecture." "error" >&2
        log "Please check the releases page: https://github.com/${REPO}/releases" "error" >&2
        return 1
    fi
    echo "$url"
}

write_default_config() {
    local cfg="${WORKDIR}/config.yaml"
    if [[ -f "$cfg" ]]; then
        log "Configuration file already exists, skipping creation." "warn"
        return 0
    fi

    log "Writing default minimal configuration to $cfg"
    # Minimal and fast UDP+TCP configuration
    cat >"$cfg" <<'YAML'
log:
  level: info
  file: "" # Log to console

plugins:
  - tag: cache
    type: cache
    args:
      size: 4096
      lazy_cache_ttl: 86400

  - tag: upstream_doh
    type: fast_forward
    args:
      upstream:
        - addr: https://1.1.1.1/dns-query
        - addr: https://8.8.8.8/dns-query

  - tag: main_sequence
    type: sequence
    args:
      - exec: cache
      - exec: upstream_doh

servers:
  - exec: main_sequence
    listeners:
      - protocol: udp
        addr: 127.0.0.1:53
      - protocol: tcp
        addr: 127.0.0.1:53
YAML
    log "Default configuration written successfully." "success"
}

install_service_files() {
    log "Installing and enabling systemd service..."
    # Use mosdns's built-in service management commands
    if ! "$BIN" service install -d "$WORKDIR" -c "${WORKDIR}/config.yaml"; then
        log "Failed to install the systemd service." "error"
        return 1
    fi
    if ! "$BIN" service start; then
        log "Failed to start the mosdns service. Check status with 'systemctl status $SERVICE_NAME'" "warn"
    fi
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    log "Service '$SERVICE_NAME' installed and started."
}

#--- Main Actions: Install, Uninstall, Reinstall ---
do_install() {
    log "Starting mosdns-x installation..."
    ensure_root
    ensure_deps
    mkdir -p "$WORKDIR"

    local arch url asset_path
    arch=$(detect_arch)
    log "Detected architecture: $arch"

    url=$(fetch_asset_url "$arch") || exit 1
    log "Downloading from: $url"

    asset_path="$TMP_DIR/mosdns.zip"
    if ! curl -fSL --retry 3 --connect-timeout 15 -o "$asset_path" "$url"; then
        log "Download failed." "error"
        exit 1
    fi

    log "Installing binary to $BIN..."
    unzip -oj "$asset_path" "mosdns" -d "$TMP_DIR"
    install -m 0755 "$TMP_DIR/mosdns" "$BIN"

    write_default_config
    install_service_files

    print_line
    log "mosdns-x installation complete!" "success"
    echo -e "  Binary:    $BIN"
    echo -e "  Config Dir: $WORKDIR"
    echo -e "  Service:   systemctl status ${SERVICE_NAME}"
    print_line
}

do_uninstall() {
    log "Starting mosdns-x uninstallation..."
    ensure_root

    log "Stopping and uninstalling service..."
    if command -v mosdns &>/dev/null; then
        "$BIN" service stop >/dev/null 2>&1 || true
        "$BIN" service uninstall >/dev/null 2>&1 || true
    else
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    fi
    systemctl daemon-reload

    log "Removing binary: $BIN"
    rm -f "$BIN"

    if [[ -d "$WORKDIR" ]]; then
        local backup_dir="${WORKDIR}-backup-$(date +%Y%m%d-%H%M%S)"
        mv "$WORKDIR" "$backup_dir"
        log "Configuration backed up to: $backup_dir" "success"
    fi

    log "Uninstallation complete." "success"
}

do_reinstall() {
    log "Starting mosdns-x reinstallation..."
    ensure_root
    local config_backup=""
    if [[ -f "${WORKDIR}/config.yaml" ]]; then
        config_backup="$(mktemp)"
        cp "${WORKDIR}/config.yaml" "$config_backup"
        log "Existing configuration has been backed up temporarily."
    fi

    do_uninstall
    echo # Add a space for better readability
    do_install

    if [[ -n "$config_backup" ]]; then
        log "Restoring previous configuration..."
        cp "$config_backup" "${WORKDIR}/config.yaml"
        rm "$config_backup"
        log "Restarting service with restored configuration..."
        systemctl restart "$SERVICE_NAME"
        log "Reinstallation complete with configuration restored." "success"
    fi
}

#--- User Interface ---
show_menu() {
    clear
    print_line
    echo "mosdns-x One-Key Management Script"
    print_line
    echo
    echo "  1) Install mosdns-x"
    echo "  2) Uninstall mosdns-x"
    echo "  3) Reinstall mosdns-x"
    echo "  4) Exit"
    echo
    read -p "Please enter your choice [1-4]: " -r choice
    case "$choice" in
        1) do_install ;;
        2) do_uninstall ;;
        3) do_reinstall ;;
        4) exit 0 ;;
        *)
            log "Invalid option, please try again." "error"
            sleep 2
            show_menu
            ;;
    esac
}

#--- Script Entry Point ---
main() {
    # If arguments are passed, use command-line mode. Otherwise, show the menu.
    case "${1:-menu}" in
        install)   do_install ;;
        uninstall) do_uninstall ;;
        reinstall) do_reinstall ;;
        menu)      show_menu ;;
        *)
            echo -e "${RED}Usage: $0 {install|uninstall|reinstall}${NC}"
            echo "Run without arguments to show the interactive menu."
            exit 1
            ;;
    esac
}

main "$@"
