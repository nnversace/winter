#!/bin/bash
# 全自动系统优化脚本
# 功能: 智能Zram配置、时区设置、时间同步

set -euo pipefail

# === 常量定义 ===
readonly CUSTOM_ZRAM_SCRIPT="/usr/local/sbin/custom-zram-setup.sh"
readonly SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/zramswap.service.d"
readonly SYSTEMD_OVERRIDE_FILE="${SYSTEMD_OVERRIDE_DIR}/override.conf"
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly -a APT_INSTALL_OPTS=(--no-install-recommends)
APT_UPDATED=0

# === 日志函数 ===
log() {
    local msg="$1" level="${2:-info}"
    local -A colors=([info]="\033[0;36m" [warn]="\033[0;33m" [error]="\033[0;31m" [debug]="\033[0;35m")
    echo -e "${colors[$level]:-\033[0;32m}$msg\033[0m"
}

debug_log() {
    [[ "${DEBUG:-}" == "1" ]] && log "DEBUG: $1" "debug" >&2
}

# === 辅助函数 ===
convert_to_mb() {
    local size="$1"
    size=$(echo "$size" | tr -d ' ')
    local value=$(echo "$size" | sed 's/[^0-9.]//g')
    
    case "${size^^}" in
        *G|*GB) awk "BEGIN {printf \"%.0f\", $value * 1024}" ;;
        *M|*MB) awk "BEGIN {printf \"%.0f\", $value}" ;;
        *K|*KB) awk "BEGIN {printf \"%.0f\", $value / 1024}" ;;
        *)      awk "BEGIN {printf \"%.0f\", $value / 1024 / 1024}" ;;
    esac
}

calculate_target_size() {
    local mem_mb="$1" multiplier="$2"
    awk -v mem="$mem_mb" -v mul="$multiplier" 'BEGIN {printf "%.0f", mem * mul}'
}

is_pkg_installed() {
    local pkg="$1"
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

apt_update_once() {
    ((APT_UPDATED)) && return 0

    log "APT: 同步软件包索引..." "info"
    if DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
        APT_UPDATED=1
    else
        log "APT: 更新软件包索引失败，请检查网络或软件源配置" "error"
        return 1
    fi
}

ensure_packages() {
    local packages=("$@") missing=()

    for pkg in "${packages[@]}"; do
        is_pkg_installed "$pkg" || missing+=("$pkg")
    done

    (( ${#missing[@]} == 0 )) && return 0

    apt_update_once || return 1

    log "APT: 安装依赖 -> ${missing[*]}" "info"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_INSTALL_OPTS[@]}" "${missing[@]}" >/dev/null 2>&1; then
        log "APT: 安装 ${missing[*]} 失败" "error"
        return 1
    fi
}

ensure_algorithm_supported() {
    local requested="$1" temp_loaded=0 algorithms_file="/sys/block/zram0/comp_algorithm"

    if [[ ! -r "$algorithms_file" ]]; then
        if ! lsmod | awk '{print $1}' | grep -qx "zram"; then
            if modprobe zram num_devices=1 2>/dev/null; then
                temp_loaded=1
            else
                log "无法加载zram模块以检测压缩算法支持，继续使用 $requested" "warn"
                echo "$requested"
                return 0
            fi
        fi
    fi

    if [[ -r "$algorithms_file" ]]; then
        local available
        available=$(<"$algorithms_file")
        if ! grep -qw "$requested" <<< "$available"; then
            local fallback
            fallback=$(awk '{for(i=1;i<=NF;i++){gsub(/\[|\]/,"",$i); if(length($i)){print $i; exit}}}' <<< "$available")
            fallback=${fallback:-lzo}
            log "压缩算法 $requested 不受支持，改用 $fallback" "warn"
            requested="$fallback"
        fi
    else
        log "无法读取压缩算法支持列表，继续使用 $requested" "warn"
    fi

    if (( temp_loaded )); then
        modprobe -r zram 2>/dev/null || true
    fi

    echo "$requested"
}

check_debian_version() {
    local os_release="/etc/os-release"

    if [[ -r "$os_release" ]]; then
        # shellcheck disable=SC1090
        . "$os_release"

        if [[ "${ID:-}" != "debian" ]]; then
            log "检测到系统 ${PRETTY_NAME:-unknown}，脚本仍将按Debian进行优化" "warn"
            return
        fi

        local major="${VERSION_ID%%.*}"
        if [[ "$major" =~ ^[0-9]+$ ]]; then
            if (( major < 12 )); then
                log "当前Debian版本(${VERSION_ID})较旧，部分优化可能无法生效" "warn"
            elif (( major > 13 )); then
                log "当前Debian版本(${VERSION_ID})较新，请留意兼容性" "warn"
            else
                log "检测到Debian ${VERSION_ID:-unknown}，应用针对性优化" "info"
            fi
        else
            log "无法解析Debian版本号(${VERSION_ID:-unknown})，默认继续" "warn"
        fi
    else
        log "无法读取系统版本信息，默认按Debian进行优化" "warn"
    fi
}

format_size() {
    local mb="$1"
    if (( mb >= 1024 )); then
        awk "BEGIN {gb=$mb/1024; printf (gb==int(gb)) ? \"%.0fGB\" : \"%.1fGB\", gb}"
    else
        echo "${mb}MB"
    fi
}

show_swap_status() {
    local swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "unknown")
    echo "Swap配置: swappiness=$swappiness"
    
    local swap_output
    if ! swap_output=$(swapon --show 2>/dev/null | tail -n +2); then
        echo "Swap状态: 无活动设备"
        return
    fi
    
    if [[ -n "$swap_output" ]]; then
        echo "Swap状态:"
        while read -r device _ size used priority; do
            [[ -z "$device" ]] && continue
            if [[ "$device" == *"zram"* ]]; then
                echo "  - Zram: $device ($size, 已用$used, 优先级$priority)"
            else
                echo "  - 磁盘: $device ($size, 已用$used, 优先级$priority)"
            fi
        done <<< "$swap_output"
    else
        echo "Swap状态: 无活动设备"
    fi
}

# 彻底清理zram配置 - 增强版
cleanup_zram_completely() {
    debug_log "开始彻底清理zram"
    
    systemctl stop zramswap.service 2>/dev/null || true
    systemctl disable zramswap.service 2>/dev/null || true
    
    # 移除systemd override
    if [[ -f "$SYSTEMD_OVERRIDE_FILE" ]]; then
        debug_log "移除 systemd override 文件"
        rm -f "$SYSTEMD_OVERRIDE_FILE"
        rmdir --ignore-fail-on-non-empty "$SYSTEMD_OVERRIDE_DIR" 2>/dev/null
        systemctl daemon-reload
    fi
    
    # 移除自定义脚本
    [[ -f "$CUSTOM_ZRAM_SCRIPT" ]] && rm -f "$CUSTOM_ZRAM_SCRIPT"
    
    for dev in /dev/zram*; do
        if [[ -b "$dev" ]]; then
            swapoff "$dev" 2>/dev/null || true
            echo 1 > "/sys/block/$(basename "$dev")/reset" 2>/dev/null || true
            debug_log "重置设备: $dev"
        fi
    done
    
    modprobe -r zram 2>/dev/null || true
    
    [[ -f "/etc/default/zramswap" ]] && rm -f "/etc/default/zramswap" "/etc/default/zramswap.bak" 2>/dev/null || true
    
    sleep 1
    debug_log "zram清理完成"
}

# === 核心功能函数 ===
# CPU性能快速检测
benchmark_cpu_quick() {
    debug_log "开始CPU性能检测"
    local cores=$(nproc)
    
    local start_time=$(date +%s.%N)
    if ! timeout 10s bash -c 'dd if=/dev/zero bs=1M count=32 2>/dev/null | gzip -1 > /dev/null' 2>/dev/null; then
        log "CPU检测超时，使用保守配置" "warn"
        echo "weak"
        return
    fi
    local end_time=$(date +%s.%N)
    
    local duration cpu_score
    if command -v bc >/dev/null 2>&1; then
        duration=$(echo "$end_time - $start_time" | bc)
        [[ $(echo "$duration <= 0" | bc -l) -eq 1 ]] && duration="0.1"
        cpu_score=$(echo "scale=2; ($cores * 2) / $duration" | bc)
    else
        local start_int=${start_time%.*}
        local end_int=${end_time%.*}
        duration=$((end_int - start_int))
        [[ $duration -le 0 ]] && duration=1
        cpu_score=$(( (cores * 200) / duration / 100 ))
    fi
    
    debug_log "CPU核心数: $cores, 测试时间: ${duration}s, 得分: $cpu_score"
    
    if (( $(echo "$cpu_score < 3" | bc -l 2>/dev/null || echo 1) )); then
        echo "weak"
    elif (( $(echo "$cpu_score < 8" | bc -l 2>/dev/null || echo 1) )); then
        echo "moderate"  
    else
        echo "strong"
    fi
}

get_memory_category() {
    local mem_mb="$1"
    if (( mem_mb < 1024 )); then echo "low";
    elif (( mem_mb < 2048 )); then echo "medium";
    elif (( mem_mb < 4096 )); then echo "high";
    else echo "flagship"; fi
}

get_optimal_zram_config() {
    local mem_mb="$1" cpu_level="$2" cores="$3"
    local mem_category=$(get_memory_category "$mem_mb")
    debug_log "内存分类: $mem_category, CPU等级: $cpu_level, 核心数: $cores"
    
    case "$mem_category" in
        "low")      echo "zstd,single,2.0" ;;
        "medium")   echo "zstd,single,1.5" ;;
        "high")     if (( cores >= 4 )); then echo "zstd,multi,1.0"; else echo "zstd,single,1.0"; fi ;;
        "flagship") if (( cores >= 4 )); then echo "zstd,multi,0.6"; else echo "zstd,single,0.8"; fi ;;
        *)          log "未知配置组合，使用默认" "warn"; echo "zstd,single,1.0" ;;
    esac
}

# 设置系统参数（增强版）
set_system_parameters() {
    local mem_mb="$1"
    local zram_priority=100 disk_priority=10 swappiness
    
    if (( mem_mb <= 1024 )); then swappiness=90;
    elif (( mem_mb <= 2048 )); then swappiness=80;
    elif (( mem_mb <= 4096 )); then swappiness=70;
    else swappiness=60; fi
    
    debug_log "目标配置: zram优先级=$zram_priority, swappiness=$swappiness"
    
    local sysctl_file="/etc/sysctl.d/99-zram-optimize.conf"
    cat > "$sysctl_file" << EOF
# Zram优化配置 - 由系统优化脚本自动生成
vm.swappiness = $swappiness
vm.page-cluster = 0
kernel.zswap.enabled = 0
EOF
    
    sysctl -p "$sysctl_file" >/dev/null 2>&1 || debug_log "sysctl应用失败，可能部分参数不支持"

    # 运行时设置（确保立即生效）
    echo "$swappiness" > /proc/sys/vm/swappiness 2>/dev/null || true
    echo "0" > /proc/sys/vm/page-cluster 2>/dev/null || true
    [[ -f /sys/module/zswap/parameters/enabled ]] && echo "0" > /sys/module/zswap/parameters/enabled 2>/dev/null || true

    # 设置磁盘swap优先级
    local disk_swap_count=0
    local disk_swap_output
    if disk_swap_output=$(swapon --show 2>/dev/null | grep -v zram | tail -n +2); then
        while read -r disk_swap _; do
            [[ -n "$disk_swap" ]] || continue
            if swapoff "$disk_swap" 2>/dev/null && swapon "$disk_swap" -p "$disk_priority" 2>/dev/null; then
                ((disk_swap_count++))
            fi
        done <<< "$disk_swap_output"
    fi
    
    echo "$zram_priority,$swappiness,$disk_swap_count"
}

# 创建持久化的Zram配置脚本和Systemd服务
create_persistent_zram_setup() {
    local size_mb="$1" algorithm="$2" device_count="$3" priority="$4"
    
    debug_log "创建持久化配置: ${size_mb}MB, $algorithm, ${device_count}个设备, 优先级$priority"
    
    # 1. 创建自定义配置脚本
    cat > "$CUSTOM_ZRAM_SCRIPT" << EOF
#!/bin/bash
# 这个脚本由系统优化工具自动生成，用于在启动时配置Zram

# 停止并重置所有现有zram设备
for dev in \$(ls /sys/class/block | grep zram); do
    if [[ -e "/sys/class/block/\$dev/reset" ]]; then
        swapoff "/dev/\$dev" 2>/dev/null
        echo 1 > "/sys/class/block/\$dev/reset"
    fi
done

# 加载zram模块
modprobe zram num_devices=${device_count}

# 配置每个设备
per_device_mb=\$(( ${size_mb} / ${device_count} ))
for i in \$(seq 0 \$(( ${device_count} - 1 )) ); do
    dev="/dev/zram\$i"
    
    # 等待设备就绪
    for _ in \$(seq 1 10); do
        [[ -b "\$dev" ]] && break
        sleep 0.1
    done
    
    if [[ ! -b "\$dev" ]]; then
        echo "Error: \$dev not found." >&2
        exit 1
    fi

    echo "${algorithm}" > "/sys/block/zram\$i/comp_algorithm"
    if [[ -f "/sys/block/zram\$i/max_comp_streams" ]]; then
        echo 0 > "/sys/block/zram\$i/max_comp_streams"
    fi
    echo "\${per_device_mb}M" > "/sys/block/zram\$i/disksize"
    mkswap "\$dev"
    swapon "\$dev" -p "${priority}"
done
EOF
    
    chmod +x "$CUSTOM_ZRAM_SCRIPT"
    
    # 2. 创建Systemd Override文件
    mkdir -p "$SYSTEMD_OVERRIDE_DIR"
    cat > "$SYSTEMD_OVERRIDE_FILE" << EOF
[Service]
# 清除旧的执行命令
ExecStart=
# 指定我们自己的配置脚本
ExecStart=${CUSTOM_ZRAM_SCRIPT}
EOF

    # 3. 重新加载systemd配置
    systemctl daemon-reload
    debug_log "Systemd override 创建成功"
}


# 主要的zram配置函数
setup_zram() {
    local mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local cores=$(nproc)
    local mem_display=$(format_size "$mem_mb")
    
    echo "检测到: ${mem_display}内存, ${cores}核CPU"
    
    # 检查是否有冲突的zram-generator
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        log "检测到 zram-generator 配置文件，可能导致冲突。建议移除或禁用。" "warn"
        sleep 3
    fi
    
    local cpu_level
    cpu_level=$(benchmark_cpu_quick)
    echo "CPU性能: $cpu_level"
    
    local config=$(get_optimal_zram_config "$mem_mb" "$cpu_level" "$cores")
    local algorithm=$(echo "$config" | cut -d, -f1)
    local device_type=$(echo "$config" | cut -d, -f2)
    local multiplier=$(echo "$config" | cut -d, -f3)
    
    local target_size_mb
    target_size_mb=$(calculate_target_size "$mem_mb" "$multiplier")

    local device_count=1
    if [[ "$device_type" == "multi" ]]; then
        device_count=$(( cores > 8 ? 8 : cores ))
        (( device_count > 0 )) || device_count=1
    fi
    
    echo "决策: 目标大小=$(format_size "$target_size_mb"), 算法=$algorithm, ${device_count}个设备"
    
    # 检查现有配置是否匹配
    local current_zram_mb=0
    local current_zram_devices=$(swapon --show 2>/dev/null | grep -c "zram" || true)
    
    if [[ "$current_zram_devices" -gt 0 ]]; then
        while read -r device _ size _; do
            [[ "$device" == *"zram"* ]] || continue
            current_zram_mb=$((current_zram_mb + $(convert_to_mb "$size")))
        done < <(swapon --show 2>/dev/null | grep zram)
        
        local min_acceptable=$((target_size_mb * 90 / 100))
        local max_acceptable=$((target_size_mb * 110 / 100))
        
        if (( current_zram_mb >= min_acceptable && 
              current_zram_mb <= max_acceptable && 
              current_zram_devices == device_count )); then
            echo "Zram: $(format_size "$current_zram_mb") (已按最优配置)"
            set_system_parameters "$mem_mb" >/dev/null
            show_swap_status
            return 0
        fi
    fi
    
    log "当前配置不匹配，开始重新配置..." "info"
    cleanup_zram_completely

    algorithm=$(ensure_algorithm_supported "$algorithm")

    # 安装zram-tools以获取基础服务文件
    if ! ensure_packages zram-tools; then
        log "zram-tools安装失败" "error"
        return 1
    fi
    
    # 设置内核参数并获取优先级
    local params_result=$(set_system_parameters "$mem_mb")
    local priority=$(echo "$params_result" | cut -d, -f1)
    
    # 创建持久化配置
    create_persistent_zram_setup "$target_size_mb" "$algorithm" "$device_count" "$priority"
    
    # 启用并启动服务
    systemctl enable zramswap.service >/dev/null 2>&1
    if ! systemctl restart zramswap.service; then
        log "启动zramswap服务失败。请检查 'journalctl -u zramswap.service'" "error"
        return 1
    fi
    
    sleep 2 # 等待服务生效
    
    # 最终验证
    local final_zram_mb=0
    if ! swapon --show 2>/dev/null | grep -q "zram"; then
        log "Zram配置失败，设备未激活" "error"
        return 1
    fi
    while read -r device _ size _; do
        [[ "$device" == *"zram"* ]] || continue
        final_zram_mb=$((final_zram_mb + $(convert_to_mb "$size")))
    done < <(swapon --show 2>/dev/null | grep zram)

    echo "Zram: $(format_size "$final_zram_mb") ($algorithm, ${device_count}个设备, 优先级$priority)"
    show_swap_status
}

# 自动配置时区为 Asia/Shanghai
setup_timezone() {
    local target_tz="$DEFAULT_TIMEZONE"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone)

    if [[ "$current_tz" == "$target_tz" ]]; then
        echo "时区: $current_tz (已是目标时区，无需更改)"
    else
        log "时区: 正在自动设置为 $target_tz..." "info"
        if timedatectl set-timezone "$target_tz" 2>/dev/null; then
            echo "时区: $target_tz (设置成功)"
        else
            log "设置时区失败" "error"
            return 1
        fi
    fi
}

# 配置Chrony
setup_chrony() {
    local chrony_service="chrony.service"
    if systemctl list-unit-files chrony.service >/dev/null 2>&1; then
        chrony_service="chrony.service"
    elif systemctl list-unit-files chronyd.service >/dev/null 2>&1; then
        chrony_service="chronyd.service"
    fi

    if command -v chronyc &>/dev/null && systemctl is-active "$chrony_service" &>/dev/null; then
        local synced_flag
        synced_flag=$(timedatectl show --property=SystemClockSynchronized --value 2>/dev/null || echo "no")
        if [[ "${synced_flag,,}" == "yes" ]] || chronyc tracking 2>/dev/null | grep -qi "Leap status.*Normal"; then
            echo "时间同步: Chrony (已同步)"; return 0;
        fi
    fi
    
    if [[ -f /lib/systemd/system/systemd-timesyncd.service ]]; then
        systemctl stop systemd-timesyncd 2>/dev/null || true
        systemctl disable systemd-timesyncd 2>/dev/null || true
    fi

    if ! ensure_packages chrony; then
        log "Chrony安装失败" "error"
        return 1
    fi

    systemctl enable "$chrony_service" >/dev/null 2>&1
    systemctl restart "$chrony_service" >/dev/null 2>&1

    sleep 2
    if systemctl is-active "$chrony_service" &>/dev/null; then
        local sources_count=$(chronyc sources 2>/dev/null | grep -c "^\^" || echo "0")
        echo "时间同步: Chrony (${sources_count}个时间源)"
    else
        log "Chrony启动失败" "error"; return 1;
    fi
}

# === 主流程 ===
main() {
    [[ $EUID -eq 0 ]] || { log "需要root权限运行" "error"; exit 1; }

    check_debian_version

    local wait_count=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        ((wait_count++))
        if (( wait_count > 6 )); then
            log "包管理器锁定超时，请检查是否有其他apt进程运行" "error"; exit 1;
        fi
        if (( wait_count == 1 )); then
            log "检测到包管理器被锁定，等待释放..." "warn"
        fi
        sleep 10
    done

    for cmd in awk swapon systemctl timedatectl modprobe lsmod apt-get; do
        command -v "$cmd" &>/dev/null || { log "缺少必要命令: $cmd" "error"; exit 1; }
    done

    if ! command -v bc &>/dev/null; then
        if ! ensure_packages bc; then
            log "bc安装失败，将使用备用计算方法" "warn"
        fi
    fi

    export SYSTEMD_PAGER="" PAGER="" DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
    
    log "🔧 开始全自动系统优化..." "info"
    
    echo
    setup_zram || log "Zram配置出现问题，请检查日志" "warn"
    
    echo
    setup_timezone || log "时区配置失败" "warn"
    
    echo  
    setup_chrony || log "时间同步配置失败" "warn"
    
    echo
    log "✅ 优化完成" "info"
}

# 错误处理
trap 'log "脚本在行号 $LINENO 处意外退出" "error"; exit 1' ERR

main "$@"
