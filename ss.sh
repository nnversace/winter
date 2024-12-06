#!/bin/bash

# 创建 SS-Rust 目录和配置文件
mkdir -p /root/ss-rust/

cat > /root/ss-rust/docker-compose.yml << EOF
services:
  ss-rust:
    image: vocrx/ss-rust:latest
    container_name: ss-rust
    restart: always
    network_mode: host
    environment:
      - LEVEL=1
      - PORT=65271
      - PASSWORD=K6zMgp5kAIQMO01xp8efhxRgjh4iAqVpbHXZUr1FC+c=
      - METHOD=2022-blake3-chacha20-poly1305
      - MODE=tcp_and_udp
EOF

# 创建 Snell 目录和配置文件
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

# 部署 SS-Rust
cd /root/ss-rust
docker compose pull && docker compose up -d

# 部署 Snell
cd /root/snell
docker compose pull && docker compose up -d

echo "SS-Rust 和 Snell 服务已成功部署！"
