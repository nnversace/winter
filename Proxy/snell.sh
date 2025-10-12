#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "此脚本必须以 root 权限运行" >&2
  exit 1
fi

# 检测架构
ARCH=$(uname -m)
case $ARCH in
  x86_64)
    ARCH="amd64"
    ;;
  i386 | i686)
    ARCH="i386"
    ;;
  aarch64)
    ARCH="aarch64"
    ;;
  armv7l)
    ARCH="armv7l"
    ;;
  *)
    echo "不支持的架构: $ARCH"
    exit 1
    ;;
esac

# 下载并安装 snell-server
echo "正在为 $ARCH 架构下载 Snell v5..."
wget "https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-${ARCH}.zip" -O snell.zip
if [ $? -ne 0 ]; then
    echo "下载失败，请检查您的网络或下载地址。"
    exit 1
fi


unzip -o snell.zip
if [ $? -ne 0 ]; then
    echo "解压失败，请确认您已安装 unzip。"
    exit 1
fi

mv snell-server /usr/local/bin/
chmod +x /usr/local/bin/snell-server

# 配置 snell-server
echo "正在配置 Snell 服务器..."
PSK=IUmuU/NjIQhHPMdBz5WONA==
PORT=53100

cat > /etc/snell-server.conf <<EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
EOF

# 创建 systemd 服务
echo "正在创建 systemd 服务..."
cat > /etc/systemd/system/snell.service <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/snell-server -c /etc/snell-server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
echo "正在启动 Snell 服务..."
systemctl daemon-reload
systemctl enable snell
systemctl start snell

# 清理
rm snell.zip

# 打印配置信息
echo "Snell v5 安装完成!"
echo "------------------------------"
echo "服务器地址: 您的服务器 IP 地址"
echo "端口: ${PORT}"
echo "PSK: ${PSK}"
echo "版本: v5"
echo "------------------------------"
