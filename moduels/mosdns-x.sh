#!/bin/bash

# Mosdns-x One-Click Installation Script (Optimized)
#
# This script automates the installation and configuration of mosdns-x.
# Project: https://github.com/pmkol/mosdns-x
#
# Enhancements:
# - Improved UI and user interaction.
# - Pre-installation check to prevent accidental re-installations.
# - Updated default configuration with modern DNS upstreams (QUIC, TLS).
# - Graceful exit on interruption.

set -e

# --- Configuration Variables ---
GITHUB_REPO="pmkol/mosdns-x"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/mosdns"
SERVICE_NAME="mosdns"
LATEST_VERSION=""

# --- UI Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Logging and Utility Functions ---

# Function to handle script interruption (Ctrl+C)
trap 'echo -e "\n${RED}Operation cancelled by user.${NC}"; exit 1;' INT

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_banner() {
    echo -e "${PURPLE}"
    echo "=========================================="
    echo "   Mosdns-x One-Click Installer Script    "
    echo "=========================================="
    echo -e "${NC}"
}

# --- Pre-flight Checks ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges to run."
        log_info "Please use: sudo $0"
        exit 1
    fi
}

check_existing_install() {
    if [[ -f "$INSTALL_DIR/mosdns" ]]; then
        log_warning "Mosdns appears to be already installed at $INSTALL_DIR/mosdns."
        read -p "Do you want to proceed with re-installation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation aborted."
            exit 0
        fi
    fi
}

detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        i386|i686) echo "386" ;;
        *)
            log_error "Unsupported system architecture: $arch"
            exit 1
            ;;
    esac
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# --- Core Installation Functions ---

install_dependencies() {
    log_info "Installing necessary dependencies (curl, wget, unzip, systemd)..."
    local os=$(detect_os)
    
    case $os in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y curl wget unzip systemd
            ;;
        centos|rhel|fedora|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget unzip systemd
            else
                yum install -y curl wget unzip systemd
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm --needed curl wget unzip systemd
            ;;
        *)
            log_warning "Unknown OS. Please manually install: curl, wget, unzip, systemd."
            ;;
    esac
}

get_latest_version() {
    log_info "Fetching the latest version information from GitHub..."
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
                     grep '"tag_name"' | \
                     sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_VERSION" ]]; then
        log_error "Failed to fetch the latest version. Please check your network or GitHub API rate limits."
        exit 1
    fi
    
    log_success "Latest version identified: ${CYAN}$LATEST_VERSION${NC}"
}

download_mosdns() {
    local arch=$(detect_arch)
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$LATEST_VERSION/mosdns-linux-$arch.zip"
    local temp_dir=$(mktemp -d)
    
    log_info "Downloading mosdns-x $LATEST_VERSION for linux-$arch..."
    
    if ! wget -q --show-progress "$download_url" -O "$temp_dir/mosdns.zip"; then
        log_error "Download failed. Please check your network connection."
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_info "Unpacking files..."
    unzip -q "$temp_dir/mosdns.zip" -d "$temp_dir"
    
    log_info "Installing mosdns binary to $INSTALL_DIR..."
    mv "$temp_dir/mosdns" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/mosdns"
    
    log_success "mosdns binary installed successfully."
    
    rm -rf "$temp_dir"
}

create_config() {
    log_info "Creating configuration directory and default config file..."
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_DIR/config.yaml" << 'EOF'
# Default configuration for mosdns-x
# For more details, visit: https://github.com/pmkol/mosdns-x/wiki

log:
  level: info
  file: "/var/log/mosdns.log"

include: []

plugins:
  # DNS cache to improve query speed.
  - tag: cache
    type: cache
    args:
      size: 8192

  # Forward DNS queries to upstream servers.
  # This list includes modern encrypted DNS protocols (QUIC, TLS)
  # for better privacy and security, with standard DNS as a fallback.
  - tag: forward
    type: fast_forward
    args:
      upstream:
        # DNS-over-QUIC (fastest and most secure)
        - addr: "quic://dns.google"
        - addr: "quic://1.1.1.1"

        # DNS-over-TLS (secure)
        - addr: "tls://dns.google"
        - addr: "tls://1.1.1.1"
        
        # Standard DNS (fallback)
        - addr: "8.8.8.8"
        - addr: "1.1.1.1"

  # Main execution sequence.
  - tag: main_sequence
    type: sequence
    args:
      exec:
        - cache
        - forward

servers:
  # Listen for incoming DNS queries on port 53 for both UDP and TCP.
  - exec: main_sequence
    listeners:
      - protocol: udp
        addr: "0.0.0.0:53"
      - protocol: tcp
        addr: "0.0.0.0:53"
EOF

    log_success "Default configuration file created at ${CYAN}$CONFIG_DIR/config.yaml${NC}"
}

create_systemd_service() {
    log_info "Creating systemd service file..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Mosdns-x DNS Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/mosdns start -c $CONFIG_DIR/config.yaml -d $CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service file created and reloaded."
}

start_service() {
    log_info "Starting and enabling mosdns service..."
    
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
    systemctl start "$SERVICE_NAME"
    
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Mosdns service is active and running."
    else
        log_error "Mosdns service failed to start."
        log_info "Run ${CYAN}journalctl -u $SERVICE_NAME -f${NC} for detailed logs."
        exit 1
    fi
}

configure_firewall() {
    log_info "Attempting to configure firewall rules for DNS (port 53)..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 53/tcp > /dev/null
        ufw allow 53/udp > /dev/null
        log_success "UFW firewall rules for port 53 (TCP/UDP) have been added."
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=53/tcp > /dev/null
        firewall-cmd --permanent --add-port=53/udp > /dev/null
        firewall-cmd --reload > /dev/null
        log_success "Firewalld rules for port 53 (TCP/UDP) have been added."
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport 53 -j ACCEPT
        iptables -A INPUT -p udp --dport 53 -j ACCEPT
        log_success "Iptables rules for port 53 (TCP/UDP) have been added."
        log_warning "Please ensure your iptables rules are saved to persist after a reboot."
    else
        log_warning "Could not detect a common firewall service. Please open port 53 (TCP/UDP) manually."
    fi
}

show_completion_info() {
    echo
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}      🎉 Mosdns-x Installation Complete! 🎉      ${NC}"
    echo -e "${GREEN}===================================================${NC}"
    echo
    echo -e "${CYAN}--- Key Information ---${NC}"
    echo -e "  ${YELLOW}Version Installed:${NC} $LATEST_VERSION"
    echo -e "  ${YELLOW}Binary Location:${NC}   $INSTALL_DIR/mosdns"
    echo -e "  ${YELLOW}Configuration Dir:${NC} $CONFIG_DIR"
    echo -e "  ${YELLOW}Log File:${NC}          /var/log/mosdns.log"
    echo
    echo -e "${CYAN}--- Service Commands ---${NC}"
    echo -e "  ${YELLOW}Start Service:${NC}     systemctl start $SERVICE_NAME"
    echo -e "  ${YELLOW}Stop Service:${NC}      systemctl stop $SERVICE_NAME"
    echo -e "  ${YELLOW}Restart Service:${NC}   systemctl restart $SERVICE_NAME"
    echo -e "  ${YELLOW}Reload Config:${NC}     systemctl reload $SERVICE_NAME"
    echo -e "  ${YELLOW}Check Status:${NC}      systemctl status $SERVICE_NAME"
    echo -e "  ${YELLOW}View Logs:${NC}         journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${CYAN}--- How to Use ---${NC}"
    echo -e "  To use mosdns, set your system or router's DNS server to this machine's IP address."
    echo -e "  You can test locally with: ${PURPLE}nslookup google.com 127.0.0.1${NC}"
    echo
    echo -e "${YELLOW}To customize, edit ${CYAN}$CONFIG_DIR/config.yaml${YELLOW} and restart/reload the service.${NC}"
    echo
}

# --- Uninstall Function ---

uninstall() {
    log_info "Starting uninstallation of mosdns-x..."
    check_root
    
    if ! [[ -f "$INSTALL_DIR/mosdns" || -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        log_error "Mosdns does not appear to be installed. Aborting."
        exit 1
    fi

    log_info "Stopping and disabling the service..."
    systemctl stop "$SERVICE_NAME" > /dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" > /dev/null 2>&1 || true
    
    log_info "Removing files..."
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -f "$INSTALL_DIR/mosdns"
    
    systemctl daemon-reload
    
    read -p "Do you want to remove the configuration directory ($CONFIG_DIR)? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f /var/log/mosdns.log
        log_success "Configuration directory and log file removed."
    fi
    
    log_success "Mosdns-x uninstallation complete."
}

# --- Help Function ---

show_help() {
    echo "Mosdns-x One-Click Management Script"
    echo
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  install      (Default) Install or reinstall mosdns-x."
    echo "  uninstall    Remove mosdns-x from the system."
    echo "  help         Display this help message."
    echo
    echo "Example: sudo ./$0 install"
}

# --- Main Execution Logic ---

main() {
    case "${1:-install}" in
        install)
            show_banner
            check_root
            check_existing_install
            install_dependencies
            get_latest_version
            download_mosdns
            create_config
            create_systemd_service
            start_service
            configure_firewall
            show_completion_info
            ;;
        uninstall)
            uninstall
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run the main function with all script arguments
main "$@"
