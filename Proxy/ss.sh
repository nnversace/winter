#!/bin/bash

# =================================================================================
#                 🚀 代理服务管理器 v4.1 (精简版) 🚀
#        一键管理 sing-box (Shadowsocks/anytls) 和 snell 代理服务
# =================================================================================

# --- 样式定义 ---
# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
# 样式
BOLD='\033[1m'
NC='\033[0m'

# 符号
CHECKMARK="✓"
CROSSMARK="✗"
ARROW="→"
STAR="★"
WARNING="!"
INFO="i"
GEAR="⚙"
ROCKET="🚀"

# =================================================================================
#                           --- 全局配置 ---
#         所有服务配置集中于此，方便修改。修改后重新部署即可生效。
# =================================================================================

SCRIPT_NAME="代理服务管理器"
VERSION="v4.1"

# --- 基础路径配置 ---
# 所有服务文件的根目录
BASE_DIR="/root"

# --- sing-box 配置 ---
SINGBOX_DIR="${BASE_DIR}/sing-box"
SINGBOX_CONFIG_DIR="${SINGBOX_DIR}/config"
SINGBOX_CONTAINER_NAME="sb"
SINGBOX_IMAGE="ghcr.io/sagernet/sing-box:latest"

# Shadowsocks 配置
SINGBOX_SS1_PORT=52171
SINGBOX_SS1_METHOD="2022-blake3-chacha20-poly1305"
SINGBOX_SS1_PASSWORD="K6zMgp5kAIQMO01xp8efhxRgjh4iAqVpbHXZUr1FC+c=" # 建议使用 openssl rand -base64 32 生成

SINGBOX_SS2_PORT=52071
SINGBOX_SS2_METHOD="2022-blake3-aes-128-gcm"
SINGBOX_SS2_PASSWORD="IUmuU/NjIQhHPMdBz5WONA==" # 建议使用 openssl rand -base64 16 生成

# Anytls 配置
SINGBOX_ANYTLS_PORT=59271
SINGBOX_ANYTLS_USER="cqy"
SINGBOX_ANYTLS_PASSWORD="IUmuU/NjIQhHPMdBz5WONA==" # 可与SS密码相同或单独设置

# --- Snell 配置 ---
SNELL_DIR="${BASE_DIR}/snell"
SNELL_CONTAINER_NAME="snell-server"
SNELL_IMAGE="vocrx/snell-server:latest"

SNELL_PORT=5310
SNELL_PSK="IUmuU/NjIQhHPMdBz5WONA==" # 建议使用 openssl rand -base64 16 生成
SNELL_IPV6_ENABLED="false" # 是否启用IPv6监听

# --- 服务注册表 (关联数组) ---
# 格式: ["服务名"]="目录路径 容器名 镜像名 Compose文件路径"
declare -A SERVICES
SERVICES=(
    ["sing-box"]="${SINGBOX_DIR} ${SINGBOX_CONTAINER_NAME} ${SINGBOX_IMAGE} ${SINGBOX_DIR}/docker-compose.yml"
    ["snell"]="${SNELL_DIR} ${SNELL_CONTAINER_NAME} ${SNELL_IMAGE} ${SNELL_DIR}/docker-compose.yml"
)

# =================================================================================
#                           --- UI 和日志函数 ---
# =================================================================================

# 统一格式的日志输出
log_info()    { echo -e "${BLUE}${BOLD}${INFO} INFO${NC}    │ $1"; }
log_success() { echo -e "${GREEN}${BOLD}${CHECKMARK} SUCCESS${NC} │ $1"; }
log_warning() { echo -e "${YELLOW}${BOLD}${WARNING} WARNING${NC} │ $1"; }
log_error()   { echo -e "${RED}${BOLD}${CROSSMARK} ERROR${NC}   │ $1"; }
log_step()    { echo -e "${PURPLE}${BOLD}${ARROW} STEP${NC}    │ $1"; }
log_gear()    { echo -e "${CYAN}${BOLD}${GEAR} SYSTEM${NC}  │ $1"; }

# 动态加载动画
loading_animation() {
    local text="$1"
    local duration="${2:-2}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    tput civis # 隐藏光标
    while [ $i -lt $((duration * 10)) ]; do
        printf "\r${BLUE}${chars:$((i % ${#chars})):1}${NC} $text"
        sleep 0.1
        ((i++))
    done
    printf "\r%-80s\r" " " # 清除当前行
    log_success "$text"
    tput cnorm # 恢复光标
}

# 打印分隔线
print_separator() {
    printf "${GRAY}%s${NC}\n" "$(printf '─%.0s' $(seq 1 "$(tput cols)"))"
}

# 打印标题
print_title() {
    clear
    local title="$1"
    local subtitle="$2"
    print_separator
    echo -e "${CYAN}${BOLD}$(printf "%*s" $(( ($(tput cols) + ${#title}) / 2 )) "$title")${NC}"
    if [ -n "$subtitle" ]; then
        echo -e "${GRAY}$(printf "%*s" $(( ($(tput cols) + ${#subtitle}) / 2 )) "$subtitle")${NC}"
    fi
    print_separator
    echo
}

# 确认操作
confirm_action() {
    local prompt="$1"
    local default="${2:-N}"
    while true; do
        if [ "$default" = "Y" ]; then
            read -p "$(echo -e "${YELLOW}${WARNING} ${prompt} [Y/n]: ${NC}")" response
            response=${response:-Y}
        else
            read -p "$(echo -e "${YELLOW}${WARNING} ${prompt} [y/N]: ${NC}")" response
            response=${response:-N}
        fi
        case $response in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) log_error "请输入 y 或 n" ;;
        esac
    done
}

# 等待按键
wait_for_key() {
    echo
    read -n 1 -s -r -p "$(echo -e "${GRAY}按任意键返回主菜单...${NC}")"
}


# =================================================================================
#                           --- 核心功能函数 ---
# =================================================================================

# 检查系统环境
check_system() {
    log_gear "正在检查系统环境..."
    if [[ $EUID -ne 0 ]]; then
        log_error "需要 root 权限运行此脚本。请使用: sudo $0"
        exit 1
    fi

    local missing_deps=""
    command -v docker &>/dev/null || missing_deps+=" Docker"
    command -v openssl &>/dev/null || missing_deps+=" openssl"

    if [ -n "$missing_deps" ]; then
        log_error "缺少依赖: ${missing_deps}"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker 服务未运行。请启动服务: systemctl start docker"
        exit 1
    fi
    log_success "系统环境检查通过"
}

# 获取公网IP
get_external_ip() {
    IP=$(curl -s --max-time 5 https://api.ip.sb/ip) || \
    IP=$(curl -s --max-time 5 https://ipinfo.io/ip) || \
    IP=$(curl -s --max-time 5 https://ifconfig.me)
    echo "${IP:-"获取失败"}"
}

# 生成自签名证书 (用于 Anytls)
generate_self_signed_cert() {
    local cert_dir="$1"
    local cert_path="${cert_dir}/cert.crt"
    local key_path="${cert_dir}/private.key"

    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "TLS 证书已存在，跳过生成。"
        return 0
    fi

    log_step "正在生成自签名 TLS 证书..."
    if openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$key_path" -out "$cert_path" -subj "/CN=localhost" -days 3650 &>/dev/null; then
        log_success "TLS 证书生成成功"
    else
        log_error "TLS 证书生成失败，请检查 openssl 是否正常工作。"
        return 1
    fi
}

# 创建 sing-box 配置文件
create_sing_box_config() {
    log_step "创建 sing-box 配置文件..."
    mkdir -p "$SINGBOX_CONFIG_DIR"
    
    generate_self_signed_cert "$SINGBOX_CONFIG_DIR" || return 1

    cat > "${SINGBOX_DIR}/docker-compose.yml" <<-EOF
services:
  sing-box:
    image: ${SINGBOX_IMAGE}
    container_name: ${SINGBOX_CONTAINER_NAME}
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/etc/sing-box:ro
    command: -D /var/lib/sing-box -C /etc/sing-box/ run
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${SINGBOX_SS1_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

    cat > "${SINGBOX_CONFIG_DIR}/config.json" <<-EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-1",
      "listen": "::",
      "listen_port": ${SINGBOX_SS1_PORT},
      "method": "${SINGBOX_SS1_METHOD}",
      "password": "${SINGBOX_SS1_PASSWORD}",
      "multiplex": { "enabled": true, "padding": true }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-2",
      "listen": "::",
      "listen_port": ${SINGBOX_SS2_PORT},
      "method": "${SINGBOX_SS2_METHOD}",
      "password": "${SINGBOX_SS2_PASSWORD}",
      "multiplex": { "enabled": true, "padding": false }
    },
    {
      "type": "anytls",
      "tag": "anytls-1",
      "listen": "::",
      "listen_port": ${SINGBOX_ANYTLS_PORT},
      "users": [ { "name": "${SINGBOX_ANYTLS_USER}", "password": "${SINGBOX_ANYTLS_PASSWORD}" } ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/cert.crt",
        "key_path": "/etc/sing-box/private.key"
      }
    }
  ],
  "experimental": {
    "cache_file": { "enabled": true, "path": "/var/lib/sing-box/cache.db" }
  }
}
EOF
    log_success "sing-box 配置创建完成"
}

# 创建 snell 配置文件
create_snell_config() {
    log_step "创建 snell 配置文件..."
    mkdir -p "$SNELL_DIR"

    cat > "${SNELL_DIR}/docker-compose.yml" <<-EOF
services:
  snell-server:
    image: ${SNELL_IMAGE}
    container_name: ${SNELL_CONTAINER_NAME}
    restart: unless-stopped
    network_mode: host
    environment:
      PORT: ${SNELL_PORT}
      PSK: ${SNELL_PSK}
      IPV6: ${SNELL_IPV6_ENABLED}
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${SNELL_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    log_success "snell 配置创建完成"
}

# 部署单个服务
deploy_single_service() {
    local service_name="$1"
    local service_info=(${SERVICES[$service_name]})
    local compose_file=${service_info[3]}

    log_step "开始部署 ${service_name} 服务..."
    
    loading_animation "下载 ${service_name} 镜像..." 3
    if ! docker compose -f "$compose_file" pull &>/dev/null; then
        log_error "${service_name} 镜像下载失败"
        return 1
    fi

    loading_animation "启动 ${service_name} 容器..." 3
    if ! docker compose -f "$compose_file" up -d &>/dev/null; then
        log_error "${service_name} 容器启动失败"
        return 1
    fi

    log_success "${service_name} 部署成功"
}

# 部署所有服务
deploy_services() {
    print_title "🚀 一键部署服务" "将自动配置并启动所有代理服务"
    
    if ! confirm_action "这将创建配置文件并启动 Docker 容器。是否继续？" "Y"; then
        log_info "部署已取消。"; return
    fi
    echo

    log_step "检查端口占用情况..."
    local ports_ok=true
    check_port() {
        if ss -tlnp | grep -q ":$1 "; then
            log_warning "端口 ${WHITE}$1${NC} ($2) 已被占用"
            ports_ok=false
        fi
    }
    check_port ${SINGBOX_SS1_PORT} "sing-box SS-1"
    check_port ${SINGBOX_SS2_PORT} "sing-box SS-2"
    check_port ${SINGBOX_ANYTLS_PORT} "sing-box anytls"
    check_port ${SNELL_PORT} "snell"
    
    if ! $ports_ok; then
        if ! confirm_action "存在端口冲突，是否忽略并继续？"; then
            log_info "部署已取消。"; wait_for_key; return
        fi
    else
        log_success "所有目标端口均可用"
    fi
    echo

    log_step "生成服务配置文件..."
    create_sing_box_config || { wait_for_key; return; }
    create_snell_config || { wait_for_key; return; }
    echo

    for service in "${!SERVICES[@]}"; do
        deploy_single_service "$service" || { wait_for_key; return; }
        echo
    done

    print_separator
    log_success "🎉 部署完成！所有服务已成功启动 🎉"
    print_separator
    echo
    
    show_status_and_info "no_clear"
    wait_for_key
}

# 通用服务控制器
control_service() {
    local action="$1"
    local action_desc="$2"
    local title_icon="$3"
    
    print_title "${title_icon} ${action_desc}所有服务"
    
    local all_success=true
    for service in "${!SERVICES[@]}"; do
        local service_info=(${SERVICES[$service]})
        local compose_file=${service_info[3]}
        
        if [ -f "$compose_file" ]; then
            log_step "${action_desc} ${service}..."
            if docker compose -f "$compose_file" "$action" &>/dev/null; then
                log_success "${service} ${action_desc}成功"
            else
                log_error "${service} ${action_desc}失败"
                all_success=false
            fi
        else
            log_warning "${service} 未安装，跳过"
        fi
    done
    
    echo
    if $all_success; then
        log_success "所有服务已成功${action_desc}"
    else
        log_error "部分服务操作失败，请检查日志"
    fi
    
    if [[ "$action" == "start" || "$action" == "restart" ]]; then
        loading_animation "等待服务稳定..." 3
        show_status_and_info "no_clear"
    fi
    wait_for_key
}

# 卸载所有服务
uninstall_services() {
    print_title "🗑️ 完全卸载服务" "将移除所有容器、配置和数据"
    log_error "警告：此操作不可逆，将永久删除所有服务和相关文件！"
    
    if ! confirm_action "您确定要完全卸载所有服务吗？"; then
        log_info "操作已取消。"; wait_for_key; return
    fi
    echo

    for service in "${!SERVICES[@]}"; do
        local service_info=(${SERVICES[$service]})
        local service_dir=${service_info[0]}
        local compose_file=${service_info[3]}
        
        if [ -f "$compose_file" ]; then
            log_step "正在停止并移除 ${service} 服务..."
            docker compose -f "$compose_file" down -v --remove-orphans &>/dev/null
            log_step "正在删除 ${service} 的配置文件目录..."
            rm -rf "$service_dir"
            log_success "${service} 已完全卸载"
        else
            log_info "${service} 未安装，无需卸载。"
        fi
        echo
    done
    
    if confirm_action "是否删除相关 Docker 镜像？(这不会影响其他容器)"; then
        local images_to_remove=""
        for service in "${!SERVICES[@]}"; do
            local service_info=(${SERVICES[$service]})
            images_to_remove+=" ${service_info[2]}"
        done
        log_step "删除 Docker 镜像..."
        docker rmi ${images_to_remove} &>/dev/null || true
        log_success "相关 Docker 镜像已清理"
    fi

    print_separator
    log_success "所有服务和资源已成功卸载！"
    print_separator
    wait_for_key
}

# 显示状态和连接信息
show_status_and_info() {
    [ "$1" != "no_clear" ] && print_title "📊 服务状态与连接信息"

    local external_ip
    external_ip=$(get_external_ip)
    
    echo -e "${CYAN}${BOLD}  ${STAR} 服务器地址: ${WHITE}${external_ip}${NC}\n"

    # 容器状态
    echo -e "${BLUE}  ┌─ 容器运行状态${NC}"
    for service in "${!SERVICES[@]}"; do
        local service_info=(${SERVICES[$service]})
        local container_name=${service_info[1]}
        local service_dir=${service_info[0]}
        
        printf "  │  %-12s: " "${service}"
        if [ ! -d "$service_dir" ]; then
            echo -e "${GRAY}未安装${NC}"
            continue
        fi

        local status health
        status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
        
        case "$status" in
            "running")
                if [[ "$health" == "healthy" ]]; then echo -e "${GREEN}运行中 (健康)${NC}"
                elif [[ "$health" == "unhealthy" ]]; then echo -e "${YELLOW}运行中 (不健康)${NC}"
                else echo -e "${GREEN}运行中${NC}"; fi
                ;;
            "exited") echo -e "${RED}已停止${NC}" ;;
            "restarting") echo -e "${YELLOW}重启中${NC}" ;;
            *) echo -e "${GRAY}${status:-未找到}${NC}" ;;
        esac
    done
    echo -e "${BLUE}  └─${NC}\n"

    # 连接信息
    echo -e "${BLUE}  ┌─ 连接配置信息${NC}"
    echo -e "${BLUE}  │${NC} ${YELLOW}${BOLD}sing-box Shadowsocks${NC}"
    echo -e "${BLUE}  │${NC}   ├─ SS-1: ${WHITE}${SINGBOX_SS1_PORT} / ${SINGBOX_SS1_METHOD}${NC}"
    echo -e "${BLUE}  │${NC}   │  └─ 密码: ${GRAY}${SINGBOX_SS1_PASSWORD}${NC}"
    echo -e "${BLUE}  │${NC}   └─ SS-2: ${WHITE}${SINGBOX_SS2_PORT} / ${SINGBOX_SS2_METHOD}${NC}"
    echo -e "${BLUE}  │${NC}      └─ 密码: ${GRAY}${SINGBOX_SS2_PASSWORD}${NC}"
    echo -e "${BLUE}  │${NC}"
    echo -e "${BLUE}  │${NC} ${YELLOW}${BOLD}sing-box Anytls${NC}"
    echo -e "${BLUE}  │${NC}   ├─ 端口: ${WHITE}${SINGBOX_ANYTLS_PORT}${NC}"
    echo -e "${BLUE}  │${NC}   ├─ 用户: ${WHITE}${SINGBOX_ANYTLS_USER}${NC}"
    echo -e "${BLUE}  │${NC}   ├─ 密码: ${GRAY}${SINGBOX_ANYTLS_PASSWORD}${NC}"
    echo -e "${BLUE}  │${NC}   └─ SNI/Server Name: ${WHITE}(任意域名, 如 google.com)${NC}"
    echo -e "${BLUE}  │${NC}"
    echo -e "${BLUE}  │${NC} ${YELLOW}${BOLD}Snell${NC}"
    echo -e "${BLUE}  │${NC}   ├─ 端口: ${WHITE}${SNELL_PORT}${NC}"
    echo -e "${BLUE}  │${NC}   └─ PSK:  ${GRAY}${SNELL_PSK}${NC}"
    echo -e "${BLUE}  └─${NC}"

    [ "$1" != "no_clear" ] && wait_for_key
}

# 查看日志
show_logs() {
    print_title "📜 查看服务日志"
    
    PS3="$(echo -e "${CYAN}请选择要查看的服务日志 [输入数字]: ${NC}")"
    options=("sing-box" "snell" "返回主菜单")
    
    select opt in "${options[@]}"; do
        case $opt in
            "sing-box"|"snell")
                local service_info=(${SERVICES[$opt]})
                local compose_file=${service_info[3]}
                if [ -f "$compose_file" ]; then
                    echo -e "\n${YELLOW}正在实时跟踪 ${opt} 日志 (按 Ctrl+C 退出)...${NC}"
                    docker compose -f "$compose_file" logs -f --tail=100
                else
                    log_error "${opt} 未安装，无法查看日志。"
                fi
                wait_for_key
                break
                ;;
            "返回主菜单")
                break
                ;;
            *) log_error "无效选择，请输入正确的数字。" ;;
        esac
    done
}

# 主菜单
show_menu() {
    print_title "$SCRIPT_NAME" "$VERSION"

    echo -e "  ${GREEN}1) ${WHITE}一键部署服务 ${GRAY}(安装/重置)${NC}"
    echo -e "  ${BLUE}2) ${WHITE}查看状态和信息${NC}"
    echo -e "  ${CYAN}3) ${WHITE}查看服务日志${NC}"
    echo
    echo -e "  ${GREEN}4) ${WHITE}启动所有服务${NC}"
    echo -e "  ${YELLOW}5) ${WHITE}停止所有服务${NC}"
    echo -e "  ${PURPLE}6) ${WHITE}重启所有服务${NC}"
    echo -e "  ${RED}7) ${WHITE}完全卸载服务${NC}"
    echo
    echo -e "  ${GRAY}0) ${WHITE}退出脚本${NC}"
    print_separator
}

# 脚本启动横幅
print_startup_banner() {
    clear
    echo -e "${BLUE}"
cat << "EOF"
    ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗
    ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝
    ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ 
    ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  
    ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   
    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
EOF
    echo -e "${CYAN}${BOLD}                 服务管理器 v4.1${NC}"
    echo
    loading_animation "初始化脚本和环境检查..." 1
}

# 主函数
main() {
    check_system
    
    while true; do
        show_menu
        read -p "$(echo -e "${CYAN}请选择操作 [0-7]: ${NC}")" choice
        
        case $choice in
            1) deploy_services ;;
            2) show_status_and_info ;;
            3) show_logs ;;
            4) control_service "start" "启动" "▶️" ;;
            5) control_service "stop" "停止" "⏹️" ;;
            6) control_service "restart" "重启" "🔄" ;;
            7) uninstall_services ;;
            0)
                print_title "👋 再见" "感谢使用！"
                exit 0
                ;;
            *)
                log_error "无效选择，请输入 0-7 之间的数字"
                sleep 1
                ;;
        esac
    done
}

# 信号处理，确保 Ctrl+C 可以优雅退出
trap 'echo -e "\n${YELLOW}程序被中断，正在安全退出...${NC}"; tput cnorm; exit 130' INT TERM

# 脚本执行入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_startup_banner
    main "$@"
fi
