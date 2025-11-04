# Caddy 反向代理快速开始

## 一键安装

### 方法 1: 交互式安装 (推荐)

```bash
cd /path/to/Proxy
sudo ./caddy.sh
```

然后选择 `1` 进行安装，按照提示完成配置。

### 方法 2: 命令行直接安装

```bash
cd /path/to/Proxy
sudo ./caddy.sh install
```

## 三步快速配置

### 步骤 1: 下载脚本并添加执行权限

```bash
chmod +x caddy.sh
```

### 步骤 2: 运行安装脚本

```bash
sudo ./caddy.sh install
```

### 步骤 3: 选择配置模式

安装过程中会提示选择：

**选项 1: HTTP 模式** (适合内网或测试)
- 输入监听端口，例如 `80` 或 `8080`
- 访问地址: `http://YOUR_SERVER_IP:PORT`

**选项 2: HTTPS 模式** (适合生产环境)
- 输入域名，例如 `example.com`
- 输入邮箱，例如 `admin@example.com`
- 确保域名已解析到服务器
- 访问地址: `https://example.com`

**选项 3: 自定义配置**
- 根据提示自定义配置

## 验证安装

安装完成后，运行：

```bash
# 检查服务状态
sudo systemctl status caddy

# 测试访问
curl -I http://localhost:80

# 查看日志
sudo journalctl -u caddy -f
```

## 常用命令速查

```bash
# 启动服务
sudo systemctl start caddy

# 停止服务
sudo systemctl stop caddy

# 重启服务
sudo systemctl restart caddy

# 重载配置 (无中断)
sudo systemctl reload caddy

# 查看状态
sudo systemctl status caddy

# 查看日志
sudo journalctl -u caddy -f

# 验证配置
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

## 配置文件位置

- **主配置**: `/etc/caddy/Caddyfile`
- **访问日志**: `/var/log/caddy/access.log`
- **证书目录**: `/var/lib/caddy/`

## 修改配置

### 1. 编辑配置文件

```bash
sudo nano /etc/caddy/Caddyfile
```

### 2. 验证配置

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

### 3. 重载配置

```bash
sudo systemctl reload caddy
```

## 使用示例配置

我们提供了一个包含多种场景的示例配置文件 `Caddyfile.example`：

```bash
# 查看示例
cat Caddyfile.example

# 使用示例配置
sudo cp Caddyfile.example /etc/caddy/Caddyfile

# 编辑并根据需要修改
sudo nano /etc/caddy/Caddyfile

# 重载配置
sudo systemctl reload caddy
```

## HTTP 模式示例

最简单的配置，监听 80 端口：

```caddyfile
:80 {
    reverse_proxy localhost:4173
}
```

## HTTPS 模式示例

使用域名和自动 HTTPS：

```caddyfile
example.com {
    reverse_proxy localhost:4173
    tls admin@example.com
}
```

## 防火墙配置

如果使用 UFW 防火墙：

```bash
# HTTP 模式
sudo ufw allow 80/tcp

# HTTPS 模式
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## 故障排查

### 服务启动失败

```bash
# 查看详细错误
sudo journalctl -u caddy -n 50

# 验证配置
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

### HTTPS 证书申请失败

```bash
# 检查域名解析
dig +short your-domain.com

# 检查防火墙
sudo ufw status

# 查看证书日志
sudo journalctl -u caddy | grep -i "acme\|certificate"
```

### 502 Bad Gateway

```bash
# 检查后端服务是否运行
ss -tulpn | grep :4173

# 测试后端服务
curl http://localhost:4173
```

## 卸载

```bash
sudo ./caddy.sh uninstall
```

## 更多信息

详细文档请参考: [README_CADDY.md](./README_CADDY.md)

## 技术支持

- [Caddy 官方文档](https://caddyserver.com/docs/)
- [Caddy 社区论坛](https://caddy.community/)

---

**快速帮助**: 运行 `sudo ./caddy.sh` 查看所有可用选项
