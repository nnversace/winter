# 更新说明 v2.2.1

## 📋 更新内容

本次更新修改了 Snell v5 和 sing-box 模块的默认配置。

---

## 🔄 主要变更

### 1. Snell v5 模块更新

#### 版本升级
- **旧版本**: v5.0.0
- **新版本**: v5.0.1

#### 默认配置更改

**旧配置**:
```ini
[snell-server]
# Snell Server v5 配置文件
listen = 0.0.0.0:6160
psk = <随机生成>
ipv6 = true
dns = 8.8.8.8, 1.1.1.1

# Obfs 混淆 (可选，取消注释启用)
# obfs = tls
# obfs-host = www.bing.com
```

**新配置**:
```ini
[snell-server]
listen = 0.0.0.0:53100
psk = IUmuU/NjIQhHPMdBz5WONA==
```

**变更说明**:
- ✅ 版本升级至 5.0.1
- ✅ 端口从 6160 改为 53100
- ✅ PSK 使用固定值: `IUmuU/NjIQhHPMdBz5WONA==`
- ✅ 移除交互式配置，直接使用默认值
- ✅ 简化配置文件，仅保留必要参数

---

### 2. sing-box 模块更新

#### 协议变更
- **旧协议**: VLESS + Reality
- **新协议**: Shadowsocks 2022

#### 默认配置更改

**旧配置 (VLESS+Reality)**:
```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "port": 443,
      "users": [
        {
          "uuid": "<自动生成>",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.apple.com",
            "server_port": 443
          },
          "private_key": "<自动生成>",
          "short_id": ["<自动生成>"]
        }
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ]
}
```

**新配置 (Shadowsocks 2022)**:
```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "DIRECT",
      "listen": "::",
      "listen_port": 59271,
      "method": "2022-blake3-aes-128-gcm",
      "password": "IUmuU/NjIQhHPMdBz5WONA==",
      "multiplex": {
        "enabled": true,
        "padding": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
```

**变更说明**:
- ✅ 协议从 VLESS+Reality 改为 Shadowsocks 2022
- ✅ 端口从 443 改为 59271
- ✅ 加密方式: 2022-blake3-aes-128-gcm
- ✅ 密码: `IUmuU/NjIQhHPMdBz5WONA==`
- ✅ 启用多路复用 (multiplex)
- ✅ 启用 padding
- ✅ 移除 Reality 相关配置
- ✅ 移除交互式配置，直接使用默认值

---

## 📊 配置对比

### Snell v5

| 项目 | 旧值 | 新值 |
|------|------|------|
| 版本 | 5.0.0 | **5.0.1** |
| 端口 | 6160 | **53100** |
| PSK | 随机生成 | **IUmuU/NjIQhHPMdBz5WONA==** |
| 配置方式 | 交互式 | **自动化** |

### sing-box

| 项目 | 旧值 | 新值 |
|------|------|------|
| 协议 | VLESS+Reality | **Shadowsocks 2022** |
| 端口 | 443 | **59271** |
| 加密方式 | Reality | **2022-blake3-aes-128-gcm** |
| 密码/UUID | 随机生成 | **IUmuU/NjIQhHPMdBz5WONA==** |
| 多路复用 | - | **启用** |
| 配置方式 | 交互式 | **自动化** |

---

## 🚀 使用方法

### Snell v5

```bash
# 安装
sudo ./start.sh -m snell-v5 -y

# 或直接执行
sudo bash modules/snell-v5.sh

# 查看配置
cat /etc/snell/snell-server.conf

# 查看客户端配置
cat /etc/snell/client-config.txt
```

**客户端配置示例**:
```
服务器: <你的服务器IP>
端口: 53100
PSK: IUmuU/NjIQhHPMdBz5WONA==
版本: 5
```

---

### sing-box

```bash
# 安装
sudo ./start.sh -m sing-box -y

# 或直接执行
sudo bash modules/sing-box.sh

# 查看配置
cat /etc/sing-box/config.json

# 查看客户端配置
cat /etc/sing-box/client-config.txt
```

**客户端配置示例**:
```
协议: Shadowsocks 2022
服务器: <你的服务器IP>
端口: 59271
密码: IUmuU/NjIQhHPMdBz5WONA==
加密方式: 2022-blake3-aes-128-gcm
```

---

## ✅ 验证安装

### Snell v5

```bash
# 检查服务状态
sudo systemctl status snell

# 查看监听端口
sudo ss -tlnp | grep 53100

# 查看日志
sudo journalctl -u snell -f
```

### sing-box

```bash
# 检查服务状态
sudo systemctl status sing-box

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 查看监听端口
sudo ss -tlnp | grep 59271

# 查看日志
sudo journalctl -u sing-box -f
```

---

## 🔧 管理命令

### Snell v5

```bash
# 启动/停止/重启
sudo systemctl start snell
sudo systemctl stop snell
sudo systemctl restart snell

# 修改配置后重启
sudo nano /etc/snell/snell-server.conf
sudo systemctl restart snell
```

### sing-box

```bash
# 启动/停止/重启
sudo systemctl start sing-box
sudo systemctl stop sing-box
sudo systemctl restart sing-box

# 修改配置后验证并重启
sudo nano /etc/sing-box/config.json
sudo sing-box check -c /etc/sing-box/config.json
sudo systemctl restart sing-box
```

---

## 📝 注意事项

### 安全建议

1. **端口开放**: 确保防火墙已开放相应端口
   ```bash
   # Snell
   sudo ufw allow 53100/tcp
   
   # sing-box
   sudo ufw allow 59271/tcp
   ```

2. **密码安全**: 
   - 默认密码已在代码中硬编码
   - 如需更改，请修改配置文件后重启服务

3. **定期更新**: 
   - 定期检查并更新到最新版本
   - 关注安全公告

### 兼容性

- ✅ Debian 12/13
- ✅ Ubuntu 20.04+
- ✅ 支持架构: amd64, arm64, armv7

---

## 🔄 升级指南

### 从 v2.2.0 升级

如果已安装旧版本，需要重新安装：

```bash
# 1. 停止并删除旧服务
sudo systemctl stop snell sing-box
sudo systemctl disable snell sing-box

# 2. 删除旧配置
sudo rm -rf /etc/snell /etc/sing-box

# 3. 重新安装
sudo ./start.sh -m snell-v5,sing-box -y
```

---

## 🐛 故障排除

### Snell v5

**问题**: 服务无法启动
```bash
# 检查日志
sudo journalctl -u snell -n 50

# 验证配置文件
cat /etc/snell/snell-server.conf

# 测试手动运行
sudo /usr/local/bin/snell-server -c /etc/snell/snell-server.conf
```

**问题**: 端口被占用
```bash
# 查看端口占用
sudo lsof -i :53100

# 修改端口（编辑配置文件）
sudo nano /etc/snell/snell-server.conf
sudo systemctl restart snell
```

### sing-box

**问题**: 服务无法启动
```bash
# 检查日志
sudo journalctl -u sing-box -n 50

# 验证配置
sudo sing-box check -c /etc/sing-box/config.json

# 测试手动运行
sudo /usr/local/bin/sing-box run -c /etc/sing-box/config.json
```

**问题**: 端口被占用
```bash
# 查看端口占用
sudo lsof -i :59271

# 修改端口（编辑配置文件）
sudo nano /etc/sing-box/config.json
# 修改 listen_port 值
sudo systemctl restart sing-box
```

---

## 📚 参考资料

### Snell
- [Snell 官方文档](https://manual.nssurge.com/others/snell.html)
- [Snell v5 发布说明](https://nssurge.com)

### sing-box
- [sing-box 官方文档](https://sing-box.sagernet.org)
- [Shadowsocks 2022 规范](https://github.com/Shadowsocks-NET/shadowsocks-specs)

---

## 📞 技术支持

如有问题，请参考：
- `NEW_MODULES_v2.2.md` - 模块详细说明
- `README.md` - 项目总览
- `CHANGELOG.md` - 完整的变更历史

---

**更新版本**: v2.2.1  
**更新日期**: 2024-11-20  
**状态**: ✅ 已完成并测试
