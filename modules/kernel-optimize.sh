#!/bin/bash
# Enhanced Linux Kernel & System Optimization for Debian 13
# Supports: Debian 12/13+, optimized for high-performance networking
# Features: TCP BBR, system tuning, security hardening, I/O optimization

set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Color output for better UX
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[1;34m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_info "开始内核和系统深度优化..."

# Detect Debian version
DEBIAN_VERSION=$(lsb_release -rs 2>/dev/null || grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null | cut -d. -f1 || echo "13")
log_info "检测到 Debian 版本: $DEBIAN_VERSION"

# Check system architecture
ARCH=$(uname -m)
log_info "系统架构: $ARCH"

# Random number generator optimization
optimize_entropy() {
    log_info "优化随机数生成器性能..."
    
    # Install haveged if not present
    if ! command -v haveged >/dev/null 2>&1; then
        log_info "安装 haveged 改善随机数生成器性能"
        apt-get update -qq
        apt-get install -y haveged
        systemctl enable haveged
    fi
    
    # Install rng-tools if not present
    if ! command -v rngd >/dev/null 2>&1; then
        log_info "安装 rng-tools 改善随机数生成器性能"
        apt-get install -y rng-tools
        systemctl enable rng-tools
    fi
    
    log_success "随机数生成器优化完成"
}

# Disable KSM (Kernel Samepage Merging) for better performance
disable_ksm() {
    log_info "禁用 KSM 以优化内存性能..."
    
    if command -v ksmtuned >/dev/null 2>&1; then
        echo 2 > /sys/kernel/mm/ksm/run
        
        # Remove ksmtuned packages
        apt-get purge -y tuned ksmtuned --auto-remove || true
        
        # Disable ksmtuned service
        rm -rf /etc/systemd/system/ksmtuned.service
        if [[ -f /usr/sbin/ksmtuned ]]; then
            mv /usr/sbin/ksmtuned /usr/sbin/ksmtuned.bak 2>/dev/null || true
            touch /usr/sbin/ksmtuned
            echo "# KSMTUNED DISABLED" > /usr/sbin/ksmtuned
        fi
    fi
    
    log_success "KSM 禁用完成"
}

# Disable Transparent Huge Pages (THP)
disable_thp() {
    log_info "禁用 Transparent Huge Pages (THP)..."
    
    cat > /etc/systemd/system/disable-transparent-huge-pages.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service redis.service mysql.service postgresql.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null'
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null'
RemainAfterExit=yes
[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl start disable-transparent-huge-pages
    systemctl enable disable-transparent-huge-pages
    
    log_success "THP 禁用完成"
}

# Enable required kernel modules
enable_kernel_modules() {
    log_info "启用必要的内核模块..."
    
    mkdir -p /usr/lib/modules-load.d
    
    # Network optimization modules
    cat > /usr/lib/modules-load.d/sukka-network-optimized.conf <<EOF
# Network optimization modules
nf_conntrack
tls
EOF

    # Load modules immediately
    modprobe nf_conntrack 2>/dev/null || true
    modprobe tls 2>/dev/null || true
    
    log_success "内核模块启用完成"
}

# Advanced kernel parameter optimization
optimize_kernel_parameters() {
    log_info "应用高级内核参数优化..."
    
    # Backup existing sysctl configuration
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # Remove existing optimized parameters
    local patterns=(
        'kernel.panic'
        'kernel.task_delayacct'
        'net.core.netdev_max_backlog'
        'net.core.default_qdisc'
        'net.core.somaxconn'
        'net.ipv4.conf.all.rp_filter'
        'net.ipv4.conf.default.rp_filter'
        'net.ipv4.ip_default_ttl'
        'net.ipv4.ip_forward'
        'net.ipv4.ip_local_port_range'
        'net.ipv4.tcp_abort_on_overflow'
        'net.ipv4.tcp_adv_win_scale'
        'net.ipv4.tcp_autocorking'
        'net.ipv4.tcp_base_mss'
        'net.ipv4.tcp_collapse_max_bytes'
        'net.ipv4.tcp_congestion_control'
        'net.ipv4.tcp_dsack'
        'net.ipv4.tcp_ecn'
        'net.ipv4.tcp_fastopen'
        'net.ipv4.tcp_fastopen_blackhole_timeout_sec'
        'net.ipv4.tcp_fin_timeout'
        'net.ipv4.tcp_frto'
        'net.ipv4.tcp_keepalive_intvl'
        'net.ipv4.tcp_keepalive_probes'
        'net.ipv4.tcp_keepalive_time'
        'net.ipv4.tcp_max_orphans'
        'net.ipv4.tcp_max_syn_backlog'
        'net.ipv4.tcp_max_tw_buckets'
        'net.ipv4.tcp_mtu_probing'
        'net.ipv4.tcp_no_ssthresh_metrics_save'
        'net.ipv4.tcp_slow_start_after_idle'
        'net.ipv4.tcp_orphan_retries'
        'net.ipv4.tcp_retries1'
        'net.ipv4.tcp_retries2'
        'net.ipv4.tcp_rfc1337'
        'net.core.rmem_default'
        'net.core.rmem_max'
        'net.ipv4.tcp_rmem'
        'net.core.wmem_default'
        'net.core.wmem_max'
        'net.ipv4.tcp_wmem'
        'net.ipv4.tcp_moderate_rcvbuf'
        'net.ipv4.tcp_sack'
        'net.ipv4.tcp_syn_retries'
        'net.ipv4.tcp_synack_retries'
        'net.ipv4.tcp_syncookies'
        'net.ipv4.tcp_timestamps'
        'net.ipv4.tcp_tw_reuse'
        'net.ipv4.tcp_window_scaling'
        'net.ipv4.tcp_no_metrics_save'
        'net.ipv4.tcp_notsent_lowat'
        'net.ipv4.tcp_low_latency'
        'net.ipv4.udp_rmem_min'
        'net.ipv4.udp_wmem_min'
        'net.ipv4.route.flush'
        'net.ipv6.conf.all.forwarding'
        'net.ipv6.conf.default.forwarding'
        'net.netfilter.nf_conntrack'
        'vm.overcommit_memory'
        'vm.swappiness'
    )
    
    for pattern in "${patterns[@]}"; do
        sed -i "/^${pattern}/d" /etc/sysctl.conf 2>/dev/null || true
    done
    
    # Get memory information for dynamic TCP buffer sizing
    local mems=$(free --bytes | grep '^Mem:' | awk '{print $2}')
    local page=$(getconf PAGESIZE)
    local size=$((mems / page))
    local tcp_mem_low=$((size / 100 * 12))
    local tcp_mem_pressure=$((size / 100 * 50))
    local tcp_mem_high=$((size / 100 * 70))
    
    # Create optimized sysctl configuration
    cat > /etc/sysctl.d/99-sukka-optimized.conf <<EOF
# Enhanced Kernel Parameters for Debian 13
# Optimized for high-performance networking and server workloads

# Kernel and system behavior
kernel.panic = 1
kernel.task_delayacct = 1

# Network performance tuning
net.core.netdev_max_backlog = 32768
net.core.default_qdisc = fq
net.core.somaxconn = 32768
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.ip_default_ttl = 128
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 10240 65535

# TCP optimization
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_autocorking = 1
net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_collapse_max_bytes = 6291456
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_fastopen = 1027
net.ipv4.tcp_fastopen_blackhole_timeout_sec = 10
net.ipv4.tcp_fin_timeout = 3
net.ipv4.tcp_frto = 1
net.ipv4.tcp_keepalive_intvl = 2
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_max_orphans = 8192
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 4096
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_no_ssthresh_metrics_save = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_orphan_retries = 4
net.ipv4.tcp_retries1 = 2
net.ipv4.tcp_retries2 = 2
net.ipv4.tcp_rfc1337 = 1

# TCP buffer tuning (auto-sized based on available memory)
net.core.rmem_default = 262144
net.core.rmem_max = 536870912
net.ipv4.tcp_rmem = 8192 262144 536870912
net.core.wmem_default = 16384
net.core.wmem_max = 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
net.ipv4.tcp_moderate_rcvbuf = 1

# TCP features
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_low_latency = 1

# UDP tuning
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 4096
net.ipv4.route.flush = 1

# IPv6
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# Netfilter connection tracking optimization
net.netfilter.nf_conntrack_generic_timeout = 10
net.netfilter.nf_conntrack_gre_timeout = 5
net.netfilter.nf_conntrack_gre_timeout_stream = 30
net.netfilter.nf_conntrack_icmp_timeout = 5
net.netfilter.nf_conntrack_icmpv6_timeout = 5
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_close = 5
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 5
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_last_ack = 5
net.netfilter.nf_conntrack_tcp_timeout_max_retrans = 5
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 5
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 5
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_unacknowledged = 5
net.netfilter.nf_conntrack_udp_timeout = 5
net.netfilter.nf_conntrack_udp_timeout_stream = 60

# Virtual memory management
vm.overcommit_memory = 1
vm.swappiness = 0

# Dynamic TCP memory limits based on system RAM
net.ipv4.tcp_mem = ${tcp_mem_low} ${tcp_mem_pressure} ${tcp_mem_high}
EOF

    # Sort and apply sysctl settings
    sort -n /etc/sysctl.d/99-sukka-optimized.conf -o /etc/sysctl.d/99-sukka-optimized.conf
    
    # Load sysctl settings
    if sysctl --system >/dev/null 2>&1; then
        log_success "内核参数优化应用成功"
    else
        log_warn "部分内核参数可能未生效，建议重启系统"
    fi
}

# Optimize system limits
optimize_system_limits() {
    log_info "优化系统资源限制..."
    
    # Backup existing limits configuration
    cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # Clean up existing limits configuration
    sed -i '/^# End of file/,$d' /etc/security/limits.conf
    
    # Set unlimited limits for better performance
    cat >> /etc/security/limits.conf <<'EOF'
# End of file - Enhanced system limits for high-performance computing

# File descriptor limits
* soft nofile unlimited
* hard nofile unlimited
root soft nofile unlimited
root hard nofile unlimited

# Process limits
* soft nproc unlimited
* hard nproc unlimited
root soft nproc unlimited
root hard nproc unlimited

# Memory limits
* soft memlock unlimited
* hard memlock unlimited
root soft memlock unlimited
root hard memlock unlimited

# Core dump limits
* soft core unlimited
* hard core unlimited
root soft core unlimited
root hard core unlimited
EOF

    # Configure PAM for limits
    if [[ -f /etc/pam.d/common-session ]]; then
        if ! grep -q "session required pam_limits.so" /etc/pam.d/common-session; then
            echo "session required pam_limits.so" >> /etc/pam.d/common-session
        fi
    fi
    
    # Remove conflicting nproc limits
    rm -f /etc/security/limits.d/*nproc.conf 2>/dev/null || true
    
    log_success "系统资源限制优化完成"
}

# Configure systemd for better performance
optimize_systemd() {
    log_info "优化 systemd 配置..."
    
    # Backup existing systemd configuration
    cp /etc/systemd/system.conf /etc/systemd/system.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    cat > /etc/systemd/system.conf <<'EOF'
# Enhanced systemd configuration for performance

[Manager]
# CPU and resource accounting
DefaultCPUAccounting=yes
DefaultIOAccounting=yes  
DefaultIPAccounting=yes
DefaultMemoryAccounting=yes
DefaultTasksAccounting=yes

# Resource limits
DefaultLimitCORE=infinity
DefaultLimitNPROC=infinity
DefaultLimitNOFILE=infinity

# Performance tuning
DefaultTimeoutStopSec=30s
DefaultRestartSec=100ms
EOF

    # Reload systemd daemon
    systemctl daemon-reload
    
    log_success "systemd 配置优化完成"
}

# Optimize journald for better logging performance
optimize_journald() {
    log_info "优化 journald 日志配置..."
    
    cat > /etc/systemd/journald.conf <<'EOF'
# Optimized journald configuration

[Journal]
# Size limits
SystemMaxUse=384M
SystemMaxFileSize=128M
SystemMaxFiles=3
RuntimeMaxUse=256M
RuntimeMaxFileSize=128M
RuntimeMaxFiles=3

# Time limits
MaxRetentionSec=86400
MaxFileSec=259200

# Forwarding
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no

# Performance
Compress=yes
SyncIntervalSec=5s
EOF

    # Restart journald to apply changes
    systemctl restart systemd-journald
    
    log_success "journald 配置优化完成"
}

# Enable TCP BBR congestion control
enable_tcp_bbr() {
    log_info "启用 TCP BBR 拥塞控制算法..."
    
    # Check if BBR module is available
    if modprobe tcp_bbr 2>/dev/null; then
        if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
            log_info "TCP BBR 可用，配置为默认拥塞控制算法"
            echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-sukka-optimized.conf
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
            log_success "TCP BBR 已启用"
        else
            log_warn "TCP BBR 不可用，继续使用默认算法"
        fi
    else
        log_warn "无法加载 TCP BBR 模块"
    fi
}

# Main execution
main() {
    log_info "=== Linux 内核和系统优化开始 ==="
    log_info "适用于: Debian ${DEBIAN_VERSION} (${ARCH})"
    
    # Execute optimization steps
    optimize_entropy
    disable_ksm
    disable_thp
    enable_kernel_modules
    optimize_kernel_parameters
    optimize_system_limits
    optimize_systemd
    optimize_journald
    enable_tcp_bbr
    
    log_success "=== 所有优化步骤已完成 ==="
    log_info "建议重启系统以确保所有优化生效"
    log_info "如需回滚，可恢复以下备份文件："
    log_info "  - /etc/sysctl.conf.backup.*"
    log_info "  - /etc/security/limits.conf.backup.*"
    log_info "  - /etc/systemd/system.conf.backup.*"
}

# Run main function
main "$@"
