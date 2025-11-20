# 新增模块说明 v2.2.0

## 📋 新增模块概览

本次更新新增了 3 个重要模块，并优化了现有的 mosdns-x 模块。

---

## 1. Snell Server v5 模块 (snell-v5)

### 功能特性

✨ **主要功能**
- 自动下载并安装 Snell Server v5
- 支持多架构 (amd64, arm64, armv7)
- 自动生成 PSK 密钥
- systemd 服务管理
- 自动获取服务器 IP
- 生成客户端配置

🔧 **配置特点**
- 支持 IPv6
- 可选 TLS 混淆
- 自定义监听端口
- 自动生成 URI 格式配置

### 使用方法

```bash
# 通过主脚本安装
sudo ./start.sh -m snell-v5 -y

# 直接执行
sudo bash modules/snell-v5.sh

# 查看服务状态
sudo systemctl status snell

# 查看客户端配置
cat /etc/snell/client-config.txt
```

### 配置文件位置

- **服务配置**: `/etc/snell/snell-server.conf`
- **客户端信息**: `/etc/snell/client-config.txt`
- **二进制文件**: `/usr/local/bin/snell-server`
- **systemd 服务**: `/etc/systemd/system/snell.service`

### 默认配置

```ini
[snell-server]
listen = 0.0.0.0:6160
psk = <随机生成>
ipv6 = true
dns = 8.8.8.8, 1.1.1.1
```

### 客户端配置示例

**Surge/Shadowrocket:**
```
Snell = snell, SERVER_IP, PORT, psk=YOUR_PSK, version=5
```

**URI 格式:**
```
snell://SERVER_IP:PORT?psk=YOUR_PSK&version=5
```

---

## 2. sing-box 模块 (sing-box)

### 功能特性

✨ **主要功能**
- 自动下载最新版 sing-box
- 支持多架构 (amd64, arm64, armv7)
- 预配置 VLESS+Reality
- 自动生成密钥对
- systemd 服务管理
- 配置验证功能

🔧 **配置特点**
- VLESS 协议
- Reality TLS 伪装
- xtls-rprx-vision 流控
- 使用 www.apple.com 作为 SNI
- 自动生成 UUID 和 Short ID

### 使用方法

```bash
# 通过主脚本安装
sudo ./start.sh -m sing-box -y

# 直接执行
sudo bash modules/sing-box.sh

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 查看服务状态
sudo systemctl status sing-box

# 查看客户端配置
cat /etc/sing-box/client-config.txt
```

### 配置文件位置

- **服务配置**: `/etc/sing-box/config.json`
- **客户端信息**: `/etc/sing-box/client-config.txt`
- **二进制文件**: `/usr/local/bin/sing-box`
- **systemd 服务**: `/etc/systemd/system/sing-box.service`

### Reality 配置说明

sing-box 使用 Reality 协议，提供更好的伪装能力：

- **伪装网站**: www.apple.com
- **传输协议**: TCP
- **流控**: xtls-rprx-vision
- **加密**: 自动生成的公私钥对

### 客户端配置示例

```
协议:         VLESS
地址:         SERVER_IP
端口:         443
UUID:         <自动生成>
Flow:         xtls-rprx-vision
传输协议:     TCP
TLS:          Reality
SNI:          www.apple.com
PublicKey:    <自动生成>
ShortID:      <自动生成>
```

---

## 3. MosDNS-X 模块优化 (mosdns-x)

### 🔄 主要变更

#### 1. 系统 DNS 接管

✨ **新增功能**
- 自动修改系统 DNS 为 127.0.0.1
- 支持 systemd-resolved
- 支持传统 resolv.conf
- 自动备份原始配置

🔧 **实现方式**

**systemd-resolved 系统:**
```ini
# /etc/systemd/resolved.conf.d/mosdns.conf
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
```

**传统系统:**
```
# /etc/resolv.conf
nameserver 127.0.0.1
options edns0 trust-ad
```

#### 2. 配置变更

**旧配置 (v2.1.0):**
```yaml
plugins:
  - tag: forward_dot_servers
    type: fast_forward
    args:
      upstream:
        - addr: tls://1.1.1.1
        - addr: tls://8.8.8.8
        - addr: tls://9.9.9.9

servers:
  - exec: forward_dot_servers
    listeners:
      - protocol: udp
        addr: 127.0.0.1:5533
      - protocol: tcp
        addr: 127.0.0.1:5533
```

**新配置 (v2.2.0):**
```yaml
plugins:
  - tag: forward_dot_servers
    type: fast_forward
    args:
      upstream:
        - addr: 1.1.1.1
        - addr: 8.8.8.8
        - addr: tls://unfiltered.adguard-dns.com

servers:
  - exec: forward_dot_servers
    listeners:
      - protocol: udp
        addr: 127.0.0.1:53
      - protocol: tcp
        addr: 127.0.0.1:53
```

**主要变更:**
- ✅ 监听端口: 5533 → **53** (标准 DNS 端口)
- ✅ 上游服务器调整:
  - 1.1.1.1 (Cloudflare, 普通 DNS)
  - 8.8.8.8 (Google, 普通 DNS)
  - tls://unfiltered.adguard-dns.com (AdGuard DNS over TLS)
- ✅ 系统 DNS 自动配置为 127.0.0.1

### 使用方法

```bash
# 安装并接管系统 DNS
sudo ./start.sh -m mosdns-x -y

# 测试 DNS 解析
dig google.com
nslookup baidu.com

# 查看当前 DNS 配置
cat /etc/resolv.conf

# 恢复原始 DNS
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf.bak /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

### 配置文件位置

- **MosDNS 配置**: `/etc/mosdns-x/config.yaml`
- **DNS 配置备份**: `/etc/resolv.conf.bak`
- **systemd-resolved 配置**: `/etc/systemd/resolved.conf.d/mosdns.conf`

---

## 📊 模块对比

| 模块 | 用途 | 监听端口 | 协议 | 适用场景 |
|------|------|----------|------|----------|
| **mosdns-x** | DNS 加速 | 53 | DNS | 系统 DNS 加速，广告过滤 |
| **snell-v5** | 代理服务 | 6160 (自定义) | Snell v5 | 轻量级代理，Surge 客户端 |
| **sing-box** | 代理服务 | 443 (自定义) | VLESS+Reality | 强伪装能力，通用客户端 |

---

## 🚀 快速开始

### 方案 1: 全套安装

```bash
# 安装所有模块（包括系统优化）
sudo ./start.sh --all -y
```

### 方案 2: 选择性安装

```bash
# 仅安装代理相关模块
sudo ./start.sh -m mosdns-x,snell-v5,sing-box -y

# 仅安装 DNS 优化
sudo ./start.sh -m mosdns-x -y

# 仅安装代理服务
sudo ./start.sh -m snell-v5 -y
# 或
sudo ./start.sh -m sing-box -y
```

### 方案 3: 单独安装

```bash
# 单独安装 Snell
sudo bash modules/snell-v5.sh

# 单独安装 sing-box
sudo bash modules/sing-box.sh

# 单独安装 MosDNS-X
sudo bash modules/mosdns-x.sh
```

---

## 🔍 验证安装

### MosDNS-X 验证

```bash
# 检查服务状态
sudo systemctl status mosdns-x

# 测试 DNS 解析
dig @127.0.0.1 google.com

# 测试系统 DNS
nslookup baidu.com

# 查看日志
sudo journalctl -u mosdns-x -f
```

### Snell v5 验证

```bash
# 检查服务状态
sudo systemctl status snell

# 查看监听端口
sudo ss -tlnp | grep snell

# 查看客户端配置
cat /etc/snell/client-config.txt

# 查看日志
sudo journalctl -u snell -f
```

### sing-box 验证

```bash
# 检查服务状态
sudo systemctl status sing-box

# 验证配置文件
sudo sing-box check -c /etc/sing-box/config.json

# 查看监听端口
sudo ss -tlnp | grep sing-box

# 查看客户端配置
cat /etc/sing-box/client-config.txt

# 查看日志
sudo journalctl -u sing-box -f
```

---

## ⚙️ 配置说明

### Snell v5 高级配置

编辑 `/etc/snell/snell-server.conf`:

```ini
[snell-server]
listen = 0.0.0.0:6160
psk = YOUR_PSK
ipv6 = true
dns = 8.8.8.8, 1.1.1.1

# 启用 TLS 混淆
obfs = tls
obfs-host = www.bing.com
```

重启服务：
```bash
sudo systemctl restart snell
```

### sing-box 高级配置

编辑 `/etc/sing-box/config.json` 可以：

- 修改监听端口
- 更改伪装网站 (server_name)
- 添加路由规则
- 配置多用户

重启服务：
```bash
sudo systemctl restart sing-box
```

### MosDNS-X 高级配置

编辑 `/etc/mosdns-x/config.yaml`:

```yaml
plugins:
  - tag: forward_dot_servers
    type: fast_forward
    args:
      upstream:
        # 添加更多上游服务器
        - addr: 1.1.1.1
        - addr: 8.8.8.8
        - addr: tls://unfiltered.adguard-dns.com
        - addr: tls://dns.google
```

重启服务：
```bash
sudo systemctl restart mosdns-x
```

---

## 🔧 故障排除

### MosDNS-X 端口冲突

如果端口 53 被占用：

```bash
# 查看占用端口的进程
sudo lsof -i :53

# 停止 systemd-resolved (如果冲突)
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

### Snell 连接失败

```bash
# 检查防火墙
sudo ufw allow 6160/tcp

# 或使用 iptables
sudo iptables -A INPUT -p tcp --dport 6160 -j ACCEPT
```

### sing-box 启动失败

```bash
# 验证配置文件
sudo sing-box check -c /etc/sing-box/config.json

# 查看详细日志
sudo journalctl -u sing-box -n 100
```

---

## 🗑️ 卸载指南

### 卸载 Snell v5

```bash
sudo systemctl stop snell
sudo systemctl disable snell
sudo rm -f /usr/local/bin/snell-server
sudo rm -f /etc/systemd/system/snell.service
sudo rm -rf /etc/snell
sudo systemctl daemon-reload
```

### 卸载 sing-box

```bash
sudo systemctl stop sing-box
sudo systemctl disable sing-box
sudo rm -f /usr/local/bin/sing-box
sudo rm -f /etc/systemd/system/sing-box.service
sudo rm -rf /etc/sing-box
sudo systemctl daemon-reload
```

### 恢复 MosDNS-X 修改

```bash
# 停止服务
sudo systemctl stop mosdns-x

# 恢复 DNS 配置
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf.bak /etc/resolv.conf

# 如果使用 systemd-resolved
sudo rm -f /etc/systemd/resolved.conf.d/mosdns.conf
sudo systemctl restart systemd-resolved

# 完全卸载
sudo systemctl disable mosdns-x
sudo rm -f /usr/local/bin/mosdns-x
sudo rm -f /etc/systemd/system/mosdns-x.service
sudo rm -rf /etc/mosdns-x
sudo systemctl daemon-reload
```

---

## 📝 更新日志

### v2.2.0 - 新增代理模块和 DNS 优化

**新增:**
- ✨ Snell Server v5 一键安装模块
- ✨ sing-box (VLESS+Reality) 一键安装模块
- ✨ MosDNS-X 系统 DNS 接管功能

**变更:**
- 🔧 MosDNS-X 监听端口: 5533 → 53
- 🔧 MosDNS-X 上游服务器配置优化
- 🔧 自动配置系统 DNS 为 127.0.0.1

**改进:**
- 📝 完善的客户端配置生成
- 📝 详细的安装和卸载指南
- 📝 多架构支持 (amd64, arm64, armv7)

---

## 🎯 最佳实践

### 推荐配置组合

**场景 1: 桌面/开发环境**
```bash
sudo ./start.sh -m system-optimize,mosdns-x -y
```

**场景 2: 轻量级代理服务器**
```bash
sudo ./start.sh -m system-optimize,kernel-optimize,snell-v5 -y
```

**场景 3: 全功能代理服务器**
```bash
sudo ./start.sh -m system-optimize,kernel-optimize,mosdns-x,sing-box -y
```

**场景 4: 完整优化 + 代理**
```bash
sudo ./start.sh --all -y
```

### 安全建议

1. **修改默认端口**: 避免使用常见端口
2. **定期更新**: 保持软件最新版本
3. **防火墙配置**: 仅开放必要端口
4. **日志监控**: 定期检查服务日志
5. **备份配置**: 定期备份重要配置文件

---

**版本**: v2.2.0  
**发布日期**: 2024-11-20  
**维护者**: nnversace
