#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]
  then echo "请以root权限运行此脚本"
  exit
fi

# 安装smartdns
apt-get update
apt-get install -y smartdns

# 创建smartdns配置文件
cat > /etc/smartdns/smartdns.conf <<EOF
bind :53@lo -no-dualstack-selection -no-speed-check
speed-check-mode none
force-AAAA-SOA yes
server 8.8.8.8
server 1.1.1.1
EOF

# 启用并启动smartdns服务
systemctl enable smartdns
systemctl start smartdns

# 配置resolv.conf
chattr -i /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF
chattr +i /etc/resolv.conf

# 测试smartdns
nslookup -querytype=ptr smartdns

echo "smartdns安装和配置完成"
