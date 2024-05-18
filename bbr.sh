#!/bin/bash

# 定义配置项列表
config_items=(
    "net.ipv4.tcp_no_metrics_save"
    "net.ipv4.tcp_ecn"
    "net.ipv4.tcp_frto"
    "net.ipv4.tcp_mtu_probing"
    "net.ipv4.tcp_rfc1337"
    "net.ipv4.tcp_sack"
    "net.ipv4.tcp_fack"
    "net.ipv4.tcp_window_scaling"
    "net.ipv4.tcp_adv_win_scale"
    "net.ipv4.tcp_moderate_rcvbuf"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.ipv4.udp_rmem_min"
    "net.ipv4.udp_wmem_min"
    "net.core.default_qdisc"
    "net.ipv4.tcp_congestion_control"
    "net.ipv4.conf.all.route_localnet"
    "net.ipv4.ip_forward"
    "net.ipv4.conf.all.forwarding"
    "net.ipv4.conf.default.forwarding"
)

# 删除配置项并检测
for item in "${config_items[@]}"; do
    if grep -q "^${item}" /etc/sysctl.conf; then
        sed -i "/^${item}/d" /etc/sysctl.conf
        if grep -q "^${item}" /etc/sysctl.conf; then
            echo "Error: Failed to remove ${item} from /etc/sysctl.conf"
            exit 1
        else
            echo "Removed ${item} from /etc/sysctl.conf"
        fi
    fi
done

# 添加新的配置项
cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=1
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
EOF

# 检测新配置项是否成功添加
new_config_items=(
    "net.ipv4.tcp_no_metrics_save=1"
    "net.ipv4.tcp_ecn=1"
    "net.ipv4.tcp_frto=0"
    "net.ipv4.tcp_mtu_probing=0"
    "net.ipv4.tcp_rfc1337=0"
    "net.ipv4.tcp_sack=1"
    "net.ipv4.tcp_fack=1"
    "net.ipv4.tcp_window_scaling=1"
    "net.ipv4.tcp_adv_win_scale=1"
    "net.ipv4.tcp_moderate_rcvbuf=1"
    "net.core.rmem_max=33554432"
    "net.core.wmem_max=33554432"
    "net.ipv4.tcp_rmem=4096 87380 33554432"
    "net.ipv4.tcp_wmem=4096 16384 33554432"
    "net.ipv4.udp_rmem_min=8192"
    "net.ipv4.udp_wmem_min=8192"
    "net.core.default_qdisc=fq"
    "net.ipv4.tcp_congestion_control=bbr"
    "net.ipv4.conf.all.route_localnet=1"
    "net.ipv4.ip_forward=1"
    "net.ipv4.conf.all.forwarding=1"
    "net.ipv4.conf.default.forwarding=1"
)

for item in "${new_config_items[@]}"; do
    if ! grep -q "^${item}" /etc/sysctl.conf; then
        echo "Error: Failed to add ${item} to /etc/sysctl.conf"
        exit 1
    else
        echo "Added ${item} to /etc/sysctl.conf"
    fi
done

# 重新加载系统参数
sysctl -p && sysctl --system

if [ $? -eq 0 ]; then
    echo "System parameters reloaded successfully."
else
    echo "Error: Failed to reload system parameters."
    exit 1
fi
