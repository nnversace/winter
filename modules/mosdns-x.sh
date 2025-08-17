#!/bin/bash

# Enhanced management script for mosdns-x
# Supports: Install, Uninstall, Reinstall
#
# Author: Gemini
# Inspired by the community and official documentation.

# --- Configuration ---
# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# File and directory paths
INSTALL_DIR="/etc/mosdns"
BIN_FILE="/usr/local/bin/mosdns-x"
SERVICE_FILE="/etc/systemd/system/mosdns-x.service"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
LATEST_API_URL="https://api.github.com/repos/pmkol/mosdns-x/releases/latest"
# --- End Configuration ---


# --- Core Functions ---

# Function to check for root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}This script must be run as root. Please use sudo.${NC}"
        exit 1
    fi
}

# Function to check for required commands (curl, unzip)
check_dependencies() {
    command -v curl >/dev/null 2>&1 || { echo -e >&2 "${RED}Error: curl is not installed. Please install it first.${NC}"; exit 1; }
    command -v unzip >/dev/null 2>&1 || { echo -e >&2 "${RED}Error: unzip is not installed. Please install it first.${NC}"; exit 1; }
}

# Function to detect the system architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7*) echo "armv7" ;;
        *)
            echo -e "${RED}Unsupported architecture: $(uname -m)${NC}"
            exit 1
            ;;
    esac
}


# --- Main Operations ---

# Function to install mosdns-x
install_mosdns() {
    echo -e "${GREEN}Starting the installation of mosdns-x...${NC}"
    check_dependencies

    # Download the latest release
    ARCH=$(detect_arch)
    echo -e "${GREEN}Detected architecture: $ARCH${NC}"

    echo -e "${YELLOW}Fetching the latest release information...${NC}"
    LATEST_INFO=$(curl -s $LATEST_API_URL)
    DOWNLOAD_URL=$(echo "$LATEST_INFO" | grep "browser_download_url" | grep "linux-$ARCH" | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}Could not find a download URL for your architecture.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Downloading the latest mosdns-x...${NC}"
    curl -L -o "/tmp/mosdns-x.zip" "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then echo -e "${RED}Download failed.${NC}"; exit 1; fi

    echo -e "${GREEN}Unzipping the downloaded file...${NC}"
    unzip -o "/tmp/mosdns-x.zip" -d "/tmp/mosdns-x"
    if [ $? -ne 0 ]; then echo -e "${RED}Unzip failed.${NC}"; exit 1; fi

    mv "/tmp/mosdns-x/mosdns-x" "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -rf "/tmp/mosdns-x.zip" "/tmp/mosdns-x"
    echo -e "${GREEN}Binary installed at $BIN_FILE${NC}"

    # Create the configuration file
    mkdir -p "$INSTALL_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Configuration file already exists. Skipping creation.${NC}"
    else
        echo -e "${GREEN}Creating a default configuration file...${NC}"
        cat > "$CONFIG_FILE" << EOF
# mosdns-x configuration file
# For more details, see: https://github.com/pmkol/mosdns-x

log:
  level: info
  file: "$INSTALL_DIR/mosdns.log"

api:
  http: "127.0.0.1:8080"

plugins:
  - tag: main_sequence
    type: sequence
    args:
      - exec: forward_remote
      - exec: fallback_local

  - tag: forward_remote
    type: forward
    args:
      upstreams:
        - addr: https://dns.google/dns-query
        - addr: https://1.1.1.1/dns-query

  - tag: fallback_local
    type: forward
    args:
      upstreams:
        - addr: 223.5.5.5
        - addr: 119.29.29.29

servers:
  - protocol: udp
    addr: ":53"
    plugin: main_sequence
  - protocol: tcp
    addr: ":53"
    plugin: main_sequence
EOF
    fi

    # Create the systemd service
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}systemd service file already exists. Skipping creation.${NC}"
    else
        echo -e "${GREEN}Creating systemd service file...${NC}"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=mosdns-x: A high-performance DNS forwarding engine.
After=network.target

[Service]
Type=simple
ExecStart=$BIN_FILE -d $INSTALL_DIR -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mosdns-x
        echo -e "${GREEN}Service created and enabled.${NC}"
    fi

    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "${GREEN}mosdns-x has been successfully installed!${NC}"
    echo -e "${YELLOW}To start mosdns-x, run:         ${NC}${GREEN}systemctl start mosdns-x${NC}"
    echo -e "${YELLOW}To check the status, run:        ${NC}${GREEN}systemctl status mosdns-x${NC}"
    echo -e "${YELLOW}The configuration file is at:  ${NC}${GREEN}$CONFIG_FILE${NC}"
    echo -e "${GREEN}----------------------------------------${NC}"
}

# Function to uninstall mosdns-x
uninstall_mosdns() {
    echo -e "${YELLOW}Uninstalling mosdns-x...${NC}"

    # Stop and disable the service
    if systemctl is-active --quiet mosdns-x; then
        systemctl stop mosdns-x
        echo "Stopped mosdns-x service."
    fi
    if systemctl is-enabled --quiet mosdns-x; then
        systemctl disable mosdns-x
        echo "Disabled mosdns-x service."
    fi

    read -p "Are you sure you want to remove all mosdns-x files, including configuration? [y/N] " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi

    # Remove files
    rm -f "$BIN_FILE"
    rm -f "$SERVICE_FILE"
    rm -rf "$INSTALL_DIR"
    echo "Removed files: $BIN_FILE, $SERVICE_FILE, and directory $INSTALL_DIR"

    # Reload systemd
    systemctl daemon-reload
    echo "Reloaded systemd daemon."

    echo -e "${GREEN}mosdns-x has been successfully uninstalled.${NC}"
}

# Function to reinstall mosdns-x
reinstall_mosdns() {
    echo -e "${YELLOW}Reinstalling mosdns-x...${NC}"
    uninstall_mosdns
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e "${YELLOW}Proceeding with new installation...${NC}"
    install_mosdns
}


# --- Script Entry Point ---

# Main function to show menu and handle logic
main() {
    check_root

    # Handle command-line arguments
    if [[ $# -gt 0 ]]; then
        case $1 in
            install)
                install_mosdns
                ;;
            uninstall)
                uninstall_mosdns
                ;;
            reinstall)
                reinstall_mosdns
                ;;
            *)
                echo -e "${RED}Invalid argument: $1${NC}"
                echo "Usage: $0 [install|uninstall|reinstall]"
                exit 1
                ;;
        esac
    else
        # Interactive Menu
        echo "----------------------------------------"
        echo "        mosdns-x Management"
        echo "----------------------------------------"
        echo "1. Install mosdns-x"
        echo "2. Uninstall mosdns-x"
        echo "3. Reinstall mosdns-x"
        echo "4. Exit"
        echo "----------------------------------------"
        read -p "Please choose an option [1-4]: " choice

        case $choice in
            1) install_mosdns ;;
            2) uninstall_mosdns ;;
            3) reinstall_mosdns ;;
            4) exit 0 ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                exit 1
                ;;
        esac
    fi
}

# Run the script
main "$@"
