#!/bin/bash
#
# ==================================================================
#  本地 Docker Compose 项目一键启动脚本
# ==================================================================
#
# 这个脚本会启动位于 /root/ 目录下的一个或多个指定的
# Docker Compose 项目。
#
# 使用方法:
# ./deploy.sh [文件夹名1] [文件夹名2] ...
# 例如: ./deploy.sh snell sing-box
#
# ==================================================================

# 设置脚本在遇到错误时立即退出
set -e

# --- 函数定义 ---

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

if ! command_exists docker || ! command_exists docker-compose; then
    echo "错误: Docker 或 Docker Compose 未安装。"
    echo "请先安装它们再运行此脚本。"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "错误: Docker 守护进程未运行。"
    echo "请启动 Docker 后再试。"
    exit 1
fi

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

    # 检查 docker-compose.yml 文件是否存在
    if [ ! -f "$PROJECT_DIR/docker-compose.yml" ] && [ ! -f "$PROJECT_DIR/docker-compose.yaml" ]; then
        echo "   ❌ 错误: 在 '$PROJECT_DIR' 中未找到 docker-compose.yml 或 docker-compose.yaml 文件，已跳过。"
        continue
    fi

    echo "   - 正在进入目录: $PROJECT_DIR"
    cd "$PROJECT_DIR"

    echo "   - 正在启动 Docker 容器..."
    docker-compose up -d

    echo "   ✅ 项目 '$project_name' 部署成功!"
    echo
done

# --- 结束语 ---
echo "======================================================"
echo "🎉 所有指定的项目已处理完毕！"
echo
echo "您可以使用 'docker ps' 命令查看正在运行的容器。"
echo "======================================================"

