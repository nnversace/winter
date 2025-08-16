#!/bin/bash
#
# ==================================================================
#  本地 Docker Compose 项目一键启动脚本 (优化版)
# ==================================================================
#
# 这个脚本会自动检测 Docker Compose 的版本 (带空格或连字符),
# 然后启动位于 /root/ 目录下的一个或多个指定的项目。
#
# 使用方法:
# ./deploy.sh [文件夹名1] [文件夹名2] ...
# 例如: ./deploy.sh snell sing-box
#
# ==================================================================

# 设置脚本在遇到错误时立即退出
set -e

# --- 脚本主体 ---

echo "======================================================"
echo "  本地 Docker Compose 项目启动脚本"
echo "======================================================"
echo

# 1. 检查是否提供了参数
if [ $# -eq 0 ]; then
    echo "错误: 请提供至少一个位于 /root/ 的文件夹名作为参数。"
    echo "用法: $0 [文件夹名1] [文件夹名2] ..."
    exit 1
fi

# 2. 环境检查
echo "--- 正在检查环境依赖 ---"

# 检查 Docker 是否安装
if ! command -v docker >/dev/null 2>&1; then
    echo "错误: Docker 未安装。"
    echo "请先安装它再运行此脚本。"
    exit 1
fi

# 检查 Docker 守护进程是否运行
if ! docker info >/dev/null 2>&1; then
    echo "错误: Docker 守护进程未运行。"
    echo "请启动 Docker 后再试。"
    exit 1
fi

# **[优化]** 智能检测 Docker Compose 命令
if docker compose version >/dev/null 2>&1; then
    # 新版 `docker compose` (带空格) 可用
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    # 旧版 `docker-compose` (带连字符) 可用
    COMPOSE_CMD="docker-compose"
else
    # 两个版本都找不到
    echo "错误: Docker Compose 未安装。"
    echo "请确认 'docker compose' 或 'docker-compose' 命令可用。"
    exit 1
fi
echo "✅ Docker Compose 已找到, 将使用命令: '$COMPOSE_CMD'"

echo "✅ 环境依赖检查通过。"
echo

# 3. 遍历并启动所有指定的项目
for project_name in "$@"; do
    PROJECT_DIR="/root/$project_name"
    echo "--- 正在处理项目: $project_name ---"

    # 检查项目目录是否存在
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "   ❌ 错误: 目录 '$PROJECT_DIR' 不存在，已跳过。"
        continue
    fi

    # 检查 docker-compose.yml 或 docker-compose.yaml 文件是否存在
    if [ ! -f "$PROJECT_DIR/docker-compose.yml" ] && [ ! -f "$PROJECT_DIR/docker-compose.yaml" ]; then
        echo "   ❌ 错误: 在 '$PROJECT_DIR' 中未找到 docker-compose.yml 或 docker-compose.yaml 文件，已跳过。"
        continue
    fi

    echo "   - 正在进入目录: $PROJECT_DIR"
    cd "$PROJECT_DIR"

    echo "   - 正在启动 Docker 容器..."
    # **[优化]** 使用检测到的正确命令来执行
    $COMPOSE_CMD up -d

    echo "   ✅ 项目 '$project_name' 部署成功!"
    echo
done

# --- 结束语 ---
echo "======================================================"
echo "🎉 所有指定的项目已处理完毕！"
echo
echo "您可以使用 'docker ps' 命令查看正在运行的容器。"
echo "======================================================"
