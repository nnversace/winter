#!/bin/bash

# 更新軟件包列表
sudo apt-get update

# 检测并安装缺失的软件包
echo "Checking and installing required packages..."
REQUIRED_PKG=("wget" "jq")
for PKG in "${REQUIRED_PKG[@]}"; do
    if ! dpkg -l | grep -q "$PKG"; then
        echo "$PKG is not installed. Installing..."
        sudo apt update
        sudo apt install -y "$PKG"
    else
        echo "$PKG is already installed."
    fi
done

# 获取最新的 GitHub release 包含 "deb" 和 "cloud" 的资产的下载 URL
echo "Fetching the latest release URLs..."
download_urls=$(wget -q -O - https://api.github.com/repos/love4taylor/linux-self-use-deb/releases/latest | jq -r '.assets[] | select(.name | contains ("deb")) | select(.name | contains ("cloud")) | .browser_download_url')

# 下载文件
echo "Downloading the files..."
for url in $download_urls; do
    wget -q --show-progress "$url"
done

# 安装下载的 .deb 文件
echo "Installing downloaded .deb files..."
sudo dpkg -i linux-headers-*-egoist-cloud_*.deb && sudo dpkg -i linux-image-*-egoist-cloud_*.deb

# 删除源文件
echo "Cleaning up downloaded files..."
rm -f linux-headers-*-egoist-cloud_*.deb linux-image-*-egoist-cloud_*.deb

# 修改 /etc/sysctl.conf 文件
echo "Modifying /etc/sysctl.conf..."
sudo sed -i '/net.ipv4.tcp_no_metrics_save/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_frto/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_rfc1337/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_sack/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_fack/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_window_scaling/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_adv_win_scale/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_moderate_rcvbuf/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
sudo sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
sudo sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.udp_rmem_min/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.udp_wmem_min/d' /etc/sysctl.conf
sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.conf.all.route_localnet/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.conf.all.forwarding/d' /etc/sysctl.conf
sudo sed -i '/net.ipv4.conf.default.forwarding/d' /etc/sysctl.conf

sudo bash -c 'cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
EOF'

# 应用 sysctl 配置
echo "Applying sysctl settings..."
sudo sysctl -p && sudo sysctl --system

echo "Script execution completed."
