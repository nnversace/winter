#!/bin/bash

# 创建 sing-box 目录和配置文件
mkdir -p /root/sing-box/config

cat > /root/sing-box/docker-compose.yml << EOF
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box
    container_name: sb
    restart: always
    network_mode: host
    volumes:
      - ./config:/etc/sing-box
    command: -D /var/lib/sing-box -C /etc/sing-box/ run
EOF

cat > /root/sing-box/config/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 52171,
      "method": "2022-blake3-chacha20-poly1305",
      "password": "K6zMgp5kAIQMO01xp8efhxRgjh4iAqVpbHXZUr1FC+c=",
      "multiplex": {
        "enabled": true,
        "padding": true
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-no",
      "listen": "::",
      "listen_port": 52071,
      "method": "none",
      "password": "IUmuU/NjIQhHPMdBz5WONA==",
      "multiplex": {
        "enabled": true,
        "padding": false
      }
    }
  ]
}
EOF


# 创建 snell 目录和配置文件
mkdir -p /root/snell/

cat > /root/snell/docker-compose.yml << EOF
services:
  snell:
    image: accors/snell:latest
    container_name: snell
    restart: always
    network_mode: host
    volumes:
      - ./snell.conf:/etc/snell-server.conf
    environment:
      - SNELL_URL=https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip
EOF

cat > /root/snell/snell.conf << EOF
[snell-server]
listen = ::0:5310
psk = IUmuU/NjIQhHPMdBz5WONA==
ipv6 = false
EOF

# 部署 singbox
cd /root/singbox
docker compose pull && docker compose up -d

# 部署 snell
cd /root/snell
docker compose pull && docker compose up -d

echo "singbox 和 snell 已成功部署！"
