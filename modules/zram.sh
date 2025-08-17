#!/bin/bash

# Debian 13 zram 一键启用脚本
# 作者: Claude AI
# 版本: 1.0
# 用途: 自动在 Debian 13 上配置和启用 zram

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_info "检查系统版本..."
    
    if [[ ! -f /etc/debian_version ]]; then
        log_error "此脚本仅适用于 Debian 系统"
        exit 1
    fi
    
    # 获取系统信息
    DEBIAN_VERSION=$(cat /etc/debian_version 2>/dev/null || echo "未知")
    KERNEL_VERSION=$(uname -r)
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    
    log_info "系统信息:"
    echo "  - Debian 版本: $DEBIAN_VERSION"
    echo "  - 内核版本: $KERNEL_VERSION"
    echo "  - 总内存: $TOTAL_RAM"
}

# 检查是否已安装 zram
check_zram_exists() {
    log_info "检查 zram 模块..."
    
    if lsmod | grep -q zram; then
        log_warning "zram 模块已经加载"
        return 0
    fi
    
    if modprobe zram 2>/dev/null; then
        log_success "zram 模块加载成功"
        modprobe -r zram  # 临时卸载，稍后重新配置
        return 0
    else
        log_error "无法加载 zram 模块，可能需要安装内核模块"
        return 1
    fi
}

# 安装必要的包
install_packages() {
    log_info "更新包列表并安装必要组件..."
    
    apt update
    
    # 安装 zram-tools (如果可用) 或者使用系统自带的 zram 支持
    if apt-cache show zram-tools >/dev/null 2>&1; then
        apt install -y zram-tools
        log_success "zram-tools 安装完成"
    else
        log_info "使用系统内置 zram 支持"
    fi
}

# 创建 zram 配置
create_zram_config() {
    log_info "创建 zram 配置..."
    
    # 计算 zram 大小 (内存的 50%)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ZRAM_SIZE_KB=$((TOTAL_RAM_KB / 2))
    ZRAM_SIZE_MB=$((ZRAM_SIZE_KB / 1024))
    
    log_info "配置 zram 大小: ${ZRAM_SIZE_MB}MB (总内存的 50%)"
    
    # 创建 systemd 服务文件
    cat > /etc/systemd/system/zram.service << EOF
[Unit]
Description=Enable zram compressed swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/zram-setup.sh start
ExecStop=/usr/local/bin/zram-setup.sh stop
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF

    # 创建 zram 设置脚本
    cat > /usr/local/bin/zram-setup.sh << EOF
#!/bin/bash

ZRAM_SIZE=${ZRAM_SIZE_KB}
ZRAM_DEV=/dev/zram0

case "\$1" in
    start)
        echo "启动 zram..."
        
        # 加载 zram 模块
        modprobe zram num_devices=1
        
        # 设置压缩算法 (lz4 速度快，zstd 压缩比高)
        if echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null; then
            echo "使用 zstd 压缩算法"
        elif echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null; then
            echo "使用 lz4 压缩算法"
        else
            echo "使用默认压缩算法"
        fi
        
        # 设置 zram 大小
        echo \${ZRAM_SIZE}K > /sys/block/zram0/disksize
        
        # 格式化为 swap
        mkswap \${ZRAM_DEV}
        
        # 启用 swap，设置较高优先级
        swapon \${ZRAM_DEV} -p 10
        
        echo "zram 启动完成"
        ;;
    stop)
        echo "停止 zram..."
        
        # 禁用 swap
        swapoff \${ZRAM_DEV} 2>/dev/null || true
        
        # 重置设备
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        
        # 卸载模块
        modprobe -r zram 2>/dev/null || true
        
        echo "zram 停止完成"
        ;;
    status)
        if [[ -b \${ZRAM_DEV} ]] && grep -q \${ZRAM_DEV} /proc/swaps; then
            echo "zram 正在运行"
            echo "压缩算法: \$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\\[.*\\]' | tr -d '[]')"
            echo "原始数据: \$(cat /sys/block/zram0/orig_data_size 2>/dev/null | numfmt --to=iec)"
            echo "压缩后大小: \$(cat /sys/block/zram0/compr_data_size 2>/dev/null | numfmt --to=iec)"
            echo "内存使用: \$(cat /sys/block/zram0/mem_used_total 2>/dev/null | numfmt --to=iec)"
            cat /proc/swaps | grep zram
        else
            echo "zram 未运行"
        fi
        ;;
    *)
        echo "用法: \$0 {start|stop|status}"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/zram-setup.sh
    log_success "zram 配置文件创建完成"
}

# 优化 swap 设置
optimize_swap_settings() {
    log_info "优化 swap 设置..."
    
    # 创建或更新 sysctl 配置
    cat > /etc/sysctl.d/99-zram.conf << EOF
# zram 优化设置

# 降低 swappiness，让系统更倾向于使用内存而不是 swap
vm.swappiness=10

# 提高缓存压力阈值，减少内存回收
vm.vfs_cache_pressure=50

# 设置脏页比例，提高 I/O 性能
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF

    # 应用设置
    sysctl -p /etc/sysctl.d/99-zram.conf
    log_success "系统参数优化完成"
}

# 启用服务
enable_zram_service() {
    log_info "启用 zram 服务..."
    
    systemctl daemon-reload
    systemctl enable zram.service
    systemctl start zram.service
    
    # 等待服务启动
    sleep 2
    
    # 检查状态
    if systemctl is-active --quiet zram.service; then
        log_success "zram 服务启动成功"
    else
        log_error "zram 服务启动失败"
        systemctl status zram.service
        return 1
    fi
}

# 显示状态信息
show_status() {
    log_info "zram 状态信息:"
    echo ""
    
    /usr/local/bin/zram-setup.sh status
    
    echo ""
    log_info "内存使用情况:"
    free -h
    
    echo ""
    log_info "swap 信息:"
    cat /proc/swaps
}

# 创建管理脚本
create_management_script() {
    log_info "创建管理脚本..."
    
    cat > /usr/local/bin/zram-manager << 'EOF'
#!/bin/bash

# zram 管理脚本

case "$1" in
    start)
        sudo systemctl start zram.service
        ;;
    stop)
        sudo systemctl stop zram.service
        ;;
    restart)
        sudo systemctl restart zram.service
        ;;
    status)
        /usr/local/bin/zram-setup.sh status
        ;;
    enable)
        sudo systemctl enable zram.service
        ;;
    disable)
        sudo systemctl disable zram.service
        ;;
    *)
        echo "zram 管理工具"
        echo ""
        echo "用法: $0 {start|stop|restart|status|enable|disable}"
        echo ""
        echo "命令说明:"
        echo "  start    - 启动 zram"
        echo "  stop     - 停止 zram"
        echo "  restart  - 重启 zram"
        echo "  status   - 查看 zram 状态"
        echo "  enable   - 开机自启 zram"
        echo "  disable  - 禁用开机自启"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/zram-manager
    log_success "管理脚本创建完成，可以使用 'zram-manager' 命令管理 zram"
}

# 主函数
main() {
    echo "=========================================="
    echo "    Debian 13 zram 一键启用脚本"
    echo "=========================================="
    echo ""
    
    check_root
    check_system
    
    echo ""
    read -p "是否继续安装和配置 zram？(y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    echo ""
    log_info "开始配置 zram..."
    
    # 执行安装步骤
    check_zram_exists || exit 1
    install_packages
    create_zram_config
    optimize_swap_settings
    enable_zram_service
    create_management_script
    
    echo ""
    echo "=========================================="
    log_success "zram 配置完成！"
    echo "=========================================="
    
    show_status
    
    echo ""
    echo "管理命令:"
    echo "  zram-manager status   - 查看状态"
    echo "  zram-manager restart  - 重启服务"
    echo "  zram-manager stop     - 停止服务"
    echo ""
    echo "配置文件位置:"
    echo "  /etc/systemd/system/zram.service"
    echo "  /usr/local/bin/zram-setup.sh"
    echo "  /etc/sysctl.d/99-zram.conf"
    
    log_success "安装完成！zram 将在系统启动时自动加载。"
}

# 捕获 Ctrl+C
trap 'echo ""; log_warning "安装被用户中断"; exit 1' INT

# 运行主函数
main "$@"
