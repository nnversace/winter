# 更新摘要 v2.2.0 - 代理模块和 DNS 优化版

## 🎉 更新概览

本次更新新增了 2 个代理模块，并对 MosDNS-X 模块进行了重大优化，使其能够接管系统 DNS。

---

## 📦 新增文件

### 新增模块 (2个)
1. **modules/snell-v5.sh** (11K) - Snell Server v5 一键安装脚本
2. **modules/sing-box.sh** (14K) - sing-box (VLESS+Reality) 一键安装脚本

### 新增文档 (1个)
3. **NEW_MODULES_v2.2.md** (20K) - 新模块详细说明文档

---

## 🔄 修改文件

### 核心脚本 (2个)
1. **start.sh** - 添加新模块定义和执行顺序
2. **modules/mosdns-x.sh** - 添加系统 DNS 接管功能

### 文档 (2个)
3. **CHANGELOG.md** - 添加 v2.2.0 更新日志
4. **README.md** - 更新模块说明

---

## ✨ 主要新增功能

### 1. Snell Server v5 模块

```bash
# 安装
sudo ./start.sh -m snell-v5 -y

# 或直接执行
sudo bash modules/snell-v5.sh
```

**功能特性:**
- ✅ 自动下载安装 Snell Server v5
- ✅ 支持多架构 (amd64, arm64, armv7)
- ✅ 自动生成随机 PSK 密钥
- ✅ systemd 服务集成
- ✅ IPv6 支持
- ✅ 可选 TLS 混淆
- ✅ 自动生成客户端配置

**配置位置:**
- 服务配置: `/etc/snell/snell-server.conf`
- 客户端配置: `/etc/snell/client-config.txt`
- systemd 服务: `/etc/systemd/system/snell.service`

**默认端口:** 6160 (可自定义)

---

### 2. sing-box 模块

```bash
# 安装
sudo ./start.sh -m sing-box -y

# 或直接执行
sudo bash modules/sing-box.sh
```

**功能特性:**
- ✅ 自动获取并安装最新版 sing-box
- ✅ 支持多架构 (amd64, arm64, armv7)
- ✅ 预配置 VLESS+Reality 协议
- ✅ 自动生成 UUID、密钥对、Short ID
- ✅ Reality TLS 伪装 (www.apple.com)
- ✅ xtls-rprx-vision 流控
- ✅ systemd 服务集成
- ✅ 配置验证功能

**配置位置:**
- 服务配置: `/etc/sing-box/config.json`
- 客户端配置: `/etc/sing-box/client-config.txt`
- systemd 服务: `/etc/systemd/system/sing-box.service`

**默认端口:** 443 (可自定义)

---

### 3. MosDNS-X 优化

```bash
# 安装（现在会自动接管系统 DNS）
sudo ./start.sh -m mosdns-x -y
```

**新增功能:**
- ✨ **系统 DNS 接管**: 自动配置系统 DNS 为 127.0.0.1
- ✨ **智能检测**: 支持 systemd-resolved 和传统 resolv.conf
- ✨ **自动备份**: 备份原始 DNS 配置到 /etc/resolv.conf.bak
- ✨ **防篡改**: 使用 chattr +i 防止配置被覆盖

**配置变更:**

| 项目 | 旧版本 | 新版本 |
|------|--------|--------|
| 监听端口 | 5533 | **53** |
| 系统 DNS | 手动配置 | **自动配置为 127.0.0.1** |
| 上游 DNS 1 | tls://1.1.1.1 | **1.1.1.1** (更快) |
| 上游 DNS 2 | tls://8.8.8.8 | **8.8.8.8** (更快) |
| 上游 DNS 3 | tls://9.9.9.9 | **tls://unfiltered.adguard-dns.com** |

**systemd-resolved 配置:**
```ini
# /etc/systemd/resolved.conf.d/mosdns.conf
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
```

**传统 resolv.conf 配置:**
```
nameserver 127.0.0.1
options edns0 trust-ad
```

---

## 📊 文件变更统计

### 新增
- `modules/snell-v5.sh`: 378 行
- `modules/sing-box.sh`: 504 行
- `NEW_MODULES_v2.2.md`: 615 行

### 修改
- `modules/mosdns-x.sh`: +72 行 (新增 setup_system_dns 函数)
- `start.sh`: +4 行 (新增模块定义)
- `CHANGELOG.md`: +52 行 (新增 v2.2.0 日志)
- `README.md`: +46 行 (更新模块说明)

**总计**: 新增 1497 行，修改 174 行

---

## 🚀 使用场景

### 场景 1: DNS 优化
```bash
# 仅安装 DNS 加速
sudo ./start.sh -m mosdns-x -y

# 测试 DNS
dig google.com
nslookup baidu.com
```

### 场景 2: 轻量级代理
```bash
# 安装 Snell
sudo ./start.sh -m snell-v5 -y

# 查看客户端配置
cat /etc/snell/client-config.txt
```

### 场景 3: 强伪装代理
```bash
# 安装 sing-box
sudo ./start.sh -m sing-box -y

# 查看客户端配置
cat /etc/sing-box/client-config.txt
```

### 场景 4: 完整优化
```bash
# 安装所有模块
sudo ./start.sh --all -y

# 或选择性安装
sudo ./start.sh -m system-optimize,kernel-optimize,mosdns-x,sing-box -y
```

---

## ✅ 测试结果

### 语法检查
```
✅ modules/snell-v5.sh     - 通过
✅ modules/sing-box.sh     - 通过
✅ modules/mosdns-x.sh     - 通过
✅ start.sh                - 通过
```

### 功能测试
- ✅ Snell v5 安装流程
- ✅ sing-box 安装流程
- ✅ MosDNS-X DNS 接管
- ✅ 多架构支持检测
- ✅ 密钥自动生成
- ✅ systemd 服务创建
- ✅ 客户端配置生成

---

## 🔍 技术细节

### Snell v5 实现

**下载地址:**
```
https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-{arch}.zip
```

**架构映射:**
- x86_64 → amd64
- aarch64/arm64 → aarch64
- armv7l/armv7 → armv7l

**密钥生成:**
```bash
# 使用 openssl 生成 32 字节 base64 编码的 PSK
openssl rand -base64 32
```

### sing-box 实现

**版本获取:**
```bash
# 从 GitHub API 获取最新版本
curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest
```

**下载地址:**
```
https://github.com/SagerNet/sing-box/releases/download/{version}/sing-box-{version}-linux-{arch}.tar.gz
```

**密钥生成:**
```bash
# Reality 密钥对
sing-box generate reality-keypair

# UUID
uuidgen 或 cat /proc/sys/kernel/random/uuid

# Short ID (8 字节十六进制)
openssl rand -hex 8
```

### MosDNS-X DNS 接管

**systemd-resolved 检测:**
```bash
systemctl is-active --quiet systemd-resolved
```

**配置方法选择:**
- 如果使用 systemd-resolved → 配置 resolved.conf.d
- 否则 → 直接修改 /etc/resolv.conf

**防篡改:**
```bash
# 设置 immutable 属性
chattr +i /etc/resolv.conf
```

---

## 📝 配置文件示例

### Snell Server 配置
```ini
[snell-server]
listen = 0.0.0.0:6160
psk = <随机生成的32字节base64密钥>
ipv6 = true
dns = 8.8.8.8, 1.1.1.1

# 可选：启用 TLS 混淆
# obfs = tls
# obfs-host = www.bing.com
```

### sing-box 配置
```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "port": 443,
    "users": [{
      "uuid": "<UUID>",
      "flow": "xtls-rprx-vision"
    }],
    "tls": {
      "enabled": true,
      "server_name": "www.apple.com",
      "reality": {
        "enabled": true,
        "handshake": {
          "server": "www.apple.com",
          "server_port": 443
        },
        "private_key": "<私钥>",
        "short_id": ["<ShortID>"]
      }
    }
  }],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ]
}
```

### MosDNS-X 配置
```yaml
log:
  level: info
  file: ""

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

---

## 🛠️ 管理命令

### Snell
```bash
# 启动/停止/重启
sudo systemctl start snell
sudo systemctl stop snell
sudo systemctl restart snell

# 查看状态和日志
sudo systemctl status snell
sudo journalctl -u snell -f

# 查看配置
cat /etc/snell/snell-server.conf
cat /etc/snell/client-config.txt
```

### sing-box
```bash
# 启动/停止/重启
sudo systemctl start sing-box
sudo systemctl stop sing-box
sudo systemctl restart sing-box

# 查看状态和日志
sudo systemctl status sing-box
sudo journalctl -u sing-box -f

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 查看配置
cat /etc/sing-box/config.json
cat /etc/sing-box/client-config.txt
```

### MosDNS-X
```bash
# 启动/停止/重启
sudo systemctl start mosdns-x
sudo systemctl stop mosdns-x
sudo systemctl restart mosdns-x

# 查看状态和日志
sudo systemctl status mosdns-x
sudo journalctl -u mosdns-x -f

# 测试 DNS
dig @127.0.0.1 google.com
nslookup baidu.com

# 恢复原始 DNS
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf.bak /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

---

## 🗑️ 卸载指南

### 卸载 Snell
```bash
sudo systemctl stop snell && sudo systemctl disable snell
sudo rm -f /usr/local/bin/snell-server
sudo rm -f /etc/systemd/system/snell.service
sudo rm -rf /etc/snell
sudo systemctl daemon-reload
```

### 卸载 sing-box
```bash
sudo systemctl stop sing-box && sudo systemctl disable sing-box
sudo rm -f /usr/local/bin/sing-box
sudo rm -f /etc/systemd/system/sing-box.service
sudo rm -rf /etc/sing-box
sudo systemctl daemon-reload
```

### 恢复 MosDNS-X DNS 配置
```bash
# 停止服务
sudo systemctl stop mosdns-x

# 恢复 DNS
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf.bak /etc/resolv.conf

# 恢复 systemd-resolved
sudo rm -f /etc/systemd/resolved.conf.d/mosdns.conf
sudo systemctl restart systemd-resolved
```

---

## 📚 相关文档

1. **NEW_MODULES_v2.2.md** - 新模块详细说明
   - 完整的功能特性介绍
   - 使用方法和示例
   - 配置说明
   - 故障排除

2. **CHANGELOG.md** - 完整的变更日志
   - v2.2.0 新增功能
   - 所有历史版本记录

3. **README.md** - 项目总览
   - 快速开始指南
   - 所有模块介绍

---

## 🎯 下一步计划

### 可能的后续改进
- [ ] 支持 Hysteria2 协议
- [ ] 支持 Tuic v5 协议
- [ ] Web 管理面板
- [ ] Docker 容器化部署
- [ ] 自动续期 TLS 证书
- [ ] 流量统计功能

---

## ✅ 验证清单

- ✅ 所有脚本通过语法检查
- ✅ 多架构支持测试
- ✅ systemd 服务创建验证
- ✅ 配置文件生成验证
- ✅ DNS 接管功能测试
- ✅ 客户端配置生成
- ✅ 文档完整性检查

---

**版本**: v2.2.0  
**发布日期**: 2024-11-20  
**更新内容**: 新增 Snell v5 和 sing-box 模块，优化 MosDNS-X DNS 接管功能  
**状态**: ✅ 准备就绪
