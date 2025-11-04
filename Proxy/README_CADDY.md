# Caddy 反向代理配置指南

本指南介绍如何使用 `caddy.sh` 脚本快速配置 Caddy 作为反向代理，将外部请求转发到本地服务 `localhost:4173`。

## 功能特性

- ✅ 一键安装 Caddy 最新稳定版
- ✅ 自动配置反向代理到 localhost:4173
- ✅ 支持 HTTP 和 HTTPS (自动证书) 两种模式
- ✅ 自动配置 systemd 服务，支持开机自启
- ✅ 内置配置验证和安全头设置
- ✅ 详细的日志记录
- ✅ 支持配置热重载 (无服务中断)

## 系统要求

- **操作系统**: Ubuntu 18.04+ / Debian 10+
- **权限**: Root 或 sudo 权限
- **依赖**: curl, apt-transport-https (脚本会自动安装)

## 快速开始

### 1. 下载并运行脚本

```bash
# 添加执行权限
chmod +x caddy.sh

# 运行脚本
sudo ./caddy.sh
```

或者直接使用命令行参数：

```bash
# 直接安装
sudo ./caddy.sh install

# 重新配置
sudo ./caddy.sh reconfigure

# 卸载
sudo ./caddy.sh uninstall
```

### 2. 选择配置模式

脚本提供三种配置模式：

#### 模式 1: HTTP 模式 (推荐用于内网或开发环境)

- 监听指定端口 (默认 80)
- 不需要域名
- 适合内网访问或开发测试

**示例**：
```bash
监听端口: 80 (或自定义如 8080)
访问地址: http://YOUR_SERVER_IP:80
```

#### 模式 2: HTTPS 模式 (推荐用于生产环境)

- 使用域名和自动 HTTPS
- 自动申请 Let's Encrypt SSL 证书
- 自动续期证书
- 需要域名已解析到服务器

**示例**：
```bash
域名: example.com
邮箱: admin@example.com
访问地址: https://example.com
```

**重要提示**：使用 HTTPS 模式前，请确保：
- 域名 DNS 已正确解析到服务器 IP
- 服务器防火墙开放了 80 和 443 端口
- 域名可以从公网访问

#### 模式 3: 自定义配置

- 完全自定义监听地址和后端服务
- 适合高级用户

## 配置示例

### HTTP 配置示例

```caddyfile
# Caddy 反向代理配置 - HTTP 模式
# 监听端口: 80
# 后端服务: localhost:4173

:80 {
    # 反向代理到后端服务
    reverse_proxy localhost:4173

    # 日志配置
    log {
        output file /var/log/caddy/access.log
        format json
    }

    # 请求头配置
    header {
        # 安全头
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "no-referrer-when-downgrade"
        
        # 隐藏服务器信息
        -Server
    }
}
```

### HTTPS 配置示例

```caddyfile
# Caddy 反向代理配置 - HTTPS 模式
# 域名: example.com
# 后端服务: localhost:4173
# 自动 HTTPS: 启用 (Let's Encrypt)

example.com {
    # 反向代理到后端服务
    reverse_proxy localhost:4173

    # 日志配置
    log {
        output file /var/log/caddy/access.log
        format json
    }

    # 请求头配置
    header {
        # 安全头
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "no-referrer-when-downgrade"
        
        # 隐藏服务器信息
        -Server
    }

    # TLS 配置
    tls admin@example.com
}
```

## 常用命令

### 服务管理

```bash
# 启动服务
sudo systemctl start caddy

# 停止服务
sudo systemctl stop caddy

# 重启服务
sudo systemctl restart caddy

# 查看状态
sudo systemctl status caddy

# 设置开机自启
sudo systemctl enable caddy

# 禁用开机自启
sudo systemctl disable caddy
```

### 配置管理

```bash
# 重载配置 (无服务中断)
sudo systemctl reload caddy

# 验证配置文件
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# 查看配置文件
cat /etc/caddy/Caddyfile

# 编辑配置文件
sudo nano /etc/caddy/Caddyfile
```

### 日志查看

```bash
# 实时查看服务日志
sudo journalctl -u caddy -f

# 查看最近100行日志
sudo journalctl -u caddy -n 100

# 查看访问日志
sudo tail -f /var/log/caddy/access.log

# 查看今天的日志
sudo journalctl -u caddy --since today
```

## 目录结构

```
/etc/caddy/              # 配置文件目录
├── Caddyfile            # 主配置文件

/var/lib/caddy/          # 数据目录 (证书存储)
├── certificates/        # SSL 证书
└── locks/              # 证书锁文件

/var/log/caddy/          # 日志目录
└── access.log          # 访问日志 (JSON 格式)
```

## 防火墙配置

如果使用防火墙，需要开放相应端口：

```bash
# HTTP 模式 - 开放 80 端口
sudo ufw allow 80/tcp

# HTTPS 模式 - 开放 80 和 443 端口
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 自定义端口 - 例如 8080
sudo ufw allow 8080/tcp
```

## 高级配置

### 1. 修改后端服务地址

编辑 `/etc/caddy/Caddyfile`，修改 `reverse_proxy` 行：

```caddyfile
:80 {
    reverse_proxy localhost:8080  # 修改为其他端口
}
```

然后重载配置：
```bash
sudo systemctl reload caddy
```

### 2. 添加负载均衡

```caddyfile
:80 {
    reverse_proxy localhost:4173 localhost:4174 localhost:4175 {
        lb_policy round_robin
    }
}
```

### 3. 添加健康检查

```caddyfile
:80 {
    reverse_proxy localhost:4173 {
        health_uri /health
        health_interval 10s
        health_timeout 5s
    }
}
```

### 4. 配置缓存

```caddyfile
:80 {
    reverse_proxy localhost:4173
    
    @static {
        path *.js *.css *.png *.jpg *.jpeg *.gif *.ico *.svg *.woff *.woff2
    }
    
    header @static Cache-Control "public, max-age=31536000"
}
```

### 5. 启用 Gzip 压缩

```caddyfile
:80 {
    encode gzip zstd
    reverse_proxy localhost:4173
}
```

### 6. 添加 IP 限制

```caddyfile
:80 {
    @blocked {
        remote_ip 1.2.3.4
    }
    
    handle @blocked {
        abort
    }
    
    reverse_proxy localhost:4173
}
```

### 7. 配置多个站点

```caddyfile
# 站点 1
site1.example.com {
    reverse_proxy localhost:4173
}

# 站点 2
site2.example.com {
    reverse_proxy localhost:8080
}

# HTTP 站点
:80 {
    reverse_proxy localhost:3000
}
```

## 故障排查

### 1. 服务无法启动

```bash
# 查看详细错误信息
sudo journalctl -u caddy -n 50

# 验证配置文件
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# 检查端口占用
sudo netstat -tulpn | grep :80
```

### 2. HTTPS 证书申请失败

常见原因：
- 域名未正确解析到服务器
- 防火墙未开放 80 和 443 端口
- 服务器无法访问 Let's Encrypt 服务器

解决方法：
```bash
# 检查域名解析
dig +short yourdomain.com

# 测试端口连通性
curl -I http://yourdomain.com

# 查看证书申请日志
sudo journalctl -u caddy | grep -i "acme\|certificate\|tls"
```

### 3. 502 Bad Gateway

原因：后端服务 localhost:4173 未运行

解决方法：
```bash
# 检查后端服务是否运行
netstat -tulpn | grep :4173

# 或使用 ss 命令
ss -tulpn | grep :4173

# 测试后端服务
curl http://localhost:4173
```

### 4. 权限问题

```bash
# 检查目录权限
ls -la /etc/caddy
ls -la /var/lib/caddy
ls -la /var/log/caddy

# 重新设置权限
sudo chown -R caddy:caddy /var/lib/caddy
sudo chown -R caddy:caddy /var/log/caddy
sudo chmod 755 /etc/caddy
```

### 5. 配置修改后不生效

```bash
# 方法1: 重载配置 (推荐，无中断)
sudo systemctl reload caddy

# 方法2: 重启服务
sudo systemctl restart caddy

# 方法3: 使用 Caddy 命令重载
sudo caddy reload --config /etc/caddy/Caddyfile
```

## 性能优化

### 1. 调整文件描述符限制

编辑 `/etc/systemd/system/caddy.service`：

```ini
[Service]
LimitNOFILE=1048576
LimitNPROC=512
```

然后重载服务：
```bash
sudo systemctl daemon-reload
sudo systemctl restart caddy
```

### 2. 启用 HTTP/2

Caddy 默认启用 HTTP/2，无需额外配置。

### 3. 配置缓冲区大小

```caddyfile
:80 {
    reverse_proxy localhost:4173 {
        flush_interval -1
        buffer_requests
    }
}
```

## 安全建议

1. **使用 HTTPS**: 生产环境建议使用 HTTPS 模式
2. **定期更新**: 定期更新 Caddy 到最新版本
3. **限制访问**: 使用防火墙或 Caddy 配置限制访问来源
4. **监控日志**: 定期检查访问日志，发现异常访问
5. **备份配置**: 定期备份配置文件

```bash
# 备份配置
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d)

# 更新 Caddy
sudo apt-get update
sudo apt-get upgrade caddy
```

## 卸载

使用脚本卸载：

```bash
sudo ./caddy.sh uninstall
```

或手动卸载：

```bash
# 停止并禁用服务
sudo systemctl stop caddy
sudo systemctl disable caddy

# 卸载 Caddy
sudo apt-get remove --purge caddy

# 删除配置和数据
sudo rm -rf /etc/caddy
sudo rm -rf /var/lib/caddy
sudo rm -rf /var/log/caddy
```

## 参考资源

- [Caddy 官方文档](https://caddyserver.com/docs/)
- [Caddy 反向代理指南](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Caddyfile 配置语法](https://caddyserver.com/docs/caddyfile)
- [Caddy 社区论坛](https://caddy.community/)

## 常见问题 (FAQ)

### Q: Caddy 和 Nginx 相比有什么优势？

A: Caddy 的主要优势：
- 自动 HTTPS 配置和证书管理
- 配置语法更简洁易懂
- 默认安全配置
- 内置 HTTP/2 和 HTTP/3 支持

### Q: 可以同时运行多个 Caddy 实例吗？

A: 可以，但需要使用不同的配置文件和监听端口。

### Q: 如何查看 Caddy 版本？

A: 
```bash
caddy version
```

### Q: 证书存储在哪里？

A: 
```bash
/var/lib/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```

### Q: 如何强制更新证书？

A:
```bash
sudo rm -rf /var/lib/caddy/certificates/
sudo systemctl restart caddy
```

### Q: 支持 WebSocket 吗？

A: 支持，Caddy 默认支持 WebSocket，无需额外配置。

### Q: 如何配置基本认证？

A:
```caddyfile
:80 {
    basicauth {
        username hashed_password
    }
    reverse_proxy localhost:4173
}
```

生成密码哈希：
```bash
caddy hash-password
```

## 支持

如有问题或建议，请查阅：
- Caddy 官方文档
- GitHub Issues
- 社区论坛

---

**版本**: 1.0  
**最后更新**: 2024  
**许可证**: MIT
