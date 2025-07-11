#!/bin/bash

# 自动检测默认网关对应的接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

# 设置端口范围与目标端口
PORT_RANGE="20000-50000"
HYSTERIA_PORT="5271"

# 检查是否获取到接口
if [ -z "$INTERFACE" ]; then
  echo "无法检测到默认网络接口，退出"
  exit 1
fi

echo "检测到网络接口: $INTERFACE"

# 生成并应用 nftables 配置
nft -f - <<EOF
table inet hysteria_porthopping {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$INTERFACE" udp dport $PORT_RANGE counter redirect to :$HYSTERIA_PORT
  }
}
EOF

echo "nftables 规则已加载：$PORT_RANGE -> :$HYSTERIA_PORT on $INTERFACE"
