#!/bin/bash

# 修改 /etc/resolv.conf 配置
chattr -i /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
chattr +i /etc/resolv.conf

# 更新包列表
apt-get update

# 安裝必要的軟件包
apt-get install -y curl wget sudo

# 安裝 Docker
curl -fsSL https://get.docker.com | bash -s docker

# 启用 BBR
echo "启用 BBR..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 检查 BBR 是否成功启用
echo "验证 BBR..."
if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "BBR 已成功启用"
else
    echo "BBR 启用失败"
fi

# 启用 ECN
echo "启用 ECN..."
echo "net.ipv4.tcp_ecn=1" >> /etc/sysctl.conf
sysctl -p

# 检查 ECN 是否成功启用
echo "验证 ECN..."
if sysctl net.ipv4.tcp_ecn | grep -q "1"; then
    echo "ECN 已成功启用"
else
    echo "ECN 启用失败"
fi

# 开启内核转发
echo "开启内核转发..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 检查内核转发是否成功开启
echo "验证内核转发..."
if sysctl net.ipv4.ip_forward | grep -q "1"; then
    echo "内核转发已成功开启"
else
    echo "内核转发开启失败"
fi

echo "所有设置及验证已完成。"
