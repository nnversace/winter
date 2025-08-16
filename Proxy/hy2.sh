#!/bin/bash

# Hysteria2 一键配置脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 设置固定密码
set_fixed_password() {
    PASSWORD="IUmuU/NjIQhHPMdBz5WONA=="
    log_info "使用固定密码: $PASSWORD"
}

# 获取Cloudflare 15年证书
get_cloudflare_cert() {
    log_step "获取Cloudflare 15年证书..."
    
    # 创建证书目录
    mkdir -p /etc/hysteria
    
    # 安装Cloudflare 15年证书
    log_info "正在安装Cloudflare 15年证书..."
    
    # Cloudflare的15年证书（2025-2040）
    cat > /etc/hysteria/cert.crt << 'EOF'
-----BEGIN CERTIFICATE-----
MIIEFTCCAv2gAwIBAgIUO06Pov3Uvy7zCunkZIxTcZRyfEQwDQYJKoZIhvcNAQEL
BQAwgagxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQH
Ew1TYW4gRnJhbmNpc2NvMRkwFwYDVQQKExBDbG91ZGZsYXJlLCBJbmMuMRswGQYD
VQQLExJ3d3cuY2xvdWRmbGFyZS5jb20xNDAyBgNVBAMTK01hbmFnZWQgQ0EgOTg5
MTkzYmZkNDlmMmFmYTEyMmIzYWU4ZjllZThhZGEwHhcNMjUwNzExMjMwNjAwWhcN
NDAwNzA3MjMwNjAwWjAiMQswCQYDVQQGEwJVUzETMBEGA1UEAxMKQ2xvdWRmbGFy
ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMbthLArs2Gc4Ux8H41x
R5s0LkzPJzdPRYCqI57NSMxoNfB5sliWFF8tl5f6q7zPm5A9vrycANW82O24eRHy
N9sKV9nhIEC4YfzVdXOXqXLqzrXXjN4HR6mEIJtEFaRLkWkhmBv35/jooBkH/LDn
toIEbc8eDv2GwRJFCxBR0VBB5kuJvgf/2pYhqvo2yl9OR4WuTW+7/6mWCVk7/dqZ
hFgyFi6bRo8VyZZ0Sha+t+i25Wc9fkORMjjcR5mvVZj+TqyLg/jLQHhYjt1SHZET
27N7qNon/Zrh5jJzydzAPjzYBu6w1A4DF5mVCE6sNd7P/jDJUG5AYY8IspoLpl0p
TfsCAwEAAaOBuzCBuDATBgNVHSUEDDAKBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAA
MB0GA1UdDgQWBBTOPCCmmzz/dJ8dQmqEaNRRCzMu5TAfBgNVHSMEGDAWgBQUT7o7
DO9GlGjD92Y2g1QMOn9+6jBTBgNVHR8ETDBKMEigRqBEhkJodHRwOi8vY3JsLmNs
b3VkZmxhcmUuY29tLzYzYWU0ZWUzLTIwZjAtNGNiYS1hNjNmLTEwYTc0NTM3Yzk4
Mi5jcmwwDQYJKoZIhvcNAQELBQADggEBAGobcnG0OXgiAS+pDECtl/eiLCrwVYHJ
P23fOuWAaAKNgbXCRrzW0iBOzo4VKKCmMycUbjwLB9uhbB1y6LqUXbQgBSsOY/m/
3Ox4FVHUvj4srTyb0uyOoaFbEhbW6G/ZTKNm6eSWcPdEopE1gkb2SmK3JLawsUbE
+DpccIr2rHRPZ+eSL+Qxs/mzWkrinAbv0XX6gFaGfr9f6IJf8ISx8WYMLxyl6Gm+
ZAFjNW6ujzT0Kx47vPcHuvXhVvhfGiY38DUVvD8FovEMl1++Kk0NKP1er8YK5lCl
rp6myEYG8XaM80aVU2Fv/Cm28sV43+y8uzPpQDTefVoVvi6zbYpot+A=
-----END CERTIFICATE-----
EOF
    
    cat > /etc/hysteria/private.key << 'EOF'
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDG7YSwK7NhnOFM
fB+NcUebNC5Mzyc3T0WAqiOezUjMaDXwebJYlhRfLZeX+qu8z5uQPb68nADVvNjt
uHkR8jfbClfZ4SBAuGH81XVzl6ly6s6114zeB0ephCCbRBWkS5FpIZgb9+f46KAZ
B/yw57aCBG3PHg79hsESRQsQUdFQQeZLib4H/9qWIar6NspfTkeFrk1vu/+plglZ
O/3amYRYMhYum0aPFcmWdEoWvrfotuVnPX5DkTI43EeZr1WY/k6si4P4y0B4WI7d
Uh2RE9uze6jaJ/2a4eYyc8ncwD482AbusNQOAxeZlQhOrDXez/4wyVBuQGGPCLKa
C6ZdKU37AgMBAAECggEARdZdHvw4naxV7GQnL6D1YqePGaggPGq4G9OfbcDkLd7o
EOSomDEYNdHrxo9ae47nLlx++fhK0r7Z6Zs55fMDaQLYlMVUbWROAlVuRoaYFqAY
sf5alhg4MGsSh2//qQ5enmoM3MTLy7bffeov7Gtsx3iGlJAY8yi7344dtD0FHwdl
N3YcKoh1wG2eXU99MN47+7PIO2My3Ck5BjFF52FZd1tba6VMpjZLnKjf8pxYEYB9
q/iSpbFh1nWU3o4O24gb5MW2g1SkizOyoHoz9a9FOIRoT377iK/ZwXhv8tUr/pbF
ffPpf9J7KILS1rNf3CEbzSJ48rNiFFLSix0fERLUAQKBgQDl/SpNCUVbEHXAPISf
me2YMtW6Tvg92GU5KsTlFac0QeiAYc5M30UvPmC3hoY2uR8jE/NQNoR3PHMoFlxX
vD2bloG5e4YUrVAWGktBkRKsDPJ/bam0G87PET4roqPlRmuBSMOBiffIrYlPZY1h
m/rKRX/obLHnW+t8L5+SSG2I8QKBgQDdbQuNHadErMyv3wKyEOlD3SyPCusewNsg
Hwpd7L5R8s6J+PFg0C7CAsCmjWngdAmGufDTojCbkPqfHGSlGWG6xp8HRfVUB0q4
oFjhKfuLx+W5wjhg6Q0CpGO19PrkUHlLYaOJe+ZVviNF+n9sel2o5q1jf3YI49aj
Y9bHunQlqwKBgE1ObMKaRCrY/IuSjA3NwtRu+fJ3CvBW5adynd5XCe4B3XIR7jNe
tTWtJPtrh3+reDDlStsCiEJAGoE2CvIevyKmU5KSV75ph0r2qacvaXRVocl9hhaZ
ZkmqBRjLwYWWxxoc6EKJqrVUx5vdiclukb0d4WGx75bSCfSjWWLlX5QxAoGBALWM
QNpVI9406CaS7PzezMMtxukJhLnUWlW93ZwhDfLW5+1MRWyhhJTh+N8WN2cm/OCP
+Bstcjk656Ipf4O2ieDAFYe7HmjlCajTH8yNxYdYQMzLp7odmuM9sdtwn30vViQu
TA3fnn1Sxk0MFAn3Um+3oxZfXYHwfP2+UE22XKC9AoGBAKoA5F5+2xnZxBprCOBQ
xTrEFzgWAtAMplBOMphWakk7XdQRvMP84lqVs9E6brdq1mE3MJMIEJwPfdwFAqsD
EGSbsfhlFNYpsYn9rGTKd/4uL27oIaGViNTHz0h+B30t/dtjzs6Lxjadzuys8PN4
bXiN0Dp6xbPXsLEvzXEn8T58
-----END PRIVATE KEY-----
EOF
    
    # 设置证书文件权限
    chmod 600 /etc/hysteria/private.key
    chmod 644 /etc/hysteria/cert.crt
    
    log_info "Cloudflare 15年证书已安装 (2025-2040)"
}

# 生成Hysteria2配置文件
generate_hysteria_config() {
    log_step "生成Hysteria2配置文件..."
    
    cat > ./hysteria.yaml << EOF
listen: :5271
tls:
  cert: /etc/hysteria/cert.crt 
  key: /etc/hysteria/private.key
quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
udpIdleTimeout: 60s
auth:
  type: password
  password: $PASSWORD
EOF
    
    log_info "Hysteria2配置文件已生成: ./hysteria.yaml"
}

# 生成Docker Compose文件
generate_docker_compose() {
    log_step "生成Docker Compose文件..."
    
    cat > ./docker-compose.yml << EOF
services:
  hy2:
    image: tobyxdd/hysteria
    container_name: hy2
    restart: always
    network_mode: host
    volumes:
      - ./hysteria.yaml:/etc/hysteria.yaml
      - /etc/hysteria:/etc/hysteria:ro
    command: ["server", "-c", "/etc/hysteria.yaml"]
EOF
    
    log_info "Docker Compose文件已生成: ./docker-compose.yml"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/redhat-release ]]; then
        SYSTEM="centos"
    elif [[ -f /etc/debian_version ]]; then
        SYSTEM="debian"
    elif [[ -f /etc/arch-release ]]; then
        SYSTEM="arch"
    else
        log_error "不支持的系统类型"
        exit 1
    fi
    log_info "检测到系统类型: $SYSTEM"
}



# 开放端口
open_ports() {
    log_step "确保端口5271开放..."
    
    # 检查端口是否被占用
    if netstat -tuln | grep -q ":5271 "; then
        log_warn "端口5271已被占用，请检查是否有其他服务在使用"
    else
        log_info "端口5271可用"
    fi
    
    log_info "端口5271检查完成"
}

# 查看证书SHA256指纹
check_certificate() {
    log_step "检查证书SHA256指纹..."
    
    CERT_PATH="/etc/hysteria/cert.crt"
    
    if [[ -f "$CERT_PATH" ]]; then
        log_info "找到证书文件: $CERT_PATH"
        
        # 获取证书SHA256指纹
        FINGERPRINT=$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        
        if [[ -n "$FINGERPRINT" ]]; then
            echo ""
            echo "=================================="
            echo -e "${GREEN}证书SHA256指纹:${NC}"
            echo -e "${YELLOW}$FINGERPRINT${NC}"
            echo "=================================="
            echo ""
            
            # 保存指纹到文件
            echo "$FINGERPRINT" > /tmp/hysteria_cert_fingerprint.txt
            log_info "证书指纹已保存到: /tmp/hysteria_cert_fingerprint.txt"
        else
            log_error "无法获取证书指纹"
        fi
        
        # 显示证书详细信息
        echo ""
        log_info "证书详细信息:"
        echo "--------------------------------"
        openssl x509 -in "$CERT_PATH" -noout -text | grep -E "(Subject:|Issuer:|Not Before:|Not After:)" 2>/dev/null || true
        echo "--------------------------------"
        
    else
        log_error "未找到证书文件: $CERT_PATH"
        log_warn "请确保证书文件存在或检查路径是否正确"
    fi
}

# 启动Hysteria2服务
start_hysteria_service() {
    log_step "启动Hysteria2服务..."
    
    if command -v docker-compose &> /dev/null; then
        docker-compose down 2>/dev/null || true
        docker-compose up -d
        log_info "Hysteria2服务已启动"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker compose down 2>/dev/null || true
        docker compose up -d
        log_info "Hysteria2服务已启动"
    else
        log_warn "Docker Compose未安装，请手动启动服务"
        log_info "手动启动命令: docker-compose up -d"
    fi
}

# 保存配置信息
save_config_info() {
    log_step "保存配置信息..."
    
    cat > /tmp/hysteria2_config.txt << EOF
================================
Hysteria2 配置信息
================================
服务器地址: $PUBLIC_IP
端口: 5271
认证密码: $PASSWORD
证书指纹: $FINGERPRINT
配置文件: $(pwd)/hysteria.yaml
Docker文件: $(pwd)/docker-compose.yml
================================
生成时间: $(date)
================================
EOF
    
    log_info "配置信息已保存到: /tmp/hysteria2_config.txt"
}

check_hysteria_status() {
    log_step "检查Hysteria2服务状态..."
    
    if command -v docker &> /dev/null; then
        if docker ps | grep -q "hy2"; then
            log_info "Hysteria2容器正在运行"
            docker ps | grep "hy2"
        else
            log_warn "Hysteria2容器未运行"
        fi
    else
        log_warn "Docker未安装或不可用"
    fi
}

# 显示连接信息
show_connection_info() {
    log_step "显示连接信息..."
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || echo "无法获取公网IP")
    
    echo ""
    echo "=================================="
    echo -e "${GREEN}Hysteria2 连接信息:${NC}"
    echo "--------------------------------"
    echo -e "服务器地址: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "端口: ${YELLOW}5271${NC}"
    echo -e "认证密码: ${YELLOW}$PASSWORD${NC}"
    echo -e "证书指纹: ${YELLOW}$FINGERPRINT${NC}"
    echo "=================================="
    echo ""
    echo -e "${BLUE}客户端配置示例:${NC}"
    echo "--------------------------------"
    echo "server: $PUBLIC_IP:5271"
    echo "auth: $PASSWORD"
    echo "tls:"
    echo "  sni: $PUBLIC_IP"
    echo "  insecure: false"
    echo "  pinSHA256: $FINGERPRINT"
    echo "--------------------------------"
    echo ""
}

# 主函数
main() {
    echo "=================================="
    echo -e "${BLUE}Hysteria2 一键配置脚本${NC}"
    echo "=================================="
    
    check_root
    detect_system
    set_fixed_password
    get_cloudflare_cert
    open_ports
    generate_hysteria_config
    generate_docker_compose
    check_certificate
    start_hysteria_service
    check_hysteria_status
    show_connection_info
    save_config_info
    
    echo ""
    log_info "脚本执行完成！"
    log_info "完整配置信息已保存到: /tmp/hysteria2_config.txt"
    log_info "证书指纹已保存到: /tmp/hysteria_cert_fingerprint.txt"
    
    echo ""
    echo -e "${GREEN}下一步操作:${NC}"
    echo "1. 检查服务状态: docker-compose ps"
    echo "2. 查看服务日志: docker-compose logs -f hy2"
    echo "3. 重启服务: docker-compose restart hy2"
    echo "4. 停止服务: docker-compose down"
}

# 运行主函数
main "$@"
