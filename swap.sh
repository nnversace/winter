#!/bin/bash

# 定义 swap 文件大小（以 MB 为单位）
SWAP_SIZE_MB=1024

# 创建 swap 文件
fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB

# 设置 swap 文件权限
chmod 600 /swapfile

# 将文件设置为 swap 空间
mkswap /swapfile

# 启用 swap 文件
swapon /swapfile

# 将 swap 文件添加到 /etc/fstab 以便开机自动启用
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# 验证 swap 是否启用
swapon --show

# 输出当前的 swap 使用情况
free -h

echo "Swap file has been successfully created and enabled."
