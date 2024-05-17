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

# 更新 sysctl 設置
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.rmem_default=26214400

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

# 启用 FQ
echo "启用 FQ..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
sysctl -p

# 检查 FQ 是否成功启用
echo "验证 FQ..."
if sysctl net.core.default_qdisc | grep -q "fq"; then
    echo "FQ 已成功启用"
else
    echo "FQ 启用失败"
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

# 优化 TCP 窗口大小
echo "优化 TCP 窗口大小..."
echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
echo "net.ipv4.tcp_rmem = 4096 87380 16777216" >> /etc/sysctl.conf
echo "net.ipv4.tcp_wmem = 4096 65536 16777216" >> /etc/sysctl.conf
sysctl -p

# 检查 TCP 窗口大小是否成功优化
echo "验证 TCP 窗口大小..."
if [[ $(sysctl net.core.rmem_max | awk '{print $3}') -eq 16777216 ]] && \
   [[ $(sysctl net.core.wmem_max | awk '{print $3}') -eq 16777216 ]] && \
   [[ $(sysctl net.ipv4.tcp_rmem | awk '{print $3}') -eq 16777216 ]] && \
   [[ $(sysctl net.ipv4.tcp_wmem | awk '{print $3}') -eq 16777216 ]]; then
    echo "TCP 窗口大小已成功优化"
else
    echo "TCP 窗口大小优化失败"
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
