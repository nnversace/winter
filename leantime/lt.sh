#!/bin/bash

# Leantime 官方配置一键部署脚本

set -e

echo "🚀 开始部署 Leantime（官方配置）..."

# 检查当前目录
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 请确保在包含 docker-compose.yml 的目录中运行此脚本"
    exit 1
fi

# 停止现有服务
echo "🛑 停止现有服务..."
docker compose down 2>/dev/null || true

# 清理容器和卷（可选，谨慎使用）
read -p "是否要清理现有数据？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 清理现有数据..."
    docker compose down -v
    docker system prune -f
fi

# 检查 .env 文件
if [ ! -f ".env" ]; then
    echo "⚠️  .env 文件不存在，创建默认配置..."
    cat > .env << 'EOF'
# 数据库配置
LEAN_DB_HOST=mysql_leantime
LEAN_DB_USER=lean
LEAN_DB_PASSWORD=321.qwerty
LEAN_DB_DATABASE=leantime

MYSQL_ROOT_PASSWORD=321.qwerty
MYSQL_DATABASE=leantime
MYSQL_USER=lean
MYSQL_PASSWORD=321.qwerty

# 应用配置
LEAN_APP_URL=http://localhost:8080
LEAN_APP_DIR=/var/www/html
LEAN_DEBUG=0
LEAN_SESSION_PASSWORD=3c0kdQoDLb2xX3qPNGwRdYgpiFhUaPNXG9M0GZRKA9YRLD6Wn
LEAN_PORT=8080
LEAN_ALLOW_REG=true
LEAN_DEFAULT_LANGUAGE=en-US
LEAN_DEFAULT_TIMEZONE=America/Los_Angeles
EOF
    echo "✅ 已创建默认 .env 文件"
else
    echo "✅ 发现现有 .env 文件"
fi

# 运行权限助手
echo "🔧 设置数据库权限..."
docker compose --profile helper up mysql_helper --remove-orphans

# 启动服务
echo "🚀 启动 Leantime 服务..."
docker compose up -d

# 等待服务就绪
echo "⏳ 等待服务启动..."
echo "正在等待数据库健康检查..."

# 等待健康检查通过
timeout=300
counter=0
while [ $counter -lt $timeout ]; do
    if docker compose ps | grep -q "healthy"; then
        echo "✅ 数据库已就绪"
        break
    fi
    sleep 5
    counter=$((counter + 5))
    echo "等待中... ($counter/$timeout 秒)"
done

if [ $counter -ge $timeout ]; then
    echo "❌ 数据库启动超时，请检查日志"
    docker compose logs leantime_db
    exit 1
fi

# 再等待应用启动
echo "⏳ 等待应用完全启动..."
sleep 30

# 检查服务状态
echo "📊 服务状态："
docker compose ps

# 检查日志
echo -e "\n📝 最近的应用日志："
docker compose logs --tail=10 leantime

# 测试连接
echo -e "\n🔗 测试连接..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302"; then
    echo "✅ Leantime 服务响应正常"
else
    echo "⚠️  服务可能还在启动中，请稍等片刻"
fi

echo -e "\n🎉 部署完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 访问地址: http://localhost:8080"
echo "👤 首次访问将提示创建管理员账户"
echo ""
echo "💡 核心功能:"
echo "   📊 看板视图 (Kanban)"
echo "   📅 甘特图 (Gantt)" 
echo "   📋 表格视图 (Table)"
echo "   📝 列表视图 (List)"
echo "   🗓️  日历视图 (Calendar)"
echo ""
echo "🔧 管理命令:"
echo "   查看状态: docker compose ps"
echo "   查看日志: docker compose logs -f leantime"
echo "   停止服务: docker compose down"
echo "   重启服务: docker compose restart"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 如果服务没有正常响应，显示故障排查信息
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302"; then
    echo -e "\n🔍 如果无法访问，请尝试以下故障排查："
    echo "1. 等待更长时间（初次启动可能需要5-10分钟）"
    echo "2. 检查端口是否被占用: sudo netstat -tlnp | grep :8080"
    echo "3. 查看详细日志: docker compose logs leantime"
    echo "4. 检查防火墙设置"
    echo "5. 尝试重启: docker compose restart"
fi
