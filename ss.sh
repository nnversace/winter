#!/bin/bash

# ========================================
#           代理服务管理器 v2.0
#    支持 sing-box 和 snell 服务管理
# ========================================

# 颜色和样式定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# 特殊符号 - 使用ASCII字符以提高兼容性
CHECKMARK="[✓]"
CROSSMARK="[✗]"
ARROW="=>"
STAR="*"
WARNING="[!]"
INFO="[i]"
GEAR="[+]"
ROCKET="[>>]"

# 配置变量
SING_BOX_DIR="/root/sing-box"
SNELL_DIR="/root/snell"
SCRIPT_NAME="代理服务管理器"
VERSION="v2.0"

# 动画效果函数
loading_animation() {
    local text="$1"
    local duration="${2:-3}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    while [ $i -lt $((duration * 10)) ]; do
        printf "\r${BLUE}${chars:$((i % 10)):1}${NC} $text"
        sleep 0.1
        ((i++))
    done
    printf "\r${GREEN}${CHECKMARK}${NC} $text\n"
}

# 进度条函数
progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    
    printf "\r${BLUE}["
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=filled; i<width; i++)); do printf "░"; done
    printf "] %d%% ${NC}" $percentage
}

# 日志函数增强
log_info() {
    echo -e "${BLUE}${INFO} ${BOLD}INFO${NC}    │ $1"
}

log_success() {
    echo -e "${GREEN}${CHECKMARK} ${BOLD}SUCCESS${NC} │ $1"
}

log_warning() {
    echo -e "${YELLOW}${WARNING} ${BOLD}WARNING${NC} │ $1"
}

log_error() {
    echo -e "${RED}${CROSSMARK} ${BOLD}ERROR${NC}   │ $1"
}

log_step() {
    echo -e "${PURPLE}${ARROW} ${BOLD}STEP${NC}    │ $1"
}

log_gear() {
    echo -e "${CYAN}${GEAR} ${BOLD}SYSTEM${NC}  │ $1"
}

# 分隔线函数
print_separator() {
    local char="${1:-─}"
    local length="${2:-60}"
    printf "${GRAY}"
    for ((i=0; i<length; i++)); do printf "$char"; done
    printf "${NC}\n"
}

# 标题显示函数
print_title() {
    local title="$1"
    local subtitle="$2"
    
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                     ${WHITE}${BOLD}${title}${NC}                     ${BLUE}║${NC}"
    if [ -n "$subtitle" ]; then
        echo -e "${BLUE}║${NC}                      ${GRAY}${subtitle}${NC}                      ${BLUE}║${NC}"
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 输入确认函数 - 修复乱码问题
confirm_action() {
    local prompt="$1"
    local default="${2:-N}"
    local response
    
    while true; do
        if [ "$default" = "Y" ]; then
            echo -n -e "${YELLOW}${WARNING} ${prompt} [Y/n]: ${NC}"
            read response
            response=${response:-Y}
        else
            echo -n -e "${YELLOW}${WARNING} ${prompt} [y/N]: ${NC}"
            read response
            response=${response:-N}
        fi
        
        case $response in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo -e "${RED}请输入 y 或 n${NC}" ;;
        esac
    done
}

# 等待按键函数
wait_for_key() {
    local message="${1:-按任意键继续...}"
    echo
    print_separator "─" 50
    echo -e "${GRAY}$message${NC}"
    read -n1 -s
}

# 检查系统状态
check_system() {
    log_gear "正在检查系统状态..."
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "需要 root 权限运行此脚本"
        echo -e "${YELLOW}请使用: ${WHITE}sudo $0${NC}"
        exit 1
    fi
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        echo -e "${YELLOW}请先安装 Docker: ${WHITE}curl -fsSL https://get.docker.com | bash${NC}"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行"
        echo -e "${YELLOW}启动服务: ${WHITE}systemctl start docker${NC}"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_warning "网络连接可能有问题"
    fi
    
    log_success "系统检查完成"
}

# 检查端口占用
check_port() {
    local port=$1
    local service_name="$2"
    
    if ss -tlnp | grep -q ":$port "; then
        log_warning "端口 ${WHITE}$port${NC} 已被占用 (${service_name})"
        if ! confirm_action "是否继续？这可能导致冲突"; then
            return 1
        fi
    else
        log_success "端口 ${WHITE}$port${NC} 可用"
    fi
    return 0
}

# 获取外网IP
get_external_ip() {
    local ip
    log_info "获取外网 IP 地址..."
    
    # 尝试多个服务获取IP
    ip=$(curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null) || \
    ip=$(curl -s --connect-timeout 5 ip.sb 2>/dev/null) || \
    ip="获取失败"
    
    echo "$ip"
}

# 创建 sing-box 配置
create_sing_box_config() {
    log_step "创建 sing-box 配置文件..."
    
    mkdir -p "$SING_BOX_DIR/config"
    
    cat > "$SING_BOX_DIR/docker-compose.yml" << 'EOF'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sb
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/etc/sing-box:ro
    command: -D /var/lib/sing-box -C /etc/sing-box/ run
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "52171"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

    cat > "$SING_BOX_DIR/config/config.json" << 'EOF'
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-1",
      "listen": "::",
      "listen_port": 52171,
      "method": "2022-blake3-chacha20-poly1305",
      "password": "K6zMgp5kAIQMO01xp8efhxRgjh4iAqVpbHXZUr1FC+c=",
      "multiplex": {
        "enabled": true,
        "padding": true,
        "brutal": {
          "enabled": true,
          "up_mbps": 1000,
          "down_mbps": 1000
        }
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-2",
      "listen": "::",
      "listen_port": 52071,
      "method": "2022-blake3-aes-128-gcm",
      "password": "IUmuU/NjIQhHPMdBz5WONA==",
      "multiplex": {
        "enabled": true,
        "padding": false
      }
    }
  ],
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/lib/sing-box/cache.db"
    }
  }
}
EOF
    
    log_success "sing-box 配置已创建"
}

# 创建 snell 配置
create_snell_config() {
    log_step "创建 snell 配置文件..."
    
    mkdir -p "$SNELL_DIR"
    
    cat > "$SNELL_DIR/docker-compose.yml" << 'EOF'
services:
  snell-server:
    image: vocrx/snell-server:latest
    container_name: snell-server
    restart: unless-stopped
    network_mode: host
    environment:
      PORT: 5310
      PSK: IUmuU/NjIQhHPMdBz5WONA==
      IPV6: false
      OBFS: tls
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "5310"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    
    log_success "snell 配置已创建"
}

# 部署服务
deploy_services() {
    print_title "[>>] 部署服务" "正在检查和部署代理服务"
    
    log_info "开始部署流程..."
    
    # 检查端口占用
    log_step "检查端口占用情况..."
    check_port 52171 "sing-box SS-1" || return 1
    check_port 52071 "sing-box SS-2" || return 1
    check_port 5310 "snell" || return 1
    
    # 创建配置文件
    echo
    log_step "创建配置文件..."
    create_sing_box_config
    create_snell_config
    
    # 部署 sing-box
    echo
    log_step "部署 sing-box 服务..."
    cd "$SING_BOX_DIR" || { log_error "无法进入 $SING_BOX_DIR 目录"; return 1; }
    
    loading_animation "下载 sing-box 镜像..." 2
    if docker compose pull &>/dev/null; then
        log_success "镜像下载完成"
    else
        log_error "镜像下载失败"
        return 1
    fi
    
    loading_animation "启动 sing-box 容器..." 3
    if docker compose up -d &>/dev/null; then
        log_success "sing-box 启动成功"
    else
        log_error "sing-box 启动失败"
        return 1
    fi
    
    # 部署 snell
    echo
    log_step "部署 snell 服务..."
    cd "$SNELL_DIR" || { log_error "无法进入 $SNELL_DIR 目录"; return 1; }
    
    loading_animation "下载 snell 镜像..." 2
    if docker compose pull &>/dev/null; then
        log_success "镜像下载完成"
    else
        log_error "镜像下载失败"
        return 1
    fi
    
    loading_animation "启动 snell 容器..." 3
    if docker compose up -d &>/dev/null; then
        log_success "snell 启动成功"
    else
        log_error "snell 启动失败"
        return 1
    fi
    
    echo
    print_separator "═" 60
    echo -e "${GREEN}${ROCKET} 部署完成！所有服务已成功启动${NC}"
    print_separator "═" 60
    
    show_service_info
    wait_for_key
}

# 服务控制函数
control_service() {
    local action="$1"
    local action_name="$2"
    local emoji="$3"
    
    print_title "$emoji $action_name服务" "正在${action_name}代理服务"
    
    log_step "${action_name} sing-box..."
    if [ -d "$SING_BOX_DIR" ]; then
        cd "$SING_BOX_DIR" && docker compose $action &>/dev/null
        if [ $? -eq 0 ]; then
            log_success "sing-box ${action_name}成功"
        else
            log_error "sing-box ${action_name}失败"
        fi
    else
        log_warning "sing-box 未安装"
    fi
    
    log_step "${action_name} snell..."
    if [ -d "$SNELL_DIR" ]; then
        cd "$SNELL_DIR" && docker compose $action &>/dev/null
        if [ $? -eq 0 ]; then
            log_success "snell ${action_name}成功"
        else
            log_error "snell ${action_name}失败"
        fi
    else
        log_warning "snell 未安装"
    fi
    
    echo
    if [ "$action" = "start" ] || [ "$action" = "restart" ]; then
        show_service_info
    fi
    wait_for_key
}

# 卸载服务
uninstall_services() {
    print_title "[DEL] 卸载服务" "完全删除所有代理服务和配置"
    
    echo -e "${RED}${WARNING} 警告：这将完全删除所有服务和配置文件！${NC}"
    echo
    if ! confirm_action "确认要完全卸载所有服务吗？"; then
        log_info "操作已取消"
        wait_for_key
        return 0
    fi
    
    echo
    log_step "开始卸载流程..."
    
    # 停止并删除容器
    if [ -d "$SING_BOX_DIR" ]; then
        log_step "停止 sing-box 服务..."
        cd "$SING_BOX_DIR" && docker compose down -v &>/dev/null
        log_success "sing-box 服务已停止并删除"
    fi
    
    if [ -d "$SNELL_DIR" ]; then
        log_step "停止 snell 服务..."
        cd "$SNELL_DIR" && docker compose down -v &>/dev/null
        log_success "snell 服务已停止并删除"
    fi
    
    # 删除配置文件
    log_step "删除配置文件..."
    [ -d "$SING_BOX_DIR" ] && rm -rf "$SING_BOX_DIR" && log_success "sing-box 配置文件已删除"
    [ -d "$SNELL_DIR" ] && rm -rf "$SNELL_DIR" && log_success "snell 配置文件已删除"
    
    # 询问是否删除镜像
    echo
    if confirm_action "是否删除相关 Docker 镜像？"; then
        log_step "删除 Docker 镜像..."
        docker rmi ghcr.io/sagernet/sing-box:latest vocrx/snell-server:latest &>/dev/null || true
        log_success "Docker 镜像已删除"
    fi
    
    echo
    print_separator "═" 60
    echo -e "${GREEN}${CHECKMARK} 卸载完成！所有服务和配置已清理${NC}"
    print_separator "═" 60
    wait_for_key
}

# 获取容器状态
get_container_status() {
    local container_name="$1"
    local status=$(docker inspect --format='{{.State.Status}}' $container_name 2>/dev/null)
    local health=$(docker inspect --format='{{.State.Health.Status}}' $container_name 2>/dev/null)
    
    if [ -z "$status" ]; then
        echo "未安装"
        return 1
    fi
    
    case $status in
        "running")
            if [ "$health" = "healthy" ]; then
                echo -e "${GREEN}运行中 (健康)${NC}"
            elif [ "$health" = "unhealthy" ]; then
                echo -e "${YELLOW}运行中 (不健康)${NC}"
            else
                echo -e "${GREEN}运行中${NC}"
            fi
            ;;
        "exited")
            echo -e "${RED}已停止${NC}"
            ;;
        "restarting")
            echo -e "${YELLOW}重启中${NC}"
            ;;
        *)
            echo -e "${GRAY}$status${NC}"
            ;;
    esac
    return 0
}

# 查看服务状态
show_status() {
    print_title "[INFO] 服务状态" "当前代理服务运行状态"
    
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}容器运行状态${NC}                     ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    
    # sing-box 状态
    printf "%-15s │ " "sing-box"
    get_container_status "sb"
    
    # snell 状态  
    printf "%-15s │ " "snell"
    get_container_status "snell-server"
    
    echo
    
    # 端口监听状态
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}端口监听状态${NC}                     ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    
    local ports=(52171 52071 5310)
    local names=("SS-1" "SS-2" "Snell")
    
    for i in "${!ports[@]}"; do
        local port=${ports[i]}
        local name=${names[i]}
        printf "%-15s │ " "$name ($port)"
        
        if ss -tlnp | grep -q ":$port "; then
            echo -e "${GREEN}监听中${NC}"
        else
            echo -e "${RED}未监听${NC}"
        fi
    done
    
    echo
    show_service_info
    wait_for_key
}

# 显示服务信息
show_service_info() {
    local external_ip=$(get_external_ip)
    
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}连接配置信息${NC}                     ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${CYAN}${STAR} 服务器地址：${WHITE}$external_ip${NC}"
    echo
    echo -e "${YELLOW}${BOLD}sing-box Shadowsocks 配置：${NC}"
    echo -e "  ${GRAY}├─${NC} SS-1 端口：${WHITE}52171${NC}"
    echo -e "  ${GRAY}├─${NC} SS-1 加密：${WHITE}2022-blake3-chacha20-poly1305${NC}"
    echo -e "  ${GRAY}├─${NC} SS-1 密码：${WHITE}K6zMgp5kAIQMO01xp8efhxRgjh4iAqVpbHXZUr1FC+c=${NC}"
    echo -e "  ${GRAY}├─${NC} SS-2 端口：${WHITE}52071${NC}"
    echo -e "  ${GRAY}├─${NC} SS-2 加密：${WHITE}2022-blake3-aes-128-gcm${NC}"
    echo -e "  ${GRAY}└─${NC} SS-2 密码：${WHITE}IUmuU/NjIQhHPMdBz5WONA==${NC}"
    echo
    echo -e "${YELLOW}${BOLD}snell 配置：${NC}"
    echo -e "  ${GRAY}├─${NC} 端口：${WHITE}5310${NC}"
    echo -e "  ${GRAY}├─${NC} 密码：${WHITE}IUmuU/NjIQhHPMdBz5WONA==${NC}"
    echo -e "  ${GRAY}└─${NC} 混淆：${WHITE}tls${NC}"
}

# 查看日志
show_logs() {
    print_title "[LOG] 查看日志" "实时日志监控和查看"
    
    echo -e "${BLUE}选择要查看的服务：${NC}"
    echo
    echo -e "  ${WHITE}1)${NC} sing-box 日志"
    echo -e "  ${WHITE}2)${NC} snell 日志"
    echo -e "  ${WHITE}3)${NC} 全部日志概览"
    echo -e "  ${WHITE}4)${NC} 实时跟踪 sing-box"
    echo -e "  ${WHITE}5)${NC} 实时跟踪 snell"
    echo -e "  ${WHITE}0)${NC} 返回主菜单"
    echo
    
    while true; do
        echo -n -e "${CYAN}请选择 [0-5]: ${NC}"
        read choice
        echo
        
        case $choice in
            1)
                if [ -d "$SING_BOX_DIR" ]; then
                    echo -e "${YELLOW}=== sing-box 最近日志 ===${NC}"
                    cd "$SING_BOX_DIR" && docker compose logs --tail=50 sing-box
                else
                    log_error "sing-box 未安装"
                fi
                wait_for_key
                break
                ;;
            2)
                if [ -d "$SNELL_DIR" ]; then
                    echo -e "${YELLOW}=== snell 最近日志 ===${NC}"
                    cd "$SNELL_DIR" && docker compose logs --tail=50 snell-server
                else
                    log_error "snell 未安装"
                fi
                wait_for_key
                break
                ;;
            3)
                echo -e "${YELLOW}=== sing-box 日志 ===${NC}"
                [ -d "$SING_BOX_DIR" ] && cd "$SING_BOX_DIR" && docker compose logs --tail=20 sing-box
                echo
                echo -e "${YELLOW}=== snell 日志 ===${NC}"
                [ -d "$SNELL_DIR" ] && cd "$SNELL_DIR" && docker compose logs --tail=20 snell-server
                wait_for_key
                break
                ;;
            4)
                if [ -d "$SING_BOX_DIR" ]; then
                    echo -e "${YELLOW}实时跟踪 sing-box 日志 (Ctrl+C 退出)${NC}"
                    echo
                    cd "$SING_BOX_DIR" && docker compose logs -f --tail=20 sing-box
                else
                    log_error "sing-box 未安装"
                    wait_for_key
                fi
                break
                ;;
            5)
                if [ -d "$SNELL_DIR" ]; then
                    echo -e "${YELLOW}实时跟踪 snell 日志 (Ctrl+C 退出)${NC}"
                    echo
                    cd "$SNELL_DIR" && docker compose logs -f --tail=20 snell-server
                else
                    log_error "snell 未安装"
                    wait_for_key
                fi
                break
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择，请输入 0-5${NC}"
                ;;
        esac
    done
}

# 系统信息
show_system_info() {
    print_title "[SYS] 系统信息" "服务器系统状态和资源使用"
    
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}系统基础信息${NC}                     ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    
    # 系统信息
    echo -e "${CYAN}操作系统：${NC}$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "${CYAN}内核版本：${NC}$(uname -r)"
    echo -e "${CYAN}系统架构：${NC}$(uname -m)"
    echo -e "${CYAN}运行时间：${NC}$(uptime -p)"
    
    echo
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}资源使用情况${NC}                     ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    
    # 资源使用
    local mem_info=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
    local disk_info=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')
    local load_avg=$(uptime | grep -oP 'load average: \K.*')
    
    echo -e "${CYAN}内存使用：${NC}$mem_info"
    echo -e "${CYAN}磁盘使用：${NC}$disk_info"
    echo -e "${CYAN}负载均衡：${NC}$load_avg"
    
    echo
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                     ${WHITE}${BOLD}Docker 信息${NC}                      ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    
    # Docker 信息
    local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
    local running_containers=$(docker ps -q | wc -l)
    local total_containers=$(docker ps -aq | wc -l)
    local total_images=$(docker images -q | wc -l)
    
    echo -e "${CYAN}Docker 版本：${NC}$docker_version"
    echo -e "${CYAN}运行容器：${NC}$running_containers"
    echo -e "${CYAN}总计容器：${NC}$total_containers"
    echo -e "${CYAN}镜像数量：${NC}$total_images"
    
    wait_for_key
}

# 显示主菜单
show_menu() {
    print_title "[>>] $SCRIPT_NAME" "$VERSION - 一键管理代理服务"
    
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                      ${WHITE}${BOLD}主要功能${NC}                       ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} [>>] 一键部署服务       ${GRAY}│${NC} 自动安装配置 sing-box 和 snell"
    echo -e "  ${BLUE}2)${NC} [>>] 查看服务状态       ${GRAY}│${NC} 检查服务运行状态和端口监听"
    echo -e "  ${GREEN}3)${NC} [>>] 启动所有服务       ${GRAY}│${NC} 启动已安装的代理服务"
    echo -e "  ${YELLOW}4)${NC} [>>] 停止所有服务       ${GRAY}│${NC} 停止运行中的代理服务"
    echo -e "  ${PURPLE}5)${NC} [>>] 重启所有服务       ${GRAY}│${NC} 重启所有代理服务"
    echo -e "  ${CYAN}6)${NC} [>>] 查看服务日志       ${GRAY}│${NC} 实时查看和监控日志"
    echo -e "  ${WHITE}7)${NC} [>>] 系统信息          ${GRAY}│${NC} 显示服务器系统状态信息"
    echo -e "  ${RED}8)${NC} [>>] 完全卸载服务       ${GRAY}│${NC} 删除所有服务和配置文件"
    echo
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                      ${WHITE}${BOLD}其他选项${NC}                       ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "  ${GRAY}0)${NC} [>>] 退出程序          ${GRAY}│${NC} 安全退出管理器"
    echo
    print_separator "─" 60
}

# 脚本开始提示
print_startup_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║     ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗              ║
    ║     ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝              ║
    ║     ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝               ║
    ║     ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝                ║
    ║     ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║                 ║
    ║     ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝                 ║
    ║                                                              ║
    ║                      服务管理器 v2.0                        ║
    ║                                                              ║
    ║          支持 sing-box 和 snell 一键部署管理                ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${GRAY}正在启动管理器...${NC}"
    loading_animation "初始化系统检查" 2
    echo
}

# 主函数
main() {
    # 检查系统状态
    check_system
    
    while true; do
        show_menu
        echo -n -e "${CYAN}请选择操作 [0-8]: ${NC}"
        read choice
        echo
        
        case $choice in
            1)
                deploy_services
                ;;
            2)
                show_status
                ;;
            3)
                control_service "start" "启动" "[>>]"
                ;;
            4)
                control_service "stop" "停止" "[--]"
                ;;
            5)
                control_service "restart" "重启" "[><]"
                ;;
            6)
                show_logs
                ;;
            7)
                show_system_info
                ;;
            8)
                uninstall_services
                ;;
            0)
                print_title "[BYE] 再见" "感谢使用代理服务管理器"
                echo -e "${GREEN}程序已安全退出，祝您使用愉快！${NC}"
                echo
                exit 0
                ;;
            "")
                # 空输入，重新显示菜单
                continue
                ;;
            *)
                log_error "无效选择，请输入 0-8 之间的数字"
                sleep 2
                ;;
        esac
    done
}

# 信号处理
trap 'echo -e "\n${YELLOW}程序被中断，正在安全退出...${NC}"; exit 130' INT TERM

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_startup_banner
    main "$@"
fi
