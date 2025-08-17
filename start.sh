#!/bin/bash

#=============================================================================
# Debian 13 系统一键配置脚本 v1.0.0
# 适用系统: Debian 13+
# 功能: 系统优化、Docker、工具安装、自动更新、MosDNS-x、内核优化
#=============================================================================

set -euo pipefail

#--- 全局常量 ---
readonly SCRIPT_VERSION="1.0.0"
readonly TEMP_DIR="/tmp/debian13-setup"
readonly LOG_FILE="/var/log/debian13-setup.log"
readonly SUMMARY_FILE="/root/debian13_summary.txt"

#--- 模块定义 ---
declare -A MODULES=(
    ["system-optimize"]="系统优化 (Zram, 时区, 时间同步)"
    ["docker-setup"]="Docker 容器化平台"
    ["tools-setup"]="系统工具 (NextTrace, SpeedTest等)"
    ["auto-update-setup"]="自动更新系统"
    ["mosdns-setup"]="MosDNS-x DNS服务器"
    ["kernel-optimize"]="内核参数优化"
)

#--- 执行状态 ---
EXECUTED_MODULES=()
FAILED_MODULES=()
SELECTED_MODULES=()
declare -A MODULE_EXEC_TIME=()
TOTAL_START_TIME=0

#--- 颜色系统 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

#--- 日志函数 ---
log() {
    local msg="$1"
    local level="${2:-info}"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "info")     echo -e "${GREEN}✅ $msg${NC}" ;;
        "warn")     echo -e "${YELLOW}⚠️  $msg${NC}" ;;
        "error")    echo -e "${RED}❌ $msg${NC}" ;;
        "success")  echo -e "${GREEN}🎉 $msg${NC}" ;;
    esac
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

#--- 分隔线 ---
print_line() {
    echo "============================================================"
}

#--- 错误处理 ---
cleanup() {
    local exit_code=$?
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    if (( exit_code != 0 )); then
        log "脚本异常退出，日志: $LOG_FILE" "error"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

#--- 基础检查 ---
check_system() {
    log "系统预检查"
    
    if (( EUID != 0 )); then
        log "需要 root 权限运行" "error"
        exit 1
    fi
    
    if [[ ! -f /etc/debian_version ]]; then
        log "仅支持 Debian 系统" "error"
        exit 1
    fi
    
    local debian_version=$(cat /etc/debian_version 2>/dev/null || echo "unknown")
    log "Debian 版本: $debian_version"
    
    local free_space_kb
    free_space_kb=$(df / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
    if (( free_space_kb < 2097152 )); then  # 2GB
        log "磁盘空间不足 (需要至少2GB)" "error"
        exit 1
    fi
    
    log "系统检查通过"
}

#--- 网络检查 ---
check_network() {
    log "检查网络连接..."
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log "网络连接异常，可能影响模块下载" "warn"
        read -p "继续执行? [y/N]: " -r choice
        [[ "$choice" =~ ^[Yy]$ ]] || exit 0
    fi
    log "网络连接正常"
}

#--- 安装基础依赖 ---
install_dependencies() {
    log "安装基础依赖"
    
    local required_packages=(
        "curl"
        "wget" 
        "git"
        "jq"
        "rsync"
        "sudo"
        "dnsutils"
        "unzip"
        "tar"
        "sed"
        "grep"
        "awk"
    )
    
    apt-get update -qq || log "软件包列表更新失败" "warn"
    
    local missing_packages=()
    for pkg in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            missing_packages+=("$pkg")
        fi
    done
    
    if (( ${#missing_packages[@]} > 0 )); then
        log "安装缺失依赖: ${missing_packages[*]}"
        apt-get install -y "${missing_packages[@]}" || {
            log "依赖安装失败" "error"
            exit 1
        }
    fi
    
    log "依赖检查完成"
}

#--- 系统优化模块 ---
module_system_optimize() {
    log "执行系统优化模块" "info"
    
    # Zram 配置
    log "配置 Zram..."
    
    # 检查是否已安装
    if lsmod | grep -q zram; then
        log "Zram 模块已加载，跳过配置"
    else
        # 加载 zram 模块
        modprobe zram num_devices=1 || {
            log "无法加载 zram 模块" "warn"
            return 0
        }
        
        # 计算 zram 大小 (内存的 50%)
        local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local zram_size_kb=$((total_ram_kb / 2))
        
        # 设置压缩算法和大小
        echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
        echo ${zram_size_kb}K > /sys/block/zram0/disksize
        
        # 创建 swap 并启用
        mkswap /dev/zram0
        swapon /dev/zram0 -p 10
        
        # 创建开机自启服务
        cat > /etc/systemd/system/zram.service << 'EOF'
[Unit]
Description=Enable zram compressed swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram num_devices=1; echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || echo lz4 > /sys/block/zram0/comp_algorithm; TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk "{print \$2}"); ZRAM_SIZE_KB=$((TOTAL_RAM_KB / 2)); echo ${ZRAM_SIZE_KB}K > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon /dev/zram0 -p 10'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl enable zram.service
        log "Zram 配置完成"
    fi
    
    # 时区设置
    log "设置时区为 Asia/Shanghai..."
    timedatectl set-timezone Asia/Shanghai || true
    
    # 时间同步
    log "配置时间同步..."
    systemctl enable systemd-timesyncd || true
    systemctl start systemd-timesyncd || true
    
    log "系统优化模块完成"
}

#--- Docker 安装模块 ---
module_docker_setup() {
    log "执行 Docker 安装模块" "info"
    
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "未知")
        log "Docker 已安装 v$docker_version"
        return 0
    fi
    
    log "安装 Docker..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || {
        log "Docker 安装失败" "error"
        return 1
    }
    
    # 启动并设置开机自启
    systemctl enable --now docker.service >/dev/null 2>&1 || true
    
    # 优化配置（低内存环境）
    local mem_mb=$(free -m | awk 'NR==2{print $2}' || echo "0")
    if (( mem_mb > 0 && mem_mb < 1024 )); then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
        systemctl restart docker >/dev/null 2>&1 || true
        log "Docker 低内存优化已应用"
    fi
    
    log "Docker 安装完成"
}

#--- 系统工具安装模块 ---
module_tools_setup() {
    log "执行系统工具安装模块" "info"
    
    # 安装常用工具
    local tools_packages=(
        "htop"
        "tree"
        "neofetch"
        "net-tools"
        "iperf3"
    )
    
    apt-get install -y "${tools_packages[@]}" || log "部分工具安装失败" "warn"
    
    # 安装 NextTrace
    if ! command -v nexttrace &>/dev/null; then
        log "安装 NextTrace..."
        local arch=$(uname -m)
        local download_arch=""
        
        case "$arch" in
            x86_64) download_arch="amd64" ;;
            aarch64) download_arch="arm64" ;;
            armv7l) download_arch="armv7" ;;
            *) download_arch="amd64" ;;
        esac
        
        local nexttrace_url="https://github.com/sjlleo/nexttrace/releases/latest/download/nexttrace_linux_${download_arch}"
        curl -fsSL "$nexttrace_url" -o /usr/local/bin/nexttrace && chmod +x /usr/local/bin/nexttrace || log "NextTrace 安装失败" "warn"
    fi
    
    # 安装 SpeedTest CLI
    if ! command -v speedtest &>/dev/null; then
        log "安装 SpeedTest CLI..."
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash >/dev/null 2>&1 || true
        apt-get install -y speedtest >/dev/null 2>&1 || log "SpeedTest 安装失败" "warn"
    fi
    
    log "系统工具安装完成"
}

#--- 自动更新模块 ---
module_auto_update_setup() {
    log "执行自动更新配置模块" "info"
    
    local update_script="/root/auto-update.sh"
    local update_log="/var/log/auto-update.log"
    
    # 创建自动更新脚本
    cat > "$update_script" << 'EOF'
#!/bin/bash
set -euo pipefail

readonly LOGFILE="/var/log/auto-update.log"
readonly APT_OPTIONS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o APT::ListChanges::Frontend=none"

log_update() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" | tee -a "$LOGFILE"
}

main() {
    : > "$LOGFILE"
    log_update "=== 开始自动系统更新 ==="
    
    log_update "更新软件包列表..."
    apt-get update >> "$LOGFILE" 2>&1
    
    log_update "升级系统软件包..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade $APT_OPTIONS >> "$LOGFILE" 2>&1
    
    log_update "清理系统缓存..."
    apt-get autoremove -y >> "$LOGFILE" 2>&1
    apt-get autoclean >> "$LOGFILE" 2>&1
    
    log_update "=== 自动更新完成 ==="
}

trap 'log_update "✗ 更新过程中发生错误"' ERR
main "$@"
EOF
    
    chmod +x "$update_script"
    
    # 添加 cron 任务
    if ! crontab -l 2>/dev/null | grep -q "$update_script"; then
        (crontab -l 2>/dev/null || true; echo "0 2 * * 0 $update_script") | crontab -
        log "自动更新任务已添加 (每周日凌晨2点)"
    fi
    
    log "自动更新配置完成"
}

#--- MosDNS-x 安装模块 ---
module_mosdns_setup() {
    log "执行 MosDNS-x 安装模块" "info"
    
    local repo="pmkol/mosdns-x"
    local bin="/usr/local/bin/mosdns"
    local workdir="/etc/mosdns"
    local conf="${workdir}/config.yaml"
    
    # 检测架构
    local arch=$(uname -m)
    local normalized_arch=""
    
    case "$arch" in
        x86_64|amd64) normalized_arch="linux-amd64" ;;
        aarch64|arm64) normalized_arch="linux-arm64" ;;
        armv7l|armv7) normalized_arch="linux-arm-7" ;;
        *) normalized_arch="linux-amd64" ;;
    esac
    
    if command -v mosdns &>/dev/null; then
        log "MosDNS-x 已安装，跳过"
        return 0
    fi
    
    mkdir -p "$workdir"
    
    # 获取最新版本下载链接
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local download_url=$(curl -fsSL "$api_url" | grep -oE "\"browser_download_url\": *\"[^\"]+mosdns-${normalized_arch}\.zip\"" | head -n1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
    
    if [[ -z "$download_url" ]]; then
        log "无法获取 MosDNS-x 下载链接" "error"
        return 1
    fi
    
    log "下载 MosDNS-x..."
    local tmpdir=$(mktemp -d)
    local zipfile="${tmpdir}/mosdns.zip"
    
    curl -fSL "$download_url" -o "$zipfile" || {
        log "MosDNS-x 下载失败" "error"
        rm -rf "$tmpdir"
        return 1
    }
    
    # 解压安装
    unzip -o "$zipfile" -d "$tmpdir" >/dev/null
    
    local mosdns_bin=""
    if [[ -f "${tmpdir}/mosdns" ]]; then
        mosdns_bin="${tmpdir}/mosdns"
    else
        mosdns_bin=$(find "$tmpdir" -maxdepth 2 -type f -name mosdns | head -n1)
    fi
    
    if [[ -z "$mosdns_bin" ]]; then
        log "解压包内未找到 mosdns" "error"
        rm -rf "$tmpdir"
        return 1
    fi
    
    install -m 0755 "$mosdns_bin" "$bin"
    rm -rf "$tmpdir"
    
    # 创建基础配置
    if [[ ! -f "$conf" ]]; then
        cat > "$conf" << 'EOF'
plugins:
  - tag: fwd
    type: fast_forward
    args:
      upstreams:
        - addr: 223.5.5.5
          enable_pipeline: true
        - addr: 119.29.29.29
          enable_pipeline: true
        - addr: 1.1.1.1
          enable_pipeline: true
servers:
  - exec: fwd
    listeners:
      - protocol: udp
        addr: 0.0.0.0:53
      - protocol: tcp
        addr: 0.0.0.0:53
EOF
    fi
    
    # 安装系统服务
    "$bin" service install -d "$workdir" -c "$conf" >/dev/null 2>&1 || true
    "$bin" service start >/dev/null 2>&1 || true
    
    log "MosDNS-x 安装完成"
}

#--- 内核优化模块 ---
module_kernel_optimize() {
    log "执行内核优化模块" "info"
    
    # 备份原配置
    [[ -f /etc/sysctl.conf.bak ]] || cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    # 清理旧配置
    local params_to_remove=(
        "fs.file-max"
        "fs.inotify.max_user_instances"
        "net.core.somaxconn"
        "net.core.netdev_max_backlog"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_mem"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_max_tw_buckets"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.ip_forward"
        "net.core.default_qdisc"
        "net.ipv4.tcp_congestion_control"
    )
    
    for param in "${params_to_remove[@]}"; do
        sed -i "/^${param}/d" /etc/sysctl.conf
    done
    
    # 添加优化参数
    cat >> /etc/sysctl.conf << 'EOF'

# === Debian 13 内核优化参数 ===
# 文件系统优化
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192

# 网络核心参数
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

# TCP 参数优化
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_keepalive_time = 600

# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# IP 转发
net.ipv4.ip_forward = 1
EOF
    
    # 启用 BBR
    modprobe tcp_bbr &>/dev/null || log "BBR 模块加载失败" "warn"
    
    # 应用参数
    sysctl -p >/dev/null 2>&1 || log "部分内核参数应用失败" "warn"
    
    log "内核优化完成"
}

#--- 模块选择 ---
select_modules() {
    log "选择安装模块"
    
    echo
    print_line
    echo "部署模式选择："
    echo "1) 🚀 全部安装 (推荐)"
    echo "2) 🎯 自定义选择"
    echo
    
    read -p "请选择模式 [1-2]: " -r mode_choice
    
    case "$mode_choice" in
        1)
            SELECTED_MODULES=(system-optimize docker-setup tools-setup auto-update-setup mosdns-setup kernel-optimize)
            log "选择: 全部安装"
            ;;
        2)
            custom_module_selection
            ;;
        *)
            log "无效选择，使用全部安装" "warn"
            SELECTED_MODULES=(system-optimize docker-setup tools-setup auto-update-setup mosdns-setup kernel-optimize)
            ;;
    esac
}

#--- 自定义模块选择 ---
custom_module_selection() {
    echo
    echo "可用模块："
    
    local module_list=(system-optimize docker-setup tools-setup auto-update-setup mosdns-setup kernel-optimize)
    
    for i in "${!module_list[@]}"; do
        local num=$((i + 1))
        local module="${module_list[$i]}"
        echo "$num) $module - ${MODULES[$module]}"
    done
    
    echo
    echo "请输入要安装的模块编号 (用空格分隔，如: 1 3 5):"
    read -r selection
    
    local selected=()
    for num in $selection; do
        if [[ "$num" =~ ^[1-6]$ ]]; then
            local index=$((num - 1))
            selected+=("${module_list[$index]}")
        else
            log "跳过无效编号: $num" "warn"
        fi
    done
    
    if (( ${#selected[@]} == 0 )); then
        log "未选择有效模块，使用system-optimize" "warn"
        selected=(system-optimize)
    fi
    
    SELECTED_MODULES=("${selected[@]}")
    log "已选择: ${SELECTED_MODULES[*]}"
}

#--- 执行模块 ---
execute_module() {
    local module="$1"
    
    log "执行模块: ${MODULES[$module]}"
    
    local start_time=$(date +%s)
    local exec_result=0
    
    case "$module" in
        "system-optimize")
            module_system_optimize || exec_result=$?
            ;;
        "docker-setup")
            module_docker_setup || exec_result=$?
            ;;
        "tools-setup")
            module_tools_setup || exec_result=$?
            ;;
        "auto-update-setup")
            module_auto_update_setup || exec_result=$?
            ;;
        "mosdns-setup")
            module_mosdns_setup || exec_result=$?
            ;;
        "kernel-optimize")
            module_kernel_optimize || exec_result=$?
            ;;
        *)
            log "未知模块: $module" "error"
            exec_result=1
            ;;
    esac
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    MODULE_EXEC_TIME[$module]=$duration
    
    if (( exec_result == 0 )); then
        EXECUTED_MODULES+=("$module")
        log "模块 $module 执行成功 (${duration}s)" "success"
        return 0
    else
        FAILED_MODULES+=("$module")
        log "模块 $module 执行失败 (${duration}s)" "error"
        return 1
    fi
}

#--- 获取系统状态 ---
get_system_status() {
    local status_lines=()
    
    # 基础信息
    local cpu_cores=$(nproc 2>/dev/null || echo "未知")
    local mem_info=$(free -h 2>/dev/null | grep Mem | awk '{print $3"/"$2}' || echo "未知")
    local disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "未知")
    local kernel=$(uname -r 2>/dev/null || echo "未知")
    
    status_lines+=("💻 CPU: ${cpu_cores}核心 | 内存: $mem_info | 磁盘: $disk_usage")
    status_lines+=("🔧 内核: $kernel")
    
    # Zram 状态
    if [[ -b /dev/zram0 ]] && grep -q /dev/zram0 /proc/swaps; then
        local zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null | numfmt --to=iec || echo "未知")
        status_lines+=("🗜️ Zram: 启用 (大小: $zram_size)")
    else
        status_lines+=("🗜️ Zram: 未启用")
    fi
    
    # Docker 状态
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "未知")
        local containers=$(docker ps -q 2>/dev/null | wc -l || echo "0")
        status_lines+=("🐳 Docker: v$docker_version (容器: $containers)")
    else
        status_lines+=("🐳 Docker: 未安装")
    fi
    
    # MosDNS 状态
    if command -v mosdns &>/dev/null; then
        local mosdns_version=$(mosdns version 2>/dev/null | head -1 || echo "未知")
        status_lines+=("🌐 MosDNS-x: $mosdns_version")
    else
        status_lines+=("🌐 MosDNS-x: 未安装")
    fi
    
    # 系统工具
    local tools_status=()
    command -v nexttrace &>/dev/null && tools_status+=("NextTrace")
    command -v speedtest &>/dev/null && tools_status+=("SpeedTest")
    command -v htop &>/dev/null && tools_status+=("htop")
    
    if (( ${#tools_status[@]} > 0 )); then
        status_lines+=("🛠️ 工具: ${tools_status[*]}")
    else
        status_lines+=("🛠️ 工具: 未安装")
    fi
    
    printf '%s\n' "${status_lines[@]}"
}

#--- 生成摘要 ---
generate_summary() {
    log "生成部署摘要"
    
    local total_modules=$(( ${#EXECUTED_MODULES[@]} + ${#FAILED_MODULES[@]} ))
    local success_rate=0
    if (( total_modules > 0 )); then
        success_rate=$(( ${#EXECUTED_MODULES[@]} * 100 / total_modules ))
    fi
    
    local total_time=$(( $(date +%s) - TOTAL_START_TIME ))
    
    echo
    print_line
    echo "Debian 13 系统配置完成摘要"
    print_line
    
    # 基本信息
    echo "📋 基本信息:"
    echo "   🔢 脚本版本: $SCRIPT_VERSION"
    echo "   📅 配置时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "   ⏱️ 总耗时: ${total_time}秒"
    echo "   🏠 主机名: $(hostname 2>/dev/null || echo '未知')"
    echo "   💻 系统: $(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo 'Debian 13')"
    
    # 执行统计
    echo
    echo "📊 执行统计:"
    echo "   📦 总模块: $total_modules | ✅ 成功: ${#EXECUTED_MODULES[@]} | ❌ 失败: ${#FAILED_MODULES[@]} | 📈 成功率: ${success_rate}%"
    
    # 成功模块
    if (( ${#EXECUTED_MODULES[@]} > 0 )); then
        echo
        echo "✅ 成功模块:"
        for module in "${EXECUTED_MODULES[@]}"; do
            local exec_time=${MODULE_EXEC_TIME[$module]}
            echo "   🟢 $module: ${MODULES[$module]} (${exec_time}s)"
        done
    fi
    
    # 失败模块
    if (( ${#FAILED_MODULES[@]} > 0 )); then
        echo
        echo "❌ 失败模块:"
        for module in "${FAILED_MODULES[@]}"; do
            local exec_time=${MODULE_EXEC_TIME[$module]:-0}
            echo "   🔴 $module: ${MODULES[$module]} (${exec_time}s)"
        done
    fi
    
    # 系统状态
    echo
    echo "🖥️ 当前系统状态:"
    while IFS= read -r status_line; do
        echo "   $status_line"
    done < <(get_system_status)
    
    # 保存摘要到文件
    {
        echo "==============================================="
        echo "Debian 13 系统配置摘要"
        echo "==============================================="
        echo "脚本版本: $SCRIPT_VERSION"
        echo "配置时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "总耗时: ${total_time}秒"
        echo "主机: $(hostname)"
        echo "系统: $(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo 'Debian 13')"
        echo ""
        echo "执行统计:"
        echo "总模块: $total_modules, 成功: ${#EXECUTED_MODULES[@]}, 失败: ${#FAILED_MODULES[@]}, 成功率: ${success_rate}%"
        echo ""
        echo "成功模块:"
        for module in "${EXECUTED_MODULES[@]}"; do
            echo "  $module (${MODULE_EXEC_TIME[$module]}s)"
        done
        [[ ${#FAILED_MODULES[@]} -gt 0 ]] && echo "" && echo "失败模块: ${FAILED_MODULES[*]}"
        echo ""
        echo "系统状态:"
        get_system_status
        echo ""
        echo "文件位置:"
        echo "  日志: $LOG_FILE"
        echo "  摘要: $SUMMARY_FILE"
    } > "$SUMMARY_FILE" 2>/dev/null || true
    
    echo
    echo "📁 详细摘要已保存至: $SUMMARY_FILE"
    print_line
}

#--- 最终建议 ---
show_recommendations() {
    echo
    log "配置完成！" "success"
    
    echo
    echo "🎯 重要提醒:"
    
    # Zram 提醒
    if [[ " ${EXECUTED_MODULES[*]} " =~ " system-optimize " ]]; then
        if [[ -b /dev/zram0 ]]; then
            echo "   🗜️ Zram 已启用，可有效提升系统性能"
        fi
    fi
    
    # Docker 提醒
    if [[ " ${EXECUTED_MODULES[*]} " =~ " docker-setup " ]]; then
        echo "   🐳 Docker 已安装，可使用容器部署应用"
    fi
    
    # MosDNS 提醒
    if [[ " ${EXECUTED_MODULES[*]} " =~ " mosdns-setup " ]]; then
        echo "   🌐 MosDNS-x 已配置，DNS 服务运行在 53 端口"
        echo "      管理命令: systemctl {start|stop|restart} mosdns"
    fi
    
    # 内核优化提醒
    if [[ " ${EXECUTED_MODULES[*]} " =~ " kernel-optimize " ]]; then
        echo "   ⚡ 内核已优化，BBR 拥塞控制已启用"
    fi
    
    echo
    echo "📚 常用命令:"
    echo "   查看日志: tail -f $LOG_FILE"
    echo "   查看摘要: cat $SUMMARY_FILE"
    echo "   系统状态: systemctl status"
    
    # 工具命令
    if command -v nexttrace &>/dev/null; then
        echo "   网络追踪: nexttrace baidu.com"
    fi
    
    if command -v speedtest &>/dev/null; then
        echo "   网速测试: speedtest"
    fi
    
    if [[ -b /dev/zram0 ]]; then
        echo "   Zram 状态: cat /proc/swaps | grep zram"
    fi
    
    echo
    echo "🔄 如需重新配置，请重新运行此脚本"
}

#--- 帮助信息 ---
show_help() {
    cat << EOF
Debian 13 系统一键配置脚本 v$SCRIPT_VERSION

用法: $0 [选项]

选项:
  --check-status    查看配置状态
  --help, -h        显示帮助信息
  --version, -v     显示版本信息

功能模块: 
  system-optimize   - 系统优化 (Zram, 时区, 时间同步)
  docker-setup      - Docker 容器化平台
  tools-setup       - 系统工具 (NextTrace, SpeedTest等)
  auto-update-setup - 自动更新系统
  mosdns-setup      - MosDNS-x DNS服务器
  kernel-optimize   - 内核参数优化

文件位置:
  日志: $LOG_FILE
  摘要: $SUMMARY_FILE
EOF
}

#--- 命令行参数处理 ---
handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-status)
                if [[ -f "$SUMMARY_FILE" ]]; then
                    cat "$SUMMARY_FILE"
                    echo
                    echo "实时系统状态:"
                    get_system_status
                else
                    echo "❌ 未找到配置摘要文件，请先运行配置脚本"
                fi
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "Debian 13 配置脚本 v$SCRIPT_VERSION"
                exit 0
                ;;
            *)
                echo "❌ 未知参数: $1"
                echo "使用 --help 查看帮助"
                exit 1
                ;;
        esac
        shift
    done
}

#--- 主程序 ---
main() {
    handle_arguments "$@"
    
    # 初始化
    mkdir -p "$(dirname "$LOG_FILE")" "$TEMP_DIR" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || true
    TOTAL_START_TIME=$(date +%s)
    
    # 启动界面
    clear 2>/dev/null || true
    print_line
    echo "         Debian 13 系统一键配置脚本 v$SCRIPT_VERSION"
    echo "         适配: 系统优化、Docker、工具、DNS、内核优化"
    print_line
    
    # 系统检查
    check_system
    check_network
    install_dependencies
    
    # 系统更新
    log "系统更新"
    apt-get update -qq >/dev/null 2>&1 || log "软件包列表更新失败" "warn"
    apt-get upgrade -y >/dev/null 2>&1 || log "系统升级失败" "warn"
    
    # 模块选择
    select_modules
    
    if (( ${#SELECTED_MODULES[@]} == 0 )); then
        log "未选择任何模块，退出" "warn"
        exit 0
    fi
    
    echo
    echo "最终执行计划: ${SELECTED_MODULES[*]}"
    read -p "确认执行配置? [Y/n]: " -r choice
    choice="${choice:-Y}"
    [[ "$choice" =~ ^[Yy]$ ]] || exit 0
    
    # 执行模块
    echo
    print_line
    log "开始执行 ${#SELECTED_MODULES[@]} 个配置模块"
    print_line
    
    for module in "${SELECTED_MODULES[@]}"; do
        echo
        echo "[$((${#EXECUTED_MODULES[@]} + ${#FAILED_MODULES[@]} + 1))/${#SELECTED_MODULES[@]}] 配置模块: ${MODULES[$module]}"
        
        execute_module "$module" || log "继续执行其他模块..." "warn"
    done
    
    # 生成摘要和建议
    generate_summary
    show_recommendations
    
    # 询问是否重启
    if [[ " ${EXECUTED_MODULES[*]} " =~ " kernel-optimize " ]] || [[ " ${EXECUTED_MODULES[*]} " =~ " system-optimize " ]]; then
        echo
        read -p "部分优化需要重启生效，是否立即重启? [y/N]: " -r reboot_choice
        if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
            log "系统将在 10 秒后重启..." "warn"
            sleep 10
            systemctl reboot
        else
            log "请记得稍后手动重启系统以使所有优化生效" "warn"
        fi
    fi
}

# 执行主程序
main "$@"
