#!/bin/bash

# 更新系统
echo "Updating the system..."
sudo apt update && sudo apt upgrade -y

# 安装必要的软件包
echo "Installing necessary packages..."
sudo apt install -y linux-headers-$(uname -r) linux-image-$(uname -r)

# 配置sysctl
echo "Configuring sysctl for BBR, FQ and ECN..."
sudo tee -a /etc/sysctl.conf > /dev/null <<EOL

# Enable BBR
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Enable ECN
net.ipv4.tcp_ecn=1
EOL

# 应用sysctl配置
echo "Applying sysctl settings..."
sudo sysctl -p

# 验证配置
echo "Verifying the settings..."
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_ecn

echo "Checking if BBR module is loaded..."
lsmod | grep bbr

echo "BBR, FQ, and ECN configuration complete."
