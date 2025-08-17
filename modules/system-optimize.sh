#!/bin/bash
# 系统优化模块 - Debian 13适配版
# 功能: 智能Zram配置、时区设置、时间同步
# 优化: 减少错误、提高兼容性、增强稳定性

set -euo pipefail

# === 常量定义 ===
readonly ZRAM_CONFIG="/etc/default/zramswap"
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly SCRIPT_VERSION="6.0"
readonly DEBIAN_VERSION=$(lsb_release -rs 2>/dev/null || cat /etc/debian_version 2>/dev/null || echo "unknown")
readonly KERNEL_VERSION=$(uname -r)

# === 日志函数 ===
log() {
    local msg="$1" level="${2:-info}"
    local -A colors=([info]="\033[0;36m" [warn]="\033[0;33m" [error]="\033[0;31m" [debug]="\033[0;35m" [success]="\033[0;32m")
    echo -e "${colors[$level]:-\033[0;32m}[$(date '+%H:%M:%S')] $msg\033[0m"
}

debug_log() {
    [[ "${DEBUG:-}" == "1" ]] && log "DEBUG: $1" "debug" >&2
}

# === 系统兼容性检查 ===
check_system_compatibility() {
    local arch=$(uname -m)
    local kernel_major=$(uname -r | cut -d. -f1)
    local kernel_minor=$(uname -r | cut -d. -f2)
    
    debug_log "系统检查: Debian $DEBIAN_VERSION, 内核 $KERNEL_VERSION, 架构 $arch"
    
    # 检查架构支持
    case "$arch" in
        x86_64|amd64|aarch64|arm64) ;;
        armv7l|armv8l) log "ARM32架构可能存在兼容性问题" "warn" ;;
        *) log "不支持的架构: $arch" "error"; return 1 ;;
    esac
    
    # 检查内核版本（zram需要3.14+）
    if (( kernel_major < 3 || (kernel_major == 3 && kernel_minor < 14) )); then
        log "内核版本过低，zram可能不支持" "warn"
        return 1
    fi
    
    # 检查systemd
    if ! command -v systemctl &>/dev/null; then
        log "需要systemd支持" "error"
        return 1
    fi
    
    return 0
}

# === 包管理器增强函数 ===
wait_for_package_manager() {
    local max_wait=300  # 5分钟超时
    local wait_time=0
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    
    while (( wait_time < max_wait )); do
        local locked=false
        
        for lock_file in "${lock_files[@]}"; do
            if fuser "$lock_file" &>/dev/null; then
                locked=true
                break
            fi
        done
        
        if ! $locked; then
            # 额外检查apt进程
            if ! pgrep -f "apt|dpkg" &>/dev/null; then
                return 0
            fi
        fi
        
        if (( wait_time == 0 )); then
            log "等待包管理器释放..." "warn"
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    log "包管理器锁定超时，尝试强制继续" "warn"
    return 1
}

safe_apt_install() {
    local packages=("$@")
    local retry_count=0
    local max_retries=3
    
    wait_for_package_manager || log "包管理器可能仍被锁定" "warn"
    
    while (( retry_count < max_retries )); do
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" >/dev/null 2>&1; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log "安装失败，重试 $retry_count/$max_retries" "warn"
        sleep 2
    done
    
    log "安装包失败: ${packages[*]}" "error"
    return 1
}

# === 辅助函数优化 ===
convert_to_mb() {
    local size="$1"
    size=$(echo "$size" | tr -d ' ')
    local value=$(echo "$size" | sed 's/[^0-9.]//g')
    
    # 防止空值
    [[ -z "$value" ]] && { echo "0"; return; }
    
    case "${size^^}" in
        *G|*GB|*GIB) 
            if command -v bc &>/dev/null; then
                bc -l <<< "$value * 1024" 2>/dev/null || echo "0"
            else
                awk "BEGIN {printf \"%.0f\", $value * 1024}"
            fi ;;
        *M|*MB|*MIB) 
            if command -v bc &>/dev/null; then
                bc -l <<< "$value" 2>/dev/null || echo "0" 
            else
                awk "BEGIN {printf \"%.0f\", $value}"
            fi ;;
        *K|*KB|*KIB) 
            if command -v bc &>/dev/null; then
                bc -l <<< "$value / 1024" 2>/dev/null || echo "0"
            else
                awk "BEGIN {printf \"%.0f\", $value / 1024}"
            fi ;;
        *)      
            if command -v bc &>/dev/null; then
                bc -l <<< "$value / 1024 / 1024" 2>/dev/null || echo "0"
            else
                awk "BEGIN {printf \"%.0f\", $value / 1024 / 1024}"
            fi ;;
    esac
}

format_size() {
    local mb="$1"
    [[ "$mb" =~ ^[0-9]+$ ]] || { echo "0MB"; return; }
    
    if (( mb >= 1024 )); then
        if command -v bc &>/dev/null; then
            local gb=$(bc -l <<< "$mb / 1024" 2>/dev/null || echo "0")
            printf "%.1fGB" "$gb"
        else
            awk "BEGIN {printf \"%.1fGB\", $mb/1024}"
        fi
    else
        echo "${mb}MB"
    fi
}

# === 状态显示优化 ===
show_swap_status() {
    local swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "未知")
    echo "交换配置: swappiness=$swappiness"
    
    if ! command -v swapon &>/dev/null; then
        echo "交换状态: 命令不可用"
        return 1
    fi
    
    local swap_output
    if ! swap_output=$(swapon --show 2>/dev/null); then
        echo "交换状态: 无法获取状态"
        return 1
    fi
    
    local swap_lines=$(echo "$swap_output" | tail -n +2)
    if [[ -n "$swap_lines" ]]; then
        echo "交换状态:"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            local device=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $3}')
            local used=$(echo "$line" | awk '{print $4}')
            local prio=$(echo "$line" | awk '{print $5}')
            
            if [[ "$device" == *"zram"* ]]; then
                echo "  - Zram: $device ($size, 已用$used, 优先级$prio)"
            else
                echo "  - 磁盘: $device ($size, 已用$used, 优先级$prio)"
            fi
        done <<< "$swap_lines"
    else
        echo "交换状态: 无活动设备"
    fi
}

# === Zram清理增强 ===
cleanup_zram_completely() {
    debug_log "开始彻底清理zram"
    
    # 1. 停止系统服务
    if systemctl is-active zramswap.service &>/dev/null; then
        systemctl stop zramswap.service 2>/dev/null || true
    fi
    systemctl disable zramswap.service 2>/dev/null || true
    
    # 2. 关闭所有zram设备
    local zram_devices=()
    while IFS= read -r -d '' device; do
        zram_devices+=("$device")
    done < <(find /dev -name "zram*" -print0 2>/dev/null || true)
    
    for device in "${zram_devices[@]}"; do
        if [[ -b "$device" ]]; then
            swapoff "$device" 2>/dev/null || true
            local zram_name=$(basename "$device")
            local reset_path="/sys/block/$zram_name/reset"
            if [[ -w "$reset_path" ]]; then
                echo 1 > "$reset_path" 2>/dev/null || true
            fi
            debug_log "重置设备: $device"
        fi
    done
    
    # 3. 卸载模块
    local retry=0
    while (( retry < 5 )) && lsmod | grep -q "^zram "; do
        modprobe -r zram 2>/dev/null || true
        sleep 1
        retry=$((retry + 1))
    done
    
    # 4. 清理配置文件
    rm -f "${ZRAM_CONFIG}" "${ZRAM_CONFIG}.bak" 2>/dev/null || true
    
    # 5. 等待清理完成
    sleep 2
    debug_log "zram清理完成"
}

# === CPU性能检测优化 ===
benchmark_cpu_quick() {
    debug_log "开始CPU性能检测"
    local cores=$(nproc)
    
    # 检查可用的压缩工具
    local compress_cmd=""
    if command -v gzip &>/dev/null; then
        compress_cmd="gzip -1"
    elif command -v lz4 &>/dev/null; then
        compress_cmd="lz4 -1"
    elif command -v xz &>/dev/null; then
        compress_cmd="xz -1"
    else
        log "无可用压缩工具进行CPU测试" "warn"
        echo "moderate"
        return 0
    fi
    
    local start_time end_time duration
    start_time=$(date +%s.%N)
    
    # 使用超时和错误处理的压缩测试
    if timeout 15s bash -c "dd if=/dev/zero bs=1M count=64 2>/dev/null | $compress_cmd >/dev/null" 2>/dev/null; then
        end_time=$(date +%s.%N)
    else
        log "CPU测试超时或失败，使用保守配置" "warn"
        echo "weak"
        return 0
    fi
    
    # 计算性能分数
    if command -v bc &>/dev/null; then
        duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "10")
        local cpu_score=$(echo "scale=2; ($cores * 3) / $duration" | bc 2>/dev/null || echo "2")
        debug_log "CPU测试: ${cores}核心, ${duration}秒, 得分${cpu_score}"
        
        if (( $(echo "$cpu_score < 2" | bc -l 2>/dev/null || echo "1") )); then
            echo "weak"
        elif (( $(echo "$cpu_score < 6" | bc -l 2>/dev/null || echo "0") )); then
            echo "moderate"  
        else
            echo "strong"
        fi
    else
        # 简化的性能评估
        local int_duration=${end_time%.*}
        local int_start=${start_time%.*}
        duration=$((int_duration - int_start + 1))
        
        if (( duration > 8 )); then
            echo "weak"
        elif (( duration > 4 )); then
            echo "moderate"
        else
            echo "strong"
        fi
    fi
}

# === 内存分类优化 ===
get_memory_category() {
    local mem_mb="$1"
    
    # 验证输入
    if ! [[ "$mem_mb" =~ ^[0-9]+$ ]]; then
        log "无效内存值: $mem_mb" "error"
        echo "medium"
        return
    fi
    
    if (( mem_mb < 768 )); then
        echo "low"          # 极低配 (<768MB)
    elif (( mem_mb < 1536 )); then  
        echo "medium"       # 低配 (768MB-1.5GB)
    elif (( mem_mb < 3072 )); then
        echo "high"         # 中配 (1.5-3GB)  
    elif (( mem_mb < 6144 )); then
        echo "flagship"     # 高配 (3-6GB)
    else
        echo "server"       # 服务器级 (6GB+)
    fi
}

# === 智能配置决策优化 ===
get_optimal_zram_config() {
    local mem_mb="$1"
    local cpu_level="$2"
    local cores="$3"
    
    local mem_category=$(get_memory_category "$mem_mb")
    debug_log "配置决策: 内存${mem_category}, CPU${cpu_level}, ${cores}核"
    
    # 优化的配置策略
    case "$mem_category" in
        "low") 
            # 极低内存更激进使用zram
            case "$cpu_level" in
                "strong") echo "zstd,single,2.5" ;;
                "moderate") echo "zstd,single,2.0" ;;
                *) echo "lz4,single,1.8" ;;
            esac ;;
        "medium") 
            case "$cpu_level" in
                "strong") echo "zstd,single,2.0" ;;
                "moderate") echo "zstd,single,1.5" ;;
                *) echo "lz4,single,1.2" ;;
            esac ;;
        "high") 
            if (( cores >= 4 )); then
                case "$cpu_level" in
                    "strong") echo "zstd,multi,1.2" ;;
                    "moderate") echo "zstd,multi,1.0" ;;
                    *) echo "lz4,multi,0.8" ;;
                esac
            else
                echo "zstd,single,1.0"
            fi ;;
        "flagship") 
            if (( cores >= 6 )); then
                echo "zstd,multi,0.8"
            elif (( cores >= 4 )); then
                echo "zstd,multi,0.6"
            else
                echo "zstd,single,0.8"
            fi ;;
        "server")
            if (( cores >= 8 )); then
                echo "zstd,multi,0.4"
            else
                echo "zstd,multi,0.6"
            fi ;;
        *)
            log "未知配置: $mem_category，使用默认" "warn"
            echo "lz4,single,1.0"
            ;;
    esac
}

# === 系统参数设置增强 ===
set_system_parameters() {
    local mem_mb="$1"
    local device_count="${2:-1}"
    
    # 根据内存大小调整参数
    local zram_priority=100
    local disk_priority=10
    local swappiness vm_vfs_cache_pressure
    
    case "$(get_memory_category "$mem_mb")" in
        "low")      swappiness=80; vm_vfs_cache_pressure=120 ;;
        "medium")   swappiness=70; vm_vfs_cache_pressure=110 ;;
        "high")     swappiness=60; vm_vfs_cache_pressure=100 ;;
        "flagship") swappiness=50; vm_vfs_cache_pressure=90 ;;
        "server")   swappiness=40; vm_vfs_cache_pressure=80 ;;
        *)          swappiness=60; vm_vfs_cache_pressure=100 ;;
    esac
    
    debug_log "系统参数: swappiness=$swappiness, vfs_cache_pressure=$vm_vfs_cache_pressure"
    
    # 创建sysctl配置
    local sysctl_file="/etc/sysctl.d/99-zram-optimize.conf"
    cat > "$sysctl_file" << EOF
# Zram优化配置 v$SCRIPT_VERSION
# 适配 Debian $DEBIAN_VERSION 内核 $KERNEL_VERSION

# 交换策略优化
vm.swappiness = $swappiness

# 页面集群优化（对zram更有效）
vm.page-cluster = 0

# VFS缓存压力调整
vm.vfs_cache_pressure = $vm_vfs_cache_pressure

# 禁用zswap避免冲突
kernel.zswap.enabled = 0

# 内存回收优化
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# 针对SSD优化（如果适用）
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
EOF
    
    # 应用配置
    if sysctl -p "$sysctl_file" >/dev/null 2>&1; then
        debug_log "sysctl配置已应用"
    else
        log "sysctl应用失败，使用运行时设置" "warn"
        
        # 运行时设置关键参数
        echo "$swappiness" > /proc/sys/vm/swappiness 2>/dev/null || true
        echo "0" > /proc/sys/vm/page-cluster 2>/dev/null || true
        echo "$vm_vfs_cache_pressure" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true
    fi
    
    # 禁用zswap
    if [[ -f /sys/module/zswap/parameters/enabled ]]; then
        echo "0" > /sys/module/zswap/parameters/enabled 2>/dev/null || true
        debug_log "zswap已禁用"
    fi
    
    # 设置zram优先级
    for i in $(seq 0 $((device_count - 1))); do
        local device="/dev/zram$i"
        if [[ -b "$device" ]] && swapon --show 2>/dev/null | grep -q "^$device "; then
            if swapoff "$device" 2>/dev/null && swapon "$device" -p "$zram_priority" 2>/dev/null; then
                debug_log "zram$i 优先级设置为 $zram_priority"
            fi
        fi
    done
    
    # 调整磁盘swap优先级
    local disk_swap_count=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local device=$(echo "$line" | awk '{print $1}')
        [[ "$device" != *"zram"* ]] || continue
        
        if swapoff "$device" 2>/dev/null && swapon "$device" -p "$disk_priority" 2>/dev/null; then
            ((disk_swap_count++))
            debug_log "磁盘swap $device 优先级设置为 $disk_priority"
        fi
    done < <(swapon --show 2>/dev/null | tail -n +2)
    
    echo "$zram_priority,$swappiness,$disk_swap_count"
}

# === 单设备zram配置增强 ===
setup_single_zram() {
    local size_mib="$1"
    local algorithm="$2"
    
    debug_log "配置单zram: ${size_mib}MB, 算法: $algorithm"
    
    # 首先尝试手动配置方式
    if setup_manual_zram "$size_mib" "$algorithm"; then
        return 0
    fi
    
    # 回退到zram-tools方式
    log "手动配置失败，尝试zram-tools方式" "warn"
    
    # 检查zram-tools可用性
    if ! dpkg -l zram-tools &>/dev/null; then
        log "安装zram-tools..." "info"
        safe_apt_install zram-tools || {
            log "zram-tools安装失败" "error"
            return 1
        }
        systemctl daemon-reload
    fi
    
    # 验证关键文件存在
    local required_files=("/usr/sbin/zramswap" "/usr/lib/systemd/system/zramswap.service")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log "关键文件缺失: $file，重新安装zram-tools" "warn"
            apt-get purge -y zram-tools >/dev/null 2>&1 || true
            safe_apt_install zram-tools || return 1
            systemctl daemon-reload
            break
        fi
    done
    
    # 停止现有服务
    systemctl stop zramswap.service 2>/dev/null || true
    
    # 创建配置文件 - 修复SIZE格式问题
    cat > "$ZRAM_CONFIG" << EOF
# Zram配置 - 由优化脚本 v$SCRIPT_VERSION 生成
# 适配 Debian $DEBIAN_VERSION

# 压缩算法
ALGO=$algorithm

# 固定大小（使用正确的单位格式）
SIZE=${size_mib}M

# 优先级
PRIORITY=100

# 确保不使用百分比
PERCENT=""

# 设备数量
ZRAM_NUM=1
EOF
    
    debug_log "zram-tools配置文件内容:"
    [[ "${DEBUG:-}" == "1" ]] && cat "$ZRAM_CONFIG" >&2
    
    # 启动服务
    if ! systemctl enable zramswap.service >/dev/null 2>&1; then
        log "启用zramswap服务失败" "error"
        return 1
    fi
    
    # 等待服务完全停止
    local wait_count=0
    while systemctl is-active zramswap.service &>/dev/null && (( wait_count < 10 )); do
        sleep 1
        ((wait_count++))
    done
    
    if ! systemctl start zramswap.service >/dev/null 2>&1; then
        log "启动zramswap服务失败，查看状态:" "error"
        systemctl status zramswap.service --no-pager -l || true
        
        # 尝试手动启动脚本调试
        if [[ -x /usr/sbin/zramswap ]]; then
            debug_log "尝试手动执行zramswap脚本"
            /usr/sbin/zramswap start 2>&1 | head -10 || true
        fi
        return 1
    fi
    
    # 验证配置
    sleep 5  # 增加等待时间
    local retry=0
    while (( retry < 8 )); do
        if [[ -b /dev/zram0 ]]; then
            local actual_bytes=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "0")
            local actual_mb=$((actual_bytes / 1024 / 1024))
            
            # 检查是否已启用为swap
            if swapon --show 2>/dev/null | grep -q zram0; then
                local tolerance=20  # 增加容差到20%
                local min_expected=$((size_mib * (100 - tolerance) / 100))
                local max_expected=$((size_mib * (100 + tolerance) / 100))
                
                if (( actual_mb >= min_expected && actual_mb <= max_expected )); then
                    debug_log "zram配置成功: 期望${size_mib}MB, 实际${actual_mb}MB"
                    return 0
                else
                    debug_log "大小不匹配但在范围内: 期望${size_mib}MB, 实际${actual_mb}MB"
                    # 如果差距不是太大就接受
                    if (( actual_mb >= size_mib / 4 )); then
                        log "接受当前zram大小: ${actual_mb}MB" "warn"
                        return 0
                    fi
                fi
            else
                debug_log "zram设备存在但未启用为swap，重试..."
            fi
        else
            debug_log "zram设备未创建，重试 $retry/8"
        fi
        
        sleep 2
        ((retry++))
    done
    
    log "zram配置验证失败，尝试手动配置" "error"
    return 1
}

# === 手动zram配置函数 ===
setup_manual_zram() {
    local size_mib="$1"
    local algorithm="$2"
    
    debug_log "尝试手动配置zram: ${size_mib}MB, 算法: $algorithm"
    
    # 清理现有zram
    cleanup_zram_completely
    
    # 加载zram模块
    if ! modprobe zram num_devices=1 2>/dev/null; then
        debug_log "加载zram模块失败"
        return 1
    fi
    
    # 等待设备创建
    local wait_count=0
    while [[ ! -b /dev/zram0 ]] && (( wait_count < 10 )); do
        sleep 1
        ((wait_count++))
    done
    
    if [[ ! -b /dev/zram0 ]]; then
        debug_log "zram设备创建失败"
        return 1
    fi
    
    # 检查并设置压缩算法
    local comp_algo_file="/sys/block/zram0/comp_algorithm"
    if [[ -w "$comp_algo_file" ]]; then
        local available_algos=$(cat "$comp_algo_file" 2>/dev/null || echo "lz4")
        if [[ "$available_algos" == *"$algorithm"* ]]; then
            echo "$algorithm" > "$comp_algo_file" 2>/dev/null || {
                debug_log "设置压缩算法失败，使用默认"
            }
        else
            debug_log "算法 $algorithm 不支持，可用算法: $available_algos"
            # 尝试其他算法
            if [[ "$available_algos" == *"zstd"* ]]; then
                echo "zstd" > "$comp_algo_file" 2>/dev/null || true
            elif [[ "$available_algos" == *"lz4"* ]]; then
                echo "lz4" > "$comp_algo_file" 2>/dev/null || true
            fi
        fi
    fi
    
    # 设置大小
    local size_bytes=$((size_mib * 1024 * 1024))
    if ! echo "$size_bytes" > /sys/block/zram0/disksize 2>/dev/null; then
        debug_log "设置zram大小失败"
        return 1
    fi
    
    # 创建swap文件系统
    if ! mkswap /dev/zram0 >/dev/null 2>&1; then
        debug_log "创建zram swap失败"
        return 1
    fi
    
    # 启用swap
    if ! swapon /dev/zram0 -p 100 2>/dev/null; then
        debug_log "启用zram swap失败"
        return 1
    fi
    
    # 验证配置
    sleep 2
    if swapon --show 2>/dev/null | grep -q zram0; then
        local actual_bytes=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "0")
        local actual_mb=$((actual_bytes / 1024 / 1024))
        debug_log "手动zram配置成功: 期望${size_mib}MB, 实际${actual_mb}MB"
        
        # 创建简单的服务文件以便管理
        create_manual_zram_service "$size_mib" "$algorithm"
        
        return 0
    else
        debug_log "手动zram验证失败"
        return 1
    fi
}

# === 创建手动zram服务 ===
create_manual_zram_service() {
    local size_mib="$1"
    local algorithm="$2"
    
    local service_file="/etc/systemd/system/manual-zram.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=Manual Zram Setup
Before=swap.target
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram num_devices=1; sleep 1; echo $algorithm > /sys/block/zram0/comp_algorithm 2>/dev/null || true; echo $((size_mib * 1024 * 1024)) > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon /dev/zram0 -p 100'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true; modprobe -r zram 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable manual-zram.service >/dev/null 2>&1 || true
    
    debug_log "手动zram服务已创建"
}

# === 多设备zram配置增强 ===
setup_multiple_zram() {
    local total_size_mb="$1"
    local algorithm="$2"
    local cores="$3"
    local device_count=$((cores > 8 ? 8 : cores))  # 最多8个设备
    
    # 确保设备数量合理
    (( device_count >= 2 )) || device_count=2
    
    local per_device_mb=$((total_size_mb / device_count))
    
    debug_log "配置多zram: ${device_count}个设备, 每个${per_device_mb}MB, 总计${total_size_mb}MB"
    
    # 彻底清理
    cleanup_zram_completely
    
    # 加载zram模块
    if ! modprobe zram num_devices="$device_count" 2>/dev/null; then
        log "加载zram模块失败" "error"
        return 1
    fi
    
    sleep 2
    
    # 验证压缩算法支持
    local supported_algos
    if [[ -r /sys/block/zram0/comp_algorithm ]]; then
        supported_algos=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "lz4")
        if [[ "$supported_algos" != *"$algorithm"* ]]; then
            log "算法 $algorithm 不支持，可用: $supported_algos" "warn"
            # 选择最佳可用算法
            if [[ "$supported_algos" == *"zstd"* ]]; then
                algorithm="zstd"
            elif [[ "$supported_algos" == *"lz4"* ]]; then
                algorithm="lz4"  
            else
                algorithm=$(echo "$supported_algos" | awk '{print $1}' | tr -d '[]')
            fi
            debug_log "使用算法: $algorithm"
        fi
    fi
    
    # 配置每个设备
    local configured_count=0
    local total_configured_bytes=0
    
    for i in $(seq 0 $((device_count - 1))); do
        local device="/dev/zram$i"
        
        # 等待设备就绪
        local retry=0
        while [[ ! -b "$device" ]] && (( retry < 20 )); do
            sleep 0.5
            ((retry++))
        done
        
        if [[ ! -b "$device" ]]; then
            log "设备zram$i未就绪，跳过" "warn"
            continue
        fi
        
        # 设置压缩算法
        local comp_algo_file="/sys/block/zram$i/comp_algorithm"
        if [[ -w "$comp_algo_file" ]]; then
            if ! echo "$algorithm" > "$comp_algo_file" 2>/dev/null; then
                debug_log "设置zram$i压缩算法失败，使用默认"
            else
                debug_log "zram$i 算法设置为: $algorithm"
            fi
        fi
        
        # 设置大小（使用字节精确控制）
        local device_bytes=$((per_device_mb * 1024 * 1024))
        if ! echo "$device_bytes" > "/sys/block/zram$i/disksize" 2>/dev/null; then
            log "设置zram$i大小失败" "warn"
            continue
        fi
        
        # 验证设置的大小
        local actual_bytes=$(cat "/sys/block/zram$i/disksize" 2>/dev/null || echo "0")
        local actual_mb=$((actual_bytes / 1024 / 1024))
        debug_log "zram$i 设置: 期望${per_device_mb}MB, 实际${actual_mb}MB"
        
        # 创建swap
        if mkswap "$device" >/dev/null 2>&1; then
            # 启用swap
            if swapon "$device" -p 100 2>/dev/null; then
                ((configured_count++))
                total_configured_bytes=$((total_configured_bytes + actual_bytes))
                debug_log "zram$i 配置完成并已启用"
            else
                debug_log "启用zram$i失败"
            fi
        else
            log "创建zram$i swap失败" "warn"
        fi
    done
    
    if (( configured_count > 0 )); then
        local total_configured_mb=$((total_configured_bytes / 1024 / 1024))
        debug_log "多设备zram配置完成: ${configured_count}个设备, 总计${total_configured_mb}MB"
        
        # 创建管理服务
        create_multi_zram_service "$configured_count" "$per_device_mb" "$algorithm"
        
        echo "$configured_count"
        return 0
    else
        log "所有zram设备配置失败" "error"
        return 1
    fi
}

# === 创建多设备zram服务 ===
create_multi_zram_service() {
    local device_count="$1"
    local per_device_mb="$2" 
    local algorithm="$3"
    
    local service_file="/etc/systemd/system/multi-zram.service"
    local device_bytes=$((per_device_mb * 1024 * 1024))
    
    cat > "$service_file" << EOF
[Unit]
Description=Multi Zram Setup
Before=swap.target
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
    modprobe zram num_devices=$device_count
    sleep 2
    for i in \$(seq 0 \$((${device_count}-1))); do
        echo $algorithm > /sys/block/zram\$i/comp_algorithm 2>/dev/null || true
        echo $device_bytes > /sys/block/zram\$i/disksize
        mkswap /dev/zram\$i
        swapon /dev/zram\$i -p 100
    done
'
ExecStop=/bin/bash -c '
    for i in \$(seq 0 \$((${device_count}-1))); do
        swapoff /dev/zram\$i 2>/dev/null || true
        echo 1 > /sys/block/zram\$i/reset 2>/dev/null || true
    done
    modprobe -r zram 2>/dev/null || true
'

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable multi-zram.service >/dev/null 2>&1 || true
    
    debug_log "多设备zram服务已创建: $device_count 个设备"
}

# === 主要zram配置函数 ===
setup_zram() {
    if ! check_system_compatibility; then
        log "系统兼容性检查失败，跳过zram配置" "error"
        return 1
    fi
    
    local mem_mb
    if ! mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null); then
        log "无法获取内存信息" "error"
        return 1
    fi
    
    local cores=$(nproc)
    local mem_display=$(format_size "$mem_mb")
    
    echo "检测到: ${mem_display} 内存, ${cores}核 CPU"
    
    # CPU性能检测
    local cpu_level="moderate"
    if cpu_level=$(benchmark_cpu_quick); then
        echo "CPU性能等级: $cpu_level"
    else
        log "CPU检测失败，使用默认配置" "warn"
    fi
    
    # 获取最优配置
    local config=$(get_optimal_zram_config "$mem_mb" "$cpu_level" "$cores")
    IFS=',' read -r algorithm device_type multiplier <<< "$config"
    
    # 计算目标大小
    local target_size_mb
    if command -v bc &>/dev/null; then
        target_size_mb=$(bc -l <<< "$mem_mb * $multiplier" 2>/dev/null | cut -d. -f1)
    else
        # 整数运算版本
        local int_part=${multiplier%.*}
        local dec_part=${multiplier#*.}
        if [[ "$int_part" == "$dec_part" ]]; then
            dec_part=0
        fi
        target_size_mb=$(( (mem_mb * int_part) + (mem_mb * dec_part / 100) ))
    fi
    
    # 安全边界检查
    (( target_size_mb >= 64 )) || target_size_mb=64
    (( target_size_mb <= mem_mb * 3 )) || target_size_mb=$((mem_mb * 3))
    
    debug_log "目标配置: ${target_size_mb}MB ($algorithm, $device_type)"
    
    # 检查现有zram配置
    local current_zram_total=0
    local current_device_count=0
    
    if command -v swapon &>/dev/null; then
        while IFS= read -r line; do
            [[ "$line" == *"zram"* ]] || continue
            local size_str=$(echo "$line" | awk '{print $3}')
            local device_mb=$(convert_to_mb "$size_str")
            current_zram_total=$((current_zram_total + device_mb))
            ((current_device_count++))
        done < <(swapon --show 2>/dev/null | tail -n +2)
    fi
    
    # 配置匹配检查
    local expected_device_count=1
    [[ "$device_type" == "multi" ]] && expected_device_count=$((cores > 8 ? 8 : cores))
    [[ "$expected_device_count" -lt 2 ]] && expected_device_count=1
    
    local size_tolerance=15  # 15%容差
    local min_acceptable=$((target_size_mb * (100 - size_tolerance) / 100))
    local max_acceptable=$((target_size_mb * (100 + size_tolerance) / 100))
    
    debug_log "现有: ${current_zram_total}MB/${current_device_count}设备, 期望: ${target_size_mb}MB/${expected_device_count}设备"
    
    # 检查是否需要重新配置
    if (( current_device_count > 0 && 
          current_zram_total >= min_acceptable && 
          current_zram_total <= max_acceptable && 
          current_device_count == expected_device_count )); then
        
        log "现有zram配置合适，仅调整参数" "info"
        local params_result=$(set_system_parameters "$mem_mb" "$current_device_count")
        IFS=',' read -r priority swappiness disk_count <<< "$params_result"
        
        local display_size=$(format_size "$current_zram_total")
        local device_desc="$current_device_count设备"
        [[ "$current_device_count" -eq 1 ]] && device_desc="单设备"
        
        echo "Zram: $display_size ($algorithm, ${device_desc}, 优先级$priority) ✓"
        show_swap_status
        return 0
    fi
    
    # 需要重新配置
    if (( current_device_count > 0 )); then
        echo "重新配置zram..."
        cleanup_zram_completely
    fi
    
    # 配置新的zram
    local actual_device_count=1
    local config_success=false
    
    # 尝试多设备配置
    if [[ "$device_type" == "multi" ]]; then
        log "尝试配置多设备zram..." "info"
        if actual_device_count=$(setup_multiple_zram "$target_size_mb" "$algorithm" "$cores"); then
            config_success=true
            log "多设备zram配置成功: ${actual_device_count}个设备" "success"
        else
            log "多设备配置失败，回退到单设备" "warn"
            cleanup_zram_completely
            device_type="single"
        fi
    fi
    
    # 单设备配置
    if [[ "$device_type" == "single" ]] || [[ "$config_success" == "false" ]]; then
        log "配置单设备zram..." "info"
        if setup_single_zram "$target_size_mb" "$algorithm"; then
            config_success=true
            actual_device_count=1
            log "单设备zram配置成功" "success"
        else
            log "zram配置完全失败" "error"
            return 1
        fi
    fi
    
    # 设置系统参数并显示结果
    if [[ "$config_success" == "true" ]]; then
        local params_result=$(set_system_parameters "$mem_mb" "$actual_device_count")
        IFS=',' read -r priority swappiness disk_count <<< "$params_result"
        
        # 获取实际配置的大小
        local actual_total_mb=0
        while IFS= read -r line; do
            [[ "$line" == *"zram"* ]] || continue
            local size_str=$(echo "$line" | awk '{print $3}')
            local device_mb=$(convert_to_mb "$size_str")
            actual_total_mb=$((actual_total_mb + device_mb))
        done < <(swapon --show 2>/dev/null | tail -n +2)
        
        local display_size=$(format_size "$actual_total_mb")
        local device_desc="${actual_device_count}设备"
        [[ "$actual_device_count" -eq 1 ]] && device_desc="单设备"
        
        echo "Zram: $display_size ($algorithm, ${device_desc}, 优先级$priority) ✅"
        show_swap_status
        return 0
    fi
    
    return 1
}

# === 时区配置优化 ===
setup_timezone() {
    local current_tz
    if ! current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null); then
        current_tz=$(cat /etc/timezone 2>/dev/null || echo "未知")
    fi
    
    echo "当前时区: $current_tz"
    
    # 交互式选择（仅在终端环境下）
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        echo "时区选择:"
        echo "1. 上海 (Asia/Shanghai)"
        echo "2. UTC (协调世界时)"
        echo "3. 东京 (Asia/Tokyo)"
        echo "4. 伦敦 (Europe/London)"
        echo "5. 纽约 (America/New_York)"
        echo "6. 自定义输入"
        echo "7. 保持当前"
        
        read -p "请选择 [1-7] (默认1): " choice
    else
        # 非交互模式使用默认值
        choice="1"
        log "非交互模式，使用默认时区" "info"
    fi
    
    choice=${choice:-1}
    
    local target_tz
    case "$choice" in
        1) target_tz="Asia/Shanghai" ;;
        2) target_tz="UTC" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="Europe/London" ;;
        5) target_tz="America/New_York" ;;
        6) 
            if [[ -t 0 ]]; then
                read -p "输入时区 (如: Asia/Shanghai): " target_tz
                if ! timedatectl list-timezones 2>/dev/null | grep -q "^$target_tz$"; then
                    log "无效时区，使用默认" "warn"
                    target_tz="$DEFAULT_TIMEZONE"
                fi
            else
                target_tz="$DEFAULT_TIMEZONE"
            fi
            ;;
        7) 
            echo "时区: $current_tz (保持不变) ✓"
            return 0
            ;;
        *) 
            target_tz="$DEFAULT_TIMEZONE"
            ;;
    esac
    
    if [[ "$current_tz" != "$target_tz" ]]; then
        if timedatectl set-timezone "$target_tz" 2>/dev/null; then
            echo "时区: $target_tz ✅"
        else
            log "时区设置失败" "error"
            return 1
        fi
    else
        echo "时区: $target_tz (已是当前设置) ✓"
    fi
    
    return 0
}

# === 时间同步配置增强 ===
setup_chrony() {
    # 检查现有时间同步状态
    local sync_services=("chrony" "systemd-timesyncd" "ntp" "ntpd")
    local active_service=""
    
    for service in "${sync_services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            active_service="$service"
            break
        fi
    done
    
    # 如果chrony已经运行且同步正常
    if [[ "$active_service" == "chrony" ]]; then
        if command -v chronyc &>/dev/null; then
            local sync_status=$(chronyc tracking 2>/dev/null | awk '/System time.*synchronized/{print "yes";}')
            if [[ "$sync_status" == "yes" ]]; then
                local sources_count=$(chronyc sources 2>/dev/null | grep -c "^\^[*+]" || echo "0")
                echo "时间同步: Chrony (${sources_count}个同步源) ✓"
                return 0
            fi
        fi
    fi
    
    log "配置Chrony时间同步..." "info"
    
    # 停用冲突的时间同步服务
    for service in "systemd-timesyncd" "ntp" "ntpd"; do
        if systemctl is-active "$service" &>/dev/null; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            debug_log "停用服务: $service"
        fi
    done
    
    # 安装chrony
    if ! command -v chronyd &>/dev/null; then
        safe_apt_install chrony || {
            log "Chrony安装失败" "error"
            return 1
        }
    fi
    
    # 优化chrony配置
    local chrony_conf="/etc/chrony/chrony.conf"
    if [[ -f "$chrony_conf" ]]; then
        # 备份原配置
        cp "$chrony_conf" "${chrony_conf}.bak" 2>/dev/null || true
        
        # 添加优化配置
        if ! grep -q "makestep 1 3" "$chrony_conf" 2>/dev/null; then
            echo "" >> "$chrony_conf"
            echo "# 优化配置 - 由系统优化脚本添加" >> "$chrony_conf"
            echo "makestep 1 3" >> "$chrony_conf"
            echo "rtcsync" >> "$chrony_conf"
            debug_log "chrony配置已优化"
        fi
    fi
    
    # 启动服务
    if ! systemctl enable chrony >/dev/null 2>&1; then
        log "启用chrony失败" "error"
        return 1
    fi
    
    if ! systemctl start chrony >/dev/null 2>&1; then
        log "启动chrony失败" "error"
        systemctl status chrony --no-pager -l || true
        return 1
    fi
    
    # 等待同步
    sleep 3
    
    # 验证状态
    if systemctl is-active chrony &>/dev/null; then
        local sources_count=0
        local sync_count=0
        
        if command -v chronyc &>/dev/null; then
            sources_count=$(chronyc sources 2>/dev/null | grep -c "^\^" || echo "0")
            sync_count=$(chronyc sources 2>/dev/null | grep -c "^\^[*+]" || echo "0")
        fi
        
        if (( sources_count > 0 )); then
            echo "时间同步: Chrony (${sync_count}/${sources_count}个源同步) ✅"
        else
            echo "时间同步: Chrony (启动中...) ⏳"
        fi
        return 0
    else
        log "Chrony启动失败" "error"
        return 1
    fi
}

# === 主函数增强 ===
main() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log "需要root权限运行此脚本" "error"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 显示脚本信息
    log "🚀 Debian 13 系统优化脚本 v$SCRIPT_VERSION" "success"
    echo "适配系统: Debian $DEBIAN_VERSION"
    echo "内核版本: $KERNEL_VERSION"
    echo
    
    # 环境准备
    export DEBIAN_FRONTEND=noninteractive
    export SYSTEMD_PAGER=""
    export PAGER=""
    
    # 等待包管理器
    if ! wait_for_package_manager; then
        log "继续执行，但可能遇到包管理问题" "warn"
    fi
    
    # 检查和安装基础依赖
    local missing_packages=()
    local essential_packages=("bc" "lsb-release")
    
    for package in "${essential_packages[@]}"; do
        if ! dpkg -l "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if (( ${#missing_packages[@]} > 0 )); then
        log "安装必要依赖: ${missing_packages[*]}" "info"
        if ! safe_apt_install "${missing_packages[@]}"; then
            log "基础依赖安装失败，某些功能可能受限" "warn"
        fi
    fi
    
    # 系统兼容性检查
    if ! check_system_compatibility; then
        log "系统兼容性检查失败，某些功能可能不可用" "warn"
    fi
    
    echo "=== 开始系统优化 ==="
    echo
    
    # Zram配置
    log "🔧 配置智能Zram..." "info"
    if setup_zram; then
        log "Zram配置完成" "success"
    else
        log "Zram配置失败，但不影响其他优化" "warn"
    fi
    
    echo
    echo "---"
    
    # 时区配置
    log "🌍 配置系统时区..." "info"
    if setup_timezone; then
        log "时区配置完成" "success"
    else
        log "时区配置失败" "warn"
    fi
    
    echo
    echo "---"
    
    # 时间同步配置
    log "⏰ 配置时间同步..." "info"
    if setup_chrony; then
        log "时间同步配置完成" "success"
    else
        log "时间同步配置失败" "warn"
    fi
    
    echo
    echo "=== 优化完成 ==="
    
    # 显示最终状态摘要
    echo
    log "📊 系统状态摘要:" "info"
    echo "内存使用: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)", $3,$2,$3*100/$2}')"
    
    if command -v swapon &>/dev/null; then
        local swap_summary=$(swapon --show 2>/dev/null | tail -n +2 | wc -l)
        echo "交换设备: ${swap_summary}个"
    fi
    
    echo "交换积极性: $(cat /proc/sys/vm/swappiness 2>/dev/null || echo '未知')"
    echo "当前时区: $(timedatectl show --property=Timezone --value 2>/dev/null || echo '未知')"
    
    if systemctl is-active chrony &>/dev/null; then
        echo "时间同步: 活跃"
    else
        echo "时间同步: 未配置"
    fi
    
    # DEBUG信息
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo
        log "=== 详细调试信息 ===" "debug"
        echo "完整内存信息:"
        free -h
        echo
        echo "所有交换设备:"
        swapon --show 2>/dev/null || echo "无交换设备"
        echo
        echo "关键内核参数:"
        echo "  vm.swappiness = $(cat /proc/sys/vm/swappiness 2>/dev/null || echo 'N/A')"
        echo "  vm.page-cluster = $(cat /proc/sys/vm/page-cluster 2>/dev/null || echo 'N/A')"
        echo "  vm.vfs_cache_pressure = $(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo 'N/A')"
    fi
    
    echo
    log "✨ 系统优化脚本执行完成！" "success"
    echo "建议重启系统以确保所有配置生效: sudo reboot"
}

# === 错误处理和信号捕获 ===
cleanup_on_exit() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        log "脚本异常退出 (代码: $exit_code)" "error"
        echo "如需帮助，请使用 DEBUG=1 重新运行查看详细信息"
    fi
}

# 设置错误处理
trap cleanup_on_exit EXIT
trap 'log "接收到中断信号，正在清理..." "warn"; exit 130' INT TERM

# 检查是否直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
