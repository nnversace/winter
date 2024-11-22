#!/bin/bash

# 检测并安装所需的指令
check_and_install() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 未安装，正在安装..."
        apt-get install -y $1
    else
        echo "$1 已安装，跳过安装。"
    fi
}

# 更新系统
echo "更新系统..."
apt-get update && apt-get full-upgrade -y

# 安装必要的工具
check_and_install jq
check_and_install wget
check_and_install dnsutils

# 安装 Docker
echo "安装 Docker..."
wget -qO- https://get.docker.com | bash -s docker

# 内核调优
echo "进行内核调优..."
wget https://raw.githubusercontent.com/nnversace/winter/main/bbr.sh
chmod +x bbr.sh
bash bbr.sh

# 路由测试工具
echo "安装路由测试工具 nexttrace..."
bash -c "$(wget -qO- https://github.com/sjlleo/nexttrace/raw/main/nt_install.sh)"

# 开启 tuned 并设置网络性能优化
echo "开启 tuned 并设置网络性能优化配置..."
check_and_install tuned
systemctl enable tuned.service
systemctl start tuned.service

# 在 /root 目录下创建 kernel 文件夹并进入
echo "创建 /root/kernel 目录并进入..."
mkdir -p /root/kernel
cd /root/kernel

# 下载和安装内核包
echo "下载内核包..."
wget -q -O - https://api.github.com/repos/love4taylor/linux-self-use-deb/releases/latest | \
    jq -r '.assets[] | select(.name | contains ("deb")) | select(.name | contains ("cloud")) | .browser_download_url' | \
    xargs wget -q --show-progress

# 安装内核包
echo "安装内核包..."
dpkg -i linux-headers-*-egoist-cloud_*.deb
dpkg -i linux-image-*-egoist-cloud_*.deb

# 修改 SSH 配置：修改端口，禁用密码登录
echo "修改 SSH 配置..."
sed -i 's/#Port 22/Port 14566/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# 修改系统 DNS 为 8.8.8.8 并禁用 IPv6
echo "修改系统 DNS 并禁用 IPv6..."
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p

echo "所有步骤完成！"

cat << "EOF"
==============================================
重要提示：
1. SSH 端口已修改为 14566
2. 已禁用密码登录，请确保已添加 SSH 密钥
3. IPv6 已禁用
4. 系统 DNS 已设置为 8.8.8.8
==============================================
EOF
