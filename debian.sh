#!/bin/bash

# Apply the sysctl settings for Debian 12

cat > /etc/sysctl.conf << 'EOF'
fs.file-max                     = 6815744
net.ipv4.tcp_max_syn_backlog    = 8192
net.core.somaxconn              = 8192
net.ipv4.tcp_tw_reuse           = 1
net.ipv4.tcp_abort_on_overflow  = 1
net.core.default_qdisc          = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_no_metrics_save    = 1
net.ipv4.tcp_ecn                = 0
net.ipv4.tcp_frto               = 0
net.ipv4.tcp_mtu_probing        = 0
net.ipv4.tcp_rfc1337            = 1
net.ipv4.tcp_sack               = 1
net.ipv4.tcp_fack               = 1
net.ipv4.tcp_window_scaling     = 1
net.ipv4.tcp_adv_win_scale      = 2
net.ipv4.tcp_moderate_rcvbuf    = 1
net.ipv4.tcp_fin_timeout        = 30
net.ipv4.tcp_rmem               = 4096 87380 67108864
net.ipv4.tcp_wmem               = 4096 65536 67108864
net.core.rmem_max               = 67108864
net.core.wmem_max               = 67108864
net.ipv4.udp_rmem_min           = 8192
net.ipv4.udp_wmem_min           = 8192
net.ipv4.ip_local_port_range    = 1024 65535
net.ipv4.tcp_timestamps         = 1
net.ipv4.conf.all.rp_filter     = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.ip_forward             = 1
net.ipv6.conf.all.forwarding    = 1
net.ipv6.conf.default.forwarding= 1
net.ipv4.conf.all.route_localnet= 1
EOF

# Reload sysctl settings
sysctl -p && sysctl --system
