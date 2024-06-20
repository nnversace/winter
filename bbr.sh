#!/bin/bash

# 打印当前配置
echo "当前TCP窗口和UDP缓冲区大小设置:"
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
sysctl net.core.rmem_default
sysctl net.core.rmem_max
sysctl net.core.wmem_default
sysctl net.core.wmem_max

# 修改/etc/sysctl.conf文件
echo "修改/etc/sysctl.conf文件..."

sudo tee -a /etc/sysctl.conf > /dev/null <<EOT
# TCP 窗口大小设置
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456

# 启用TCP窗口自动调优
net.ipv4.tcp_window_scaling = 1

# 启用TCP SACK（选择性确认）
net.ipv4.tcp_sack = 1

# 启用TCP timestamps
net.ipv4.tcp_timestamps = 1

# 启用TCP快速重传和恢复（Reno算法）
net.ipv4.tcp_ecn = 1

# UDP 缓冲区大小设置
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216

# 增加内核接收队列长度
net.core.netdev_max_backlog = 250000

# 增加用于接收数据包的最大默认缓冲区大小
net.core.optmem_max = 16777216
EOT

# 应用sysctl.conf中的更改
echo "应用更改..."
sudo sysctl -p

# 修改网络接口队列长度
NETWORK_INTERFACE="eth0"
echo "修改网络接口$NETWORK_INTERFACE队列长度..."
sudo ifconfig $NETWORK_INTERFACE txqueuelen 10000

# 持久化网络接口配置
INTERFACES_FILE="/etc/network/interfaces"
echo "持久化网络接口配置到$INTERFACES_FILE..."
sudo tee -a $INTERFACES_FILE > /dev/null <<EOT

auto $NETWORK_INTERFACE
iface $NETWORK_INTERFACE inet dhcp
    post-up /sbin/ifconfig $NETWORK_INTERFACE txqueuelen 10000
EOT

# 打印新的配置
echo "新的TCP窗口和UDP缓冲区大小设置:"
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
sysctl net.core.rmem_default
sysctl net.core.rmem_max
sysctl net.core.wmem_default
sysctl net.core.wmem_max

echo "TCP和UDP窗口调优完成。"
