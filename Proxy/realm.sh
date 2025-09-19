#!/bin/bash

# Realm 一键安装配置脚本 (重构优化版)
# 支持系统: Ubuntu/Debian/CentOS/RHEL
# 作者: Auto Generated Script (Refactored by AI)

set -e
set -o pipefail

# --- 全局变量和常量 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REALM_INSTALL_DIR="/usr/local/bin"
REALM_CONFIG_DIR="/etc/realm"
REALM_LOG_DIR="/var/log/realm"
REALM_CONFIG_FILE="${REALM_CONFIG_DIR}/config.json" # <--- 已修改为 config.json
REALM_SERVICE_FILE="/etc/systemd/system/realm.service"
REALM_EXECUTABLE="${REALM_INSTALL_DIR}/realm"

# --- 基础函数 ---

# 统一格式化输出
print_msg() {
    local color=$1
    local level=$2
    local message=$3
    echo -e "${color}[${level}]${NC} ${message}"
}

print_info() {
    print_msg "${BLUE}" "INFO" "$1"
}

print_success() {
    print_msg "${GREEN}" "SUCCESS" "$1"
}

print_warning() {
    print_msg "${YELLOW}" "WARNING" "$1"
}

print_error() {
    print_msg "${RED}" "ERROR" "$1" >&2
}

# --- 核心功能函数 ---

# 检查脚本是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请尝试使用: sudo $0"
        exit 1
    fi
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|aarch64)
            ARCH_SUFFIX="$ARCH-unknown-linux-gnu"
            ;;
        armv7l)
            ARCH="armv7"
            ARCH_SUFFIX="armv7-unknown-linux-gnueabihf"
            ;;
        *)
            print_error "不支持的系统架构: $ARCH"
            exit 1
            ;;
    esac
    print_info "检测到系统架构: $ARCH"
}

# 检测并安装依赖
install_dependencies() {
    print_info "检查并安装依赖包..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "无法检测到操作系统"
        exit 1
    fi

    local PKG_MANAGER=""
    local PACKAGES="wget curl tar systemd"

    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        apt-get update -y
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        print_warning "未知的包管理器，跳过依赖安装。请确保 wget, curl, tar 已安装。"
        return
    fi
    
    # shellcheck disable=SC2086
    $PKG_MANAGER install -y $PACKAGES
}

# 从 GitHub API 获取最新版本号
get_latest_version() {
    print_info "获取 Realm 最新版本..."
    LATEST_VERSION=$(curl -sL "https://api.github.com/repos/zhboner/realm/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then
        print_error "获取最新版本信息失败，请检查网络或稍后再试。"
        exit 1
    fi
    print_success "最新版本为: $LATEST_VERSION"
}

# 下载并解压 Realm
download_realm() {
    local download_url="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}/realm-${ARCH_SUFFIX}.tar.gz"
    
    print_info "开始下载 Realm..."
    print_info "下载链接: ${download_url}"

    local temp_dir
    temp_dir=$(mktemp -d)
    
    if ! wget -qO "${temp_dir}/realm.tar.gz" "$download_url"; then
        print_error "下载失败！请检查链接或网络。"
        rm -rf "$temp_dir"
        exit 1
    fi

    print_info "解压文件中..."
    if ! tar -xzf "${temp_dir}/realm.tar.gz" -C "$temp_dir"; then
        print_error "解压失败！"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 将解压后的文件路径存入全局变量，方便后续使用
    REALM_TEMP_FILE="${temp_dir}/realm"
    
    print_success "下载并解压成功。"
}

# 安装 Realm 主程序
install_realm() {
    print_info "安装 Realm 主程序..."
    
    # 创建所需目录
    mkdir -p "$REALM_INSTALL_DIR" "$REALM_CONFIG_DIR" "$REALM_LOG_DIR"
    
    # 移动可执行文件
    mv "$REALM_TEMP_FILE" "$REALM_EXECUTABLE"
    chmod +x "$REALM_EXECUTABLE"
    
    # 清理临时目录
    rm -rf "$(dirname "$REALM_TEMP_FILE")"
    
    print_success "Realm 已安装到: $REALM_EXECUTABLE"
}

# 创建 JSON 配置文件
create_config() {
    print_info "创建 JSON 配置文件..."
    
    # 使用 cat 和 EOF 创建 JSON 配置文件，注意转义
    cat > "$REALM_CONFIG_FILE" << EOF
{
    "log": {
        "level": "warn",
        "output": "${REALM_LOG_DIR}/realm.log"
    },
    "endpoints": [
        {
            "listen": "0.0.0.0:1080",
            "remote": "8.8.8.8:53"
        }
    ]
}
EOF

    print_success "配置文件创建成功: $REALM_CONFIG_FILE"
}

# 创建 systemd 服务文件
create_service() {
    print_info "创建 systemd 服务..."
    
    cat > "$REALM_SERVICE_FILE" << EOF
[Unit]
Description=Realm - A simple, high performance relay server
Documentation=https://github.com/zhboner/realm
After=network.target network-online.target
Wants=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=${REALM_EXECUTABLE} -c ${REALM_CONFIG_FILE}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "systemd 服务创建完成。"
}

# 卸载 Realm
uninstall_realm() {
    print_warning "这将彻底卸载 Realm 及其所有配置文件！"
    read -p "您确定要继续吗? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消。"
        return
    fi
    
    print_info "停止并禁用 Realm 服务..."
    systemctl stop realm 2>/dev/null || true
    systemctl disable realm 2>/dev/null || true
    
    print_info "删除相关文件..."
    rm -f "$REALM_SERVICE_FILE"
    rm -f "$REALM_EXECUTABLE"
    rm -rf "$REALM_CONFIG_DIR"
    rm -rf "$REALM_LOG_DIR"
    
    systemctl daemon-reload
    print_success "Realm 已成功卸载。"
}

# 显示使用帮助
show_usage() {
    print_success "Realm 安装配置完成！"
    echo
    echo "--------------------------------------------------"
    echo -e "配置文件: ${YELLOW}${REALM_CONFIG_FILE}${NC}"
    echo -e "日志文件: ${YELLOW}${REALM_LOG_DIR}/realm.log${NC}"
    echo "--------------------------------------------------"
    echo
    echo "常用命令:"
    echo "  systemctl start realm      # 启动服务"
    echo "  systemctl stop realm       # 停止服务"
    echo "  systemctl restart realm    # 重启服务"
    echo "  systemctl status realm     # 查看状态"
    echo "  systemctl enable realm     # 设置开机启动"
    echo "  journalctl -u realm -f   # 实时查看日志"
    echo
    print_warning "请根据您的需求修改配置文件，然后重启服务！"
}


# --- 流程函数 ---

# 完整安装流程
do_install() {
    print_info "开始完整安装流程..."
    if [[ -f "$REALM_EXECUTABLE" ]]; then
        print_warning "Realm 似乎已安装。如果需要重新安装，请先卸载。"
        return
    fi
    
    detect_arch
    install_dependencies
    get_latest_version
    download_realm
    install_realm
    create_config
    create_service
    show_usage
    
    read -p "是否立即启动并设置开机自启? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start realm
        systemctl enable realm
        print_success "Realm 服务已启动并设为开机自启。"
    fi
}

# 更新 Realm 流程
do_update() {
    print_info "开始更新 Realm..."
    if [[ ! -f "$REALM_EXECUTABLE" ]]; then
        print_error "Realm 未安装，无法更新。"
        return
    fi
    
    detect_arch
    get_latest_version
    download_realm
    
    print_info "正在停止当前服务..."
    systemctl stop realm || true
    
    print_info "替换旧的执行文件..."
    mv "$REALM_TEMP_FILE" "$REALM_EXECUTABLE"
    chmod +x "$REALM_EXECUTABLE"
    
    # 清理临时目录
    rm -rf "$(dirname "$REALM_TEMP_FILE")"
    
    print_info "正在启动新版服务..."
    systemctl start realm
    
    print_success "Realm 更新完成！"
    "$REALM_EXECUTABLE" --version
}

# --- 主逻辑 ---

main() {
    check_root
    
    # 脚本参数处理
    if [[ $# -gt 0 ]]; then
        case $1 in
            install) do_install ;;
            update) do_update ;;
            uninstall) uninstall_realm ;;
            *) echo "用法: $0 [install|update|uninstall]" ; exit 1 ;;
        esac
        exit 0
    fi

    # 交互式菜单
    echo "================================="
    echo "    Realm 一键安装配置脚本"
    echo "================================="
    echo "1. 安装 Realm"
    echo "2. 更新 Realm"
    echo "3. 卸载 Realm"
    echo "---------------------------------"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 重启服务"
    echo "7. 查看状态"
    echo "8. 查看日志"
    echo "0. 退出脚本"
    echo "================================="
    read -p "请输入您的选择 [0-8]: " choice

    case $choice in
        1) do_install ;;
        2) do_update ;;
        3) uninstall_realm ;;
        4) systemctl start realm && print_success "服务已启动" ;;
        5) systemctl stop realm && print_success "服务已停止" ;;
        6) systemctl restart realm && print_success "服务已重启" ;;
        7) systemctl status realm --no-pager ;;
        8) journalctl -u realm -f ;;
        0) exit 0 ;;
        *) print_error "无效输入！" ;;
    esac
}

# 脚本执行入口
main "$@"
