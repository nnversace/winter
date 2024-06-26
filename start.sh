#!/bin/bash

# 检查是否安装sudo
if ! command -v sudo &> /dev/null
then
    echo "sudo未安装，现在安装sudo..."
    apt-get update
    apt-get install -y sudo
else
    echo "sudo已安装。"
fi

# 设置时区为上海
echo "设置时区为上海..."
sudo timedatectl set-timezone Asia/Shanghai

# 更新包索引
echo "更新包索引..."
sudo apt-get update

# 升级已安装的软件包
echo "升级已安装的软件包..."
sudo apt-get upgrade -y

# 进行发行版升级
echo "进行发行版升级..."
sudo apt-get dist-upgrade -y

# 清理不再需要的包和依赖
echo "清理不再需要的包和依赖..."
sudo apt-get autoremove -y
sudo apt-get autoclean -y

# 安装必要的工具
echo "安装必要的工具..."
sudo apt-get install -y \
    curl \
    git \
    vim \
    htop \
    build-essential \
    wget \
    unzip \
    net-tools \
    software-properties-common

# 进行完整升级
echo "进行完整升级..."
sudo apt-get update && sudo apt-get full-upgrade -y

# 安装Docker
echo "安装Docker..."
curl -fsSL https://get.docker.com | sudo bash -s docker

# 检查是否有已知的可用更新，并列出所有升级的包
echo "检查已知的可用更新..."
sudo apt list --upgradable

echo "系统更新、必要工具安装、时区设置和Docker安装完成。"
