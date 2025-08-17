#!/bin/bash

# Mosdns-x One-Click Installation Script (Ultra-Optimized)
#
# Enhanced Features:
# - Modern high-performance configuration with DoQ/DoH/DoT
# - Improved error handling and validation
# - Better system integration and security
# - Optimized for performance and reliability
#
# Project: https://github.com/pmkol/mosdns-x

set -euo pipefail

# --- Configuration Variables ---
readonly GITHUB_REPO="pmkol/mosdns-x"
readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/mosdns"
readonly SERVICE_NAME="mosdns"
readonly LOG_FILE="/var/log/mosdns.log"

# --- UI Color Definitions ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# --- Global Variables ---
LATEST_VERSION=""
SYSTEM_ARCH=""
SYSTEM_OS=""

# --- Signal Handling ---
trap 'echo -e "\n${RED}❌ Operation cancelled by user.${NC}"; cleanup; exit 130' INT TERM

cleanup() {
    # Clean up temporary files on exit
    [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir" 2>/dev/null || true
}

# --- Logging Functions ---
log_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

show_banner() {
    echo -e "${PURPLE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║    🚀 Mosdns-x Ultra-Optimized One-Click Installer       ║
║                                                           ║
║    • High-performance DNS forwarding                     ║
║    • DoQ/DoH/DoT support                                  ║
║    • ECS optimization                                     ║
║    • Enterprise-grade configuration                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# --- Validation Functions ---
check_requirements() {
    log_info "Checking system requirements..."
    
    # Root privileges check
    if [[ $EUID -ne 0 ]]; then
        log_error "Root privileges required. Please run with sudo."
        exit 1
    fi
    
    # Internet connectivity check
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log_error "Internet connection required but not available."
        exit 1
    fi
    
    # System compatibility check
    if ! command -v systemctl &>/dev/null; then
        log_error "Systemd is required but not found."
        exit 1
    fi
    
    log_success "System requirements validated."
}

detect_system() {
    log_info "Detecting system architecture and OS..."
    
    # Architecture detection
    case $(uname -m) in
        x86_64) SYSTEM_ARCH="amd64" ;;
        aarch64|arm64) SYSTEM_ARCH="arm64" ;;
        armv7l) SYSTEM_ARCH="armv7" ;;
        i386|i686) SYSTEM_ARCH="386" ;;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    
    # OS detection
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        SYSTEM_OS="$ID"
    else
        SYSTEM_OS="unknown"
    fi
    
    log_success "Detected: ${SYSTEM_OS} on ${SYSTEM_ARCH}"
}

check_existing_installation() {
    if [[ -f "$INSTALL_DIR/mosdns" ]]; then
        log_warning "Existing mosdns installation detected."
        echo -e "${YELLOW}Please choose an option:${NC}"
        echo "  1) Reinstall (recommended for a clean setup)"
        echo "  2) Upgrade configuration only"
        echo "  3) Cancel installation"
        
        while true; do
            read -p "Enter your choice [1-3]: " choice
            case $choice in
                1) log_info "Proceeding with full reinstallation..."; break ;;
                2) upgrade_config_only; exit 0 ;;
                3) log_info "Installation cancelled."; exit 0 ;;
                *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}" ;;
            esac
        done
    fi
}

# --- Installation Functions ---
install_dependencies() {
    log_info "Installing system dependencies..."
    
    case "$SYSTEM_OS" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y --no-install-recommends curl unzip ca-certificates
            ;;
        centos|rhel|fedora|almalinux|rocky)
            if command -v dnf &>/dev/null; then
                dnf install -y curl unzip ca-certificates
            else
                yum install -y curl unzip ca-certificates
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm --needed curl unzip ca-certificates
            ;;
        *)
            log_warning "Unknown OS detected. Attempting generic installation..."
            if ! (command -v curl && command -v unzip) &>/dev/null; then
                log_error "Please manually install: curl, unzip"
                exit 1
            fi
            ;;
    esac
    
    log_success "Dependencies installed successfully."
}

fetch_latest_version() {
    log_info "Fetching latest version from GitHub..."
    
    local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    
    if ! LATEST_VERSION=$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" | \
                         grep '"tag_name"' | \
                         sed -E 's/.*"([^"]+)".*/\1/'); then
        log_error "Failed to fetch version information from GitHub."
        log_info "Please check your internet connection and GitHub availability."
        exit 1
    fi
    
    if [[ -z "$LATEST_VERSION" ]]; then
        log_error "Could not determine the latest version."
        exit 1
    fi
    
    log_success "Latest version: ${CYAN}$LATEST_VERSION${NC}"
}

download_and_install_binary() {
    log_info "Downloading mosdns-x binary..."
    
    local download_url="https://github.com/$GITHUB_REPO/releases/download/$LATEST_VERSION/mosdns-linux-$SYSTEM_ARCH.zip"
    temp_dir=$(mktemp -d)
    
    # Download with curl, with progress bar and retry logic
    if ! curl -L --progress-bar --fail --retry 3 --retry-delay 2 \
              "$download_url" -o "$temp_dir/mosdns.zip"; then
        log_error "Download failed. Please check your connection and the release URL."
        cleanup
        exit 1
    fi
    
    # Verify download
    if [[ ! -s "$temp_dir/mosdns.zip" ]]; then
        log_error "Downloaded file is empty or corrupted."
        cleanup
        exit 1
    fi
    
    log_info "Extracting and installing binary..."
    
    if ! unzip -qq "$temp_dir/mosdns.zip" -d "$temp_dir"; then
        log_error "Failed to extract downloaded file."
        cleanup
        exit 1
    fi
    
    # Stop existing service if running
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # Install binary
    install -m 755 "$temp_dir/mosdns" "$INSTALL_DIR/"
    
    # Verify installation
    if ! "$INSTALL_DIR/mosdns" version &>/dev/null; then
        log_error "Binary installation failed or corrupted."
        cleanup
        exit 1
    fi
    
    cleanup
    log_success "Binary installed successfully."
}

create_optimized_config() {
    log_info "Creating optimized configuration..."
    
    mkdir -p "$CONFIG_DIR"
    # Explicitly remove any old config file to prevent issues
    rm -f "$CONFIG_DIR/config.yaml"
    
    cat > "$CONFIG_DIR/config.yaml" << 'EOF'
# High-performance configuration for mosdns-x v5+
# Generated by the ultra-optimized installation script.

log:
  level: info
  file: "/var/log/mosdns.log"

include: []

plugins:
  # DNS cache for improved performance
  - tag: cache
    type: cache
    args:
      size: 16384
      min_ttl: 60
      max_ttl: 3600
      dump_file: "cache.dump"

  # ECS support for better CDN performance
  - tag: ecs
    type: ecs
    args:
      auto: true
      ipv4_mask: 24

  # Forward queries to reliable upstream servers
  - tag: forward_remote
    type: forward
    args:
      upstream:
        # Primary: DNS-over-QUIC (fastest)
        - addr: "quic://dns.google"
        - addr: "quic://1.1.1.1"
        # Secondary: DNS-over-HTTPS (secure)
        - addr: "https://dns.google/dns-query"
        - addr: "https://1.1.1.1/dns-query"
        # Tertiary: DNS-over-TLS (secure)
        - addr: "tls://dns.google"
        - addr: "tls://1.1.1.1"
        # Fallback: Standard DNS
        - addr: "8.8.8.8:53"
        - addr: "1.1.1.1:53"
      concurrency: 2

  # Main execution sequence
  - tag: main_sequence
    type: sequence
    args:
      exec:
        - ecs
        - cache
        - forward_remote

servers:
  - exec: main_sequence
    idle_timeout: 10s # Timeout for TCP connections
    listeners:
      - protocol: udp
        addr: "0.0.0.0:53"
      - protocol: tcp
        addr: "0.0.0.0:53"
EOF

    # Set proper permissions
    chmod 644 "$CONFIG_DIR/config.yaml"
    
    log_success "Optimized configuration created."
}

setup_systemd_service() {
    log_info "Setting up systemd service..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Mosdns-x High-Performance DNS Server
Documentation=https://github.com/pmkol/mosdns-x/wiki
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/mosdns start -c $CONFIG_DIR/config.yaml -d $CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=23
LimitNOFILE=65536
LimitNPROC=65536
# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$CONFIG_DIR /var/log
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service configured."
}

configure_logging() {
    log_info "Setting up logging..."
    
    # Create log file with proper permissions
    touch "$LOG_FILE"
    chown root:root "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Setup log rotation
    cat > "/etc/logrotate.d/$SERVICE_NAME" << EOF
$LOG_FILE {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    postrotate
        /bin/systemctl reload $SERVICE_NAME > /dev/null 2>&1 || true
    endscript
}
EOF

    log_success "Logging configured with rotation."
}

start_and_enable_service() {
    log_info "Enabling and starting service..."
    
    systemctl enable "$SERVICE_NAME" &>/dev/null
    systemctl restart "$SERVICE_NAME"
    
    # Wait and verify service is running with a retry loop
    log_info "Waiting for service to become active..."
    local retries=5
    local interval=2
    for i in $(seq 1 $retries); do
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "Service started successfully."
            return 0
        fi
        sleep $interval
    done
    
    log_error "Service failed to start."
    log_info "Dumping last 15 lines from systemd journal:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 15
    echo
    log_info "Dumping last 15 lines from mosdns log file:"
    tail -n 15 "$LOG_FILE"
    exit 1
}

configure_firewall() {
    log_info "Configuring firewall rules..."
    
    local firewall_configured=false
    
    # UFW (Ubuntu/Debian)
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow 53/tcp comment "Mosdns DNS" &>/dev/null
        ufw allow 53/udp comment "Mosdns DNS" &>/dev/null
        firewall_configured=true
        log_success "UFW rules for port 53 (TCP/UDP) added."
    fi
    
    # FirewallD (CentOS/RHEL/Fedora)
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=dns &>/dev/null
        firewall-cmd --reload &>/dev/null
        firewall_configured=true
        log_success "FirewallD rules for DNS service added."
    fi
    
    if ! $firewall_configured; then
        log_warning "No active firewall detected. Please ensure port 53 (TCP/UDP) is accessible."
    fi
}

run_dns_test() {
    log_info "Running DNS functionality test..."
    
    # Wait for service to fully initialize
    sleep 2
    
    # Test DNS resolution
    if timeout 5 nslookup google.com 127.0.0.1 &>/dev/null; then
        log_success "DNS test passed - service is resolving queries correctly."
    else
        log_warning "DNS test failed. The service might be running but unable to resolve external domains."
        log_info "Check logs for upstream errors with: journalctl -u $SERVICE_NAME -f"
    fi
}

upgrade_config_only() {
    log_info "Upgrading configuration only..."
    
    if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
        local backup_file="$CONFIG_DIR/config.yaml.backup.$(date +%s)"
        cp "$CONFIG_DIR/config.yaml" "$backup_file"
        log_info "Existing config backed up to $backup_file"
    fi
    
    create_optimized_config
    log_info "Restarting service with new configuration..."
    systemctl restart "$SERVICE_NAME" 2>/dev/null || true
    
    log_success "Configuration upgraded successfully."
}

show_completion_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║    🎉 Mosdns-x Installation Completed Successfully! 🎉   ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📋 Installation Summary:${NC}"
    echo -e "  ${YELLOW}Version:${NC}        $LATEST_VERSION"
    echo -e "  ${YELLOW}Binary:${NC}         $INSTALL_DIR/mosdns"
    echo -e "  ${YELLOW}Configuration:${NC}  $CONFIG_DIR/config.yaml"
    echo -e "  ${YELLOW}Log File:${NC}       $LOG_FILE"
    echo -e "  ${YELLOW}Service Status:${NC} $(systemctl is-active $SERVICE_NAME)"
    echo
    echo -e "${CYAN}🎛️  Service Management:${NC}"
    echo -e "  ${YELLOW}Status:${NC}    systemctl status $SERVICE_NAME"
    echo -e "  ${YELLOW}Start:${NC}     systemctl start $SERVICE_NAME"
    echo -e "  ${YELLOW}Stop:${NC}      systemctl stop $SERVICE_NAME"
    echo -e "  ${YELLOW}Restart:${NC}   systemctl restart $SERVICE_NAME"
    echo -e "  ${YELLOW}Logs:${NC}      journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${CYAN}🧪 Testing:${NC}"
    echo -e "  ${YELLOW}Local Test:${NC} nslookup google.com 127.0.0.1"
    echo -e "  ${YELLOW}Dig Test:${NC}   dig @127.0.0.1 google.com"
    echo
    echo -e "${CYAN}🔧 Configuration Features:${NC}"
    echo -e "  ${YELLOW}•${NC} DNS-over-QUIC, DoH, DoT"
    echo -e "  ${YELLOW}•${NC} ECS optimization for CDN"
    echo -e "  ${YELLOW}•${NC} 16K entry cache with TTL control"
    echo -e "  ${YELLOW}•${NC} Concurrent upstream queries"
    echo
    echo -e "${YELLOW}💡 To use this DNS server, set your system/router DNS to this server's IP address.${NC}"
    echo
}

# --- Uninstall Function ---
uninstall_mosdns() {
    log_info "Starting mosdns-x uninstallation..."
    
    if [[ ! -f "$INSTALL_DIR/mosdns" && ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        log_error "Mosdns-x does not appear to be installed."
        exit 1
    fi
    
    log_info "Stopping and disabling service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    log_info "Removing files and configurations..."
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -f "$INSTALL_DIR/mosdns"
    rm -f "/etc/logrotate.d/$SERVICE_NAME"
    
    systemctl daemon-reload
    
    read -p "Remove configuration directory ($CONFIG_DIR) and logs? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f "$LOG_FILE"
        log_success "Configuration and logs removed."
    fi
    
    log_success "Mosdns-x uninstalled successfully."
}

# --- Help Function ---
show_help() {
    cat << EOF
🚀 Mosdns-x Ultra-Optimized Management Script

Usage: $0 [command]

Commands:
  install      Install or reinstall mosdns-x (default)
  uninstall    Remove mosdns-x from the system
  upgrade      Upgrade configuration to the latest optimized version
  test         Run a series of DNS functionality tests
  status       Show service status and information
  help         Display this help message

Examples:
  sudo $0                    # Install with default settings
  sudo $0 install            # Same as above
  sudo $0 upgrade            # Upgrade configuration only
  sudo $0 uninstall          # Remove mosdns-x
  $0 status                  # Show current status (no sudo needed)
  $0 test                    # Test DNS functionality

EOF
}

show_status() {
    echo -e "${CYAN}📊 Mosdns-x Status Information${NC}"
    echo
    
    if [[ -f "$INSTALL_DIR/mosdns" ]]; then
        echo -e "${GREEN}✅ Binary installed:${NC} $INSTALL_DIR/mosdns"
        echo -e "${GREEN}✅ Version:${NC} $($INSTALL_DIR/mosdns version 2>/dev/null || echo 'Unknown')"
    else
        echo -e "${RED}❌ Binary not found${NC}"
        return 1
    fi
    
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        echo -e "${GREEN}✅ Service configured:${NC} $SERVICE_NAME"
        echo -e "${GREEN}✅ Service status:${NC} $(systemctl is-active $SERVICE_NAME 2>/dev/null || echo 'inactive')"
        echo -e "${GREEN}✅ Service enabled:${NC} $(systemctl is-enabled $SERVICE_NAME 2>/dev/null || echo 'disabled')"
    else
        echo -e "${RED}❌ Service not configured${NC}"
    fi
    
    if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
        echo -e "${GREEN}✅ Configuration:${NC} $CONFIG_DIR/config.yaml"
    else
        echo -e "${RED}❌ Configuration missing${NC}"
    fi
    
    echo
}

test_dns_functionality() {
    log_info "Testing DNS functionality..."
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "Service is not running."
        exit 1
    fi
    
    echo "Testing various DNS queries via 127.0.0.1..."
    
    local test_domains=("google.com" "cloudflare.com" "github.com")
    local success_count=0
    
    for domain in "${test_domains[@]}"; do
        echo -n "Testing $domain... "
        if timeout 10 nslookup "$domain" 127.0.0.1 &>/dev/null; then
            echo -e "${GREEN}✅ OK${NC}"
            ((success_count++))
        else
            echo -e "${RED}❌ FAILED${NC}"
        fi
    done
    
    echo
    if [[ $success_count -eq ${#test_domains[@]} ]]; then
        log_success "All DNS tests passed successfully!"
    else
        log_warning "$success_count/${#test_domains[@]} tests passed. Check service logs for upstream issues."
    fi
}

# --- Main Function ---
main() {
    case "${1:-install}" in
        install)
            show_banner
            check_requirements
            detect_system
            check_existing_installation
            install_dependencies
            fetch_latest_version
            download_and_install_binary
            create_optimized_config
            setup_systemd_service
            configure_logging
            start_and_enable_service
            configure_firewall
            run_dns_test
            show_completion_summary
            ;;
        uninstall)
            check_requirements
            uninstall_mosdns
            ;;
        upgrade)
            check_requirements
            upgrade_config_only
            ;;
        status)
            show_status
            ;;
        test)
            test_dns_functionality
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

# Execute main function with all provided arguments
main "$@"
