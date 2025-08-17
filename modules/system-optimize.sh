#!/bin/bash
# 系统优化脚本- 为Debian 13优化
# 功能: 智能Zram配置, 时区与时间同步, 内核参数调优

# --- 安全设置 ---
# -e: 如果命令返回非零退出状态，则立即退出。
# -u: 将未设置的变量和参数视为错误。
# -o pipefail: 如果管道中的任何命令失败，则返回该命令的退出状态。
set -euo pipefail

# --- 全局常量 ---
readonly ZRAM_CONFIG_FILE="/etc/default/zramswap"
readonly SYSCTL_CONFIG_FILE="/etc/sysctl.d/99-zram-optimize.conf"
readonly SCRIPT_VERSION="6.0"
# 当DEBUG=1时启用详细日志
readonly DEBUG="${DEBUG:-0}"

# --- UI与日志函数 ---

# 统一的日志输出函数
log() {
    local type="$1"
    local msg="$2"
    local color_ok="\033[0;32m"
    local color_info="\033[0;36m"
    local color_warn="\033[0;33m"
    local color_error="\033[0;31m"
    local color_debug="\033[0;35m"
    local color_reset="\033[0m"
    local prefix=""

    case "$type" in
        ok) prefix="[✓] " color="$color_ok" ;;
        info) prefix="[i] " color="$color_info" ;;
        warn) prefix="[!] " color="$color_warn" ;;
        error) prefix="[✗] " color="$color_error" ;;
        debug) [[ "$DEBUG" -eq 1 ]] || return 0; prefix="[DEBUG] " color="$color_debug" ;;
        *) msg="$type"; prefix="    "; color="$color_reset" ;;
    esac

    # 使用printf以获得更好的格式控制
    printf "%b%s%b%s\n" "$color" "$prefix" "$color_reset" "$msg"
}

# 错误处理陷阱
trap 'log "error" "脚本在第 $LINENO 行意外终止。"; exit 1' ERR

# 脚本启动时的欢迎横幅
print_banner() {
    echo -e "\033[0;34m"
    echo "======================================================"
    echo "  智能系统优化脚本 v${SCRIPT_VERSION} - 为Debian 13优化"
    echo "======================================================"
    echo -e "\033[0m"
}

# --- 辅助函数 ---

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 显示加载动画
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf "    \r"
}

# 以非交互方式安装软件包
install_packages() {
    local packages_to_install=()
    for pkg in "$@"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            packages_to_install+=("$pkg")
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log "info" "准备安装缺失的依赖: ${packages_to_install[*]}"
        (
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y --no-install-recommends "${packages_to_install[@]}"
        ) &> /dev/null &
        spinner $!
        log "ok" "依赖安装完成。"
    fi
}

# 将不同单位的大小转换为MB
convert_to_mb() {
    local size_str
    size_str=$(echo "$1" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    local val="${size_str//[^0-9.]/}"
    case "$size_str" in
        *G|*GB) awk "BEGIN {printf \"%.0f\", $val * 1024}" ;;
        *M|*MB) awk "BEGIN {printf \"%.0f\", $val}" ;;
        *K|*KB) awk "BEGIN {printf \"%.0f\", $val / 1024}" ;;
        *) awk "BEGIN {printf \"%.0f\", $val / 1024 / 1024}" ;; # 默认为字节
    esac
}

# 将MB格式化为易于阅读的GB或MB
format_size() {
    local mb="$1"
    if (( mb >= 1024 )); then
        awk -v mb="$mb" 'BEGIN {printf "%.1fG", mb / 1024}'
    else
        echo "${mb}M"
    fi
}

# --- ZRAM核心功能 ---

# 彻底清理ZRAM配置
cleanup_zram() {
    log "debug" "开始彻底清理ZRAM..."
    systemctl stop zramswap.service &>/dev/null || true
    systemctl disable zramswap.service &>/dev/null || true
    
    # 查找并卸载所有活动的zram swap设备
    local active_zram_swaps
    active_zram_swaps=$(swapon --show --noheadings | awk '/^\/dev\/zram/ {print $1}')
    if [[ -n "$active_zram_swaps" ]]; then
        swapoff $active_zram_swaps &>/dev/null || true
    fi
    
    # 重置所有zram设备
    for dev in /sys/block/zram*; do
        if [[ -d "$dev" ]]; then
            echo 1 > "$dev/reset" 2>/dev/null || true
            log "debug" "已重置设备: $(basename "$dev")"
        fi
    done
    
    # 卸载zram内核模块
    modprobe -r zram &>/dev/null || true
    
    # 清理旧的配置文件
    rm -f "$ZRAM_CONFIG_FILE" "${ZRAM_CONFIG_FILE}.bak" &>/dev/null
    log "debug" "ZRAM清理完成。"
}

# 智能决策矩阵，决定ZRAM配置
get_optimal_zram_config() {
    local mem_mb="$1"
    local cores="$2"
    local mem_category

    if (( mem_mb < 1024 )); then mem_category="low"; fi       # <1GB
    if (( mem_mb >= 1024 && mem_mb < 2048 )); then mem_category="medium"; fi # 1-2GB
    if (( mem_mb >= 2048 && mem_mb < 4096 )); then mem_category="high"; fi   # 2-4GB
    if (( mem_mb >= 4096 )); then mem_category="flagship"; fi # 4GB+

    log "debug" "内存分类: $mem_category, 核心数: $cores"

    # 策略:
    # 算法: zstd是现代内核的默认选择，性能和压缩率俱佳。
    # 设备: 多核CPU可以从多zram设备中受益，减少锁争用。
    # 乘数: 内存越小，zram/swap的需求越大，因此乘数更高。
    case "$mem_category" in
        "low")      echo "zstd,single,2.0" ;;
        "medium")   echo "zstd,single,1.5" ;;
        "high")     [[ "$cores" -ge 4 ]] && echo "zstd,multi,1.0" || echo "zstd,single,1.0" ;;
        "flagship") [[ "$cores" -ge 4 ]] && echo "zstd,multi,0.75" || echo "zstd,single,0.8" ;;
        *)          echo "zstd,single,1.0" ;; # 默认安全配置
    esac
}

# 配置内核参数以优化ZRAM
set_kernel_parameters() {
    local mem_mb="$1"
    local swappiness
    
    # 根据内存大小调整交换倾向
    if (( mem_mb <= 2048 )); then swappiness=80; else swappiness=60; fi

    log "info" "配置内核参数: swappiness=$swappiness, page-cluster=0 (优化ZRAM)"

    # 创建sysctl配置文件
    # zswap.enabled=0: 避免与ZRAM双重压缩，确保ZRAM高效工作。
    # page-cluster=0: 减少写入ZRAM的数据块大小，提高压缩效率。
    cat > "$SYSCTL_CONFIG_FILE" << EOF
# 由系统优化脚本 v${SCRIPT_VERSION} 自动生成
vm.swappiness = $swappiness
vm.page-cluster = 0
zswap.enabled = 0
EOF

    # 应用配置
    sysctl -p "$SYSCTL_CONFIG_FILE" &>/dev/null || log "warn" "应用sysctl配置时出现非致命错误。"
}

# ZRAM配置主函数
setup_zram() {
    log "info" "正在配置智能ZRAM..."
    local mem_total_kb
    mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_mb=$((mem_total_kb / 1024))
    local cores
    cores=$(nproc)
    
    log "系统检测: $(format_size "$mem_mb") 内存, ${cores}核 CPU"

    # 1. 获取最优配置
    local config
    config=$(get_optimal_zram_config "$mem_mb" "$cores")
    local algorithm device_type multiplier
    IFS=',' read -r algorithm device_type multiplier <<< "$config"

    # 2. 计算目标ZRAM大小
    local target_size_mb
    target_size_mb=$(awk "BEGIN {printf \"%.0f\", $mem_mb * $multiplier}")
    log "决策: 使用 $algorithm 算法, $device_type 设备模式, ZRAM大小为 $(format_size "$target_size_mb")"

    # 3. 检查当前配置是否满足要求
    local current_zram_size_mb=0
    local current_zram_devices=0
    if command_exists swapon && swapon --show --noheadings | grep -q zram; then
        current_zram_size_mb=$(swapon --show --bytes --noheadings | awk '/zram/ {sum+=$3} END {print int(sum/1024/1024)}')
        current_zram_devices=$(swapon --show --noheadings | grep -c zram)
    fi
    
    local expected_devices=1
    if [[ "$device_type" == "multi" ]]; then
        expected_devices=$(( cores > 4 ? 4 : cores )) # 最多4个设备
    fi

    local min_size=$((target_size_mb * 90 / 100))
    local max_size=$((target_size_mb * 110 / 100))

    if (( current_zram_size_mb >= min_size && current_zram_size_mb <= max_size && current_zram_devices == expected_devices )); then
        log "ok" "当前ZRAM配置已是最佳，无需更改。"
        set_kernel_parameters "$mem_mb" # 仍然确保内核参数是最优的
        return 0
    fi

    log "info" "当前配置不匹配，正在重新配置..."

    # 4. 清理并应用新配置
    cleanup_zram
    
    # 安装zram-tools，这是在Debian上管理ZRAM最可靠的方式
    install_packages zram-tools

    # 写入zram-tools配置文件
    cat > "$ZRAM_CONFIG_FILE" << EOF
ALGO=$algorithm
SIZE=$target_size_mb
PRIORITY=100
EOF

    # 5. 启动服务并验证
    if ! systemctl restart zramswap.service; then
        log "error" "启动zramswap服务失败。请检查系统日志。"
        return 1
    fi
    systemctl enable zramswap.service &>/dev/null

    # 等待几秒钟让swap设备激活
    sleep 2

    if ! swapon --show | grep -q zram; then
        log "error" "ZRAM设备启动失败，配置未生效。"
        return 1
    fi
    
    set_kernel_parameters "$mem_mb"
    log "ok" "ZRAM配置成功。"
}

# --- 时区和时间同步 ---

# 配置时区
setup_timezone() {
    log "info" "正在配置时区..."
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "未知")
    
    # 使用更清晰的菜单
    echo "请选择您的时区:"
    echo "  1) Asia/Shanghai (默认)"
    echo "  2) UTC"
    echo "  3) Asia/Tokyo"
    echo "  4) Europe/London"
    echo "  5) America/New_York"
    echo "  6) 自定义输入"
    echo "  7) 保持当前 ($current_tz)"
    
    read -rp "输入选项 [1-7]: " choice < /dev/tty
    choice=${choice:-1}
    
    local target_tz=""
    case "$choice" in
        1) target_tz="Asia/Shanghai" ;;
        2) target_tz="UTC" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="Europe/London" ;;
        5) target_tz="America/New_York" ;;
        6) read -rp "请输入时区 (例如: Europe/Paris): " target_tz < /dev/tty ;;
        7) log "info" "时区保持不变。"; return 0 ;;
        *) log "warn" "无效选择，使用默认值 Asia/Shanghai。"; target_tz="Asia/Shanghai" ;;
    esac

    if [[ -z "$target_tz" ]]; then
        log "warn" "未输入时区，操作取消。"
        return
    fi

    if ! timedatectl set-timezone "$target_tz"; then
        log "error" "设置时区 '$target_tz' 失败。请检查时区名称是否正确。"
    else
        log "ok" "时区已设置为: $target_tz"
    fi
}

# 配置时间同步
setup_chrony() {
    log "info" "正在配置时间同步服务 (Chrony)..."
    
    # 停用可能冲突的systemd-timesyncd
    if systemctl is-active --quiet systemd-timesyncd; then
        systemctl stop systemd-timesyncd
        systemctl disable systemd-timesyncd
        log "debug" "已停用 systemd-timesyncd。"
    fi

    install_packages chrony

    if ! systemctl is-enabled --quiet chrony; then
        systemctl enable chrony &>/dev/null
    fi

    if ! systemctl restart chrony; then
        log "error" "启动Chrony服务失败。"
        return 1
    fi
    
    log "info" "等待Chrony与上游服务器同步..."
    sleep 5 # 等待chrony初始化

    if chronyc tracking | grep -q "System clock synchronized.*yes"; then
        local stratum
        stratum=$(chronyc tracking | awk '/Stratum/ {print $2}')
        log "ok" "时间同步成功 (Chrony, Stratum: $stratum)。"
    else
        log "warn" "Chrony正在运行，但尚未与时间服务器同步。这可能需要几分钟。"
    fi
}

# --- 主流程 ---
main() {
    # 权限检查
    [[ $EUID -eq 0 ]] || { log "error" "此脚本需要root权限运行。"; exit 1; }
    
    print_banner
    
    # 检查网络连接
    if ! ping -c 1 pool.ntp.org &>/dev/null; then
        log "warn" "无法访问外部网络。软件包安装和时间同步可能会失败。"
    fi
    
    # 检查并等待apt锁
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        log "warn" "检测到apt被锁定，等待10秒后重试..."
        sleep 10
    done

    # 确保核心工具存在
    install_packages bc util-linux procps
    
    # 执行优化
    setup_zram
    echo
    setup_timezone
    echo
    setup_chrony
    
    # 显示最终状态
    echo
    log "info" "--- 系统最终状态摘要 ---"
    log "ok" "Swap 状态:"
    swapon --show
    local final_swappiness
    final_swappiness=$(cat /proc/sys/vm/swappiness)
    log "ok" "内核参数: vm.swappiness = $final_swappiness"
    log "ok" "当前时间:"
    timedatectl status | head -n 3
    echo
    log "ok" "✅ 所有优化任务已完成。"
}

# 运行主函数
main "$@"
