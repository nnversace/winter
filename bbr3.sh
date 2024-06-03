#!/bin/bash

# 下載最新的 .deb 文件
wget -q --show-progress $(wget -q -O - https://api.github.com/repos/love4taylor/linux-self-use-deb/releases/latest | jq -r '.assets[] | select(.name | contains ("deb")) | select(.name | contains ("cloud")) | .browser_download_url')

# 安裝下載的 .deb 文件
sudo dpkg -i linux-headers-*-egoist-cloud_*.deb && sudo dpkg -i linux-image-*-egoist-cloud_*.deb

# 設置 TCP 擁塞控制算法為 BBR
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 顯示當前 TCP 擁塞控制算法
sysctl net.ipv4.tcp_congestion_control

# 顯示可用的 TCP 擁塞控制算法
sysctl net.ipv4.tcp_available_congestion_control
