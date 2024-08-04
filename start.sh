#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "Error: You must be root to run this script"
    exit 1
fi

# Function to check and install a package if not already installed
check_and_install() {
    if ! dpkg -l | grep -q "$1"; then
        apt-get install -y "$1"
    else
        echo "$1 is already installed"
    fi
}

# Update and upgrade system
echo "Updating and upgrading system..."
apt-get update && apt-get full-upgrade -y

# Install curl if not installed
check_and_install "curl"

# Install jq if not installed
check_and_install "jq"

# Install wget if not installed
check_and_install "wget"

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com | bash -s docker

# Configure TCP fast open
echo "Configuring TCP fast open..."
echo "3" > /proc/sys/net/ipv4/tcp_fastopen
echo "net.ipv4.tcp_fastopen=3" > /etc/sysctl.d/30-tcp_fastopen.conf

# Download the latest release of linux-self-use-deb
echo "Downloading the latest release of linux-self-use-deb..."
wget -q --show-progress $(wget -q -O - https://api.github.com/repos/love4taylor/linux-self-use-deb/releases/latest | jq -r '.assets[] | select(.name | contains("deb")) | select(.name | contains("cloud")) | .browser_download_url')

# Install the downloaded packages
echo "Installing the downloaded packages..."
dpkg -i linux-headers-*-egoist-cloud_*.deb && dpkg -i linux-image-*-egoist-cloud_*.deb

# Remove the downloaded packages after installation
echo "Cleaning up downloaded packages..."
rm -f linux-headers-*-egoist-cloud_*.deb linux-image-*-egoist-cloud_*.deb

echo "Script execution completed."
