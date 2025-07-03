#!/bin/sh

set -euo pipefail
LOG_FILE="/var/log/kernel_optimization.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $*" | tee -a "$LOG_FILE"
}

check_and_install() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "$1 未安装，正在安装..."
        apk add --no-cache "$1"
    else
        log "$1 已安装，跳过安装。"
    fi
}

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户运行。" >&2
    exit 1
fi

log "🔧 更新系统 & 安装必要工具..."
apk update && apk upgrade --no-cache
check_and_install jq
check_and_install wget
check_and_install bind-tools  # 替代 dnsutils

log "🐳 安装 Docker & Compose..."
if ! command -v docker >/dev/null 2>&1; then
    apk add --no-cache docker
    rc-update add docker boot
    service docker start
else
    log "Docker 已安装"
fi

if ! docker compose version >/dev/null 2>&1; then
    apk add --no-cache docker-cli-compose
else
    log "docker-compose 插件已安装"
fi

log "📥 执行外部优化脚本（nexttrace）..."

wget -qO- https://github.com/sjlleo/nexttrace/raw/main/nt_install.sh | sh

log "🚀 配置 sing-box..."
mkdir -p /root/sing-box/config
cat > /root/sing-box/docker-compose.yml <<EOF
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

cat > /root/sing-box/config/config.json <<EOF
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

log "🚀 配置 snell..."
mkdir -p /root/snell
cat > /root/snell/docker-compose.yml <<EOF
services:
  snell-server:
    image: vocrx/snell-server:latest
    container_name: snell-server
    restart: always
    network_mode: host
    environment:
      PORT: 5310
      PSK: IUmuU/NjIQhHPMdBz5WONA==
      IPV6: false
EOF

log "🔧 应用内核参数优化..."
SYSCTL_CONF="/etc/sysctl.conf"
echo "" > "$SYSCTL_CONF"
cat >> "$SYSCTL_CONF" <<EOF
fs.file-max = 1048576
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.route.gc_timeout = 100
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.conf.all.route_localnet = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
EOF

if modprobe tcp_bbr 2>/dev/null; then
    echo "net.core.default_qdisc = fq" >> "$SYSCTL_CONF"
    echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    log "✅ BBR 模块启用成功"
else
    log "⚠️ 当前内核不支持 BBR，跳过设置"
fi

sysctl -p >> "$LOG_FILE" 2>&1

log "🛠️ 修改 SSH 配置..."
sed -i 's/#Port 22/Port 14566/' /etc/ssh/sshd_config || true
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true

if [ -x /etc/init.d/sshd ]; then
    rc-service sshd restart
else
    log "⚠️ sshd 服务未找到，未重启"
fi

log "🌐 修改 DNS 配置..."
echo "nameserver 8.8.8.8" > /etc/resolv.conf

log "🚀 启动 sing-box 容器..."
cd /root/sing-box
docker compose pull && docker compose up -d

log "🚀 启动 snell 容器..."
cd /root/snell
docker compose pull && docker compose up -d

clear
echo "✅ 所有步骤完成！服务已部署完毕！" | tee -a "$LOG_FILE"
cat << "EOF"

╔════════════════════════════════════════════════════════╗
║                      ✅ 完成提示                       ║
╠════════════════════════════════════════════════════════╣
║ 🔐 SSH 已配置：                                        ║
║    • 端口已修改为 👉 14566                             ║
║    • 密码登录已禁用 ✅                                 ║
║    • 仅支持密钥登录，请确保密钥已正确部署             ║
╠════════════════════════════════════════════════════════╣
║ 🌐 网络配置：                                          ║
║    • 系统 DNS 已设置为：8.8.8.8                       ║
╠════════════════════════════════════════════════════════╣
║ 🚀 服务状态：                                          ║
║    • sing-box ✅ 已部署并运行中                        ║
║    • snell    ✅ 已部署并运行中                        ║
╚════════════════════════════════════════════════════════╝

EOF
