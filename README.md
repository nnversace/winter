# Debian 系统定制部署脚本 (Debian 13 优化版)

适用于 Debian 12/13+ 系统的一键部署和优化工具集。

## 概述

这是一个模块化的系统优化和部署工具，专门针对 Debian 13 (Trixie/Sid) 进行了优化，同时向下兼容 Debian 12。

### 主要特性

- 🚀 **模块化设计**: 灵活选择需要的功能模块
- 🔧 **智能优化**: 自动检测系统配置并应用最佳实践
- 📦 **一键部署**: 简化复杂的系统配置流程
- 🔄 **自动更新**: 支持无人值守的系统更新
- 🌐 **网络优化**: TCP BBR、内核参数优化
- 💾 **内存管理**: 智能 Zram 配置

## Debian 13 优化特性

### start.sh 主脚本

- ✅ 增强的 Debian 13 版本检测 (trixie/sid)
- ✅ 命令行参数支持 (`-a`, `-m`, `-y`, `--skip-network-check`, `-h`)
- ✅ 改进的网络检测机制
- ✅ 本地模块备份支持
- ✅ 更安全的临时目录管理 (`mktemp -d`)
- ✅ 增强的错误处理和日志记录
- ✅ 非交互模式支持

### 模块优化

#### 1. system-optimize.sh - 系统优化
- 智能 Zram 配置 (根据内存和 CPU 自动调整)
- 时区自动配置 (默认 Asia/Shanghai)
- Chrony 时间同步配置
- Debian 13 特定优化

#### 2. kernel-optimize.sh - 内核优化 (v2.1.0)
- ✨ **完全重写**: 从旧式脚本升级为现代化模块
- TCP BBR 拥塞控制算法
- 系统资源限制优化 (文件句柄 6815744、进程数)
- 网络参数调优 (TCP/UDP 缓冲区、连接队列)
- IPv6 转发支持
- PAM limits 配置
- 配置验证和状态显示
- 完善的错误处理和备份机制

#### 3. auto-update-setup.sh - 自动更新
- Cron 定时任务配置
- APT 锁检测和等待机制
- 磁盘空间检查

#### 4. mosdns-x.sh - DNS 加速 (v2.2.0)
- ✨ **系统 DNS 接管**: 自动配置系统使用本地 DNS
- MosDNS-X 自动安装和配置
- 监听端口 53 (标准 DNS 端口)
- 上游 DNS: Cloudflare, Google, AdGuard DNS over TLS
- systemd-resolved 和传统 resolv.conf 兼容
- DNS 配置自动备份

#### 5. snell-v5.sh - Snell 代理 (v2.2.0 新增)
- ✨ **Snell Server v5**: 轻量级代理服务
- 自动下载和安装 (支持多架构)
- 自动生成 PSK 密钥
- 客户端配置自动生成
- IPv6 支持
- 可选 TLS 混淆

#### 6. sing-box.sh - 通用代理 (v2.2.0 新增)
- ✨ **VLESS+Reality**: 强伪装能力的代理协议
- 自动下载最新版 sing-box
- 自动生成密钥对和配置
- Reality TLS 伪装 (www.apple.com)
- xtls-rprx-vision 流控
- 配置验证功能
- 内核更新自动重启
- 进程锁防止重复运行
- 详细的日志记录

#### 4. mosdns-x.sh - DNS 加速
- 多架构支持 (amd64, arm64, armv7)
- 自动获取最新版本
- DoT (DNS over TLS) 配置
- Systemd 服务管理
- 完整的安装验证

## 快速开始

### 基本使用

```bash
# 克隆仓库
git clone https://github.com/nnversace/winter.git
cd winter

# 添加执行权限
chmod +x start.sh

# 查看帮助
sudo ./start.sh --help

# 交互式选择模块
sudo ./start.sh

# 一键安装所有模块
sudo ./start.sh --all --yes

# 仅安装特定模块
sudo ./start.sh -m system-optimize,kernel-optimize -y
```

### 高级用法

```bash
# 跳过网络检查
sudo ./start.sh --all --skip-network-check

# 自定义模块组合
sudo ./start.sh -m kernel-optimize,mosdns-x

# 查看执行日志
sudo tail -f /var/log/debian-custom-setup.log

# 查看部署摘要
cat /root/deployment_summary_custom.txt
```

## 模块详情

### 1. 系统优化模块 (system-optimize)

**功能:**
- 智能 Zram Swap 配置
- 时区设置 (Asia/Shanghai)
- Chrony 时间同步

**优化策略:**
- 根据内存大小自动调整 Zram 倍率
- 根据 CPU 性能选择压缩算法 (zstd)
- 自动设置 swappiness 参数
- 多设备 Zram 支持 (多核优化)

### 2. 内核优化模块 (kernel-optimize)

**功能:**
- 文件句柄限制提升 (1048576)
- TCP BBR 拥塞控制
- 网络缓冲区优化
- 连接队列优化

**优化参数:**
```
fs.file-max = 1048576
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
```

### 3. 自动更新模块 (auto-update-setup)

**功能:**
- Cron 定时任务配置
- 自动系统更新 (apt dist-upgrade)
- 内核更新自动重启
- 软件包清理

**默认计划:**
- 每周日凌晨 2:00 执行更新
- 可自定义时间表

### 4. MosDNS-X 模块 (mosdns-x)

**功能:**
- DNS over TLS (DoT) 支持
- 多上游 DNS 配置
- 本地 DNS 缓存
- 自动架构检测

**默认配置:**
- 监听地址: 127.0.0.1:5533
- 上游服务器: Cloudflare, Google, Quad9
- 使用 TLS 加密

## 系统要求

- **操作系统**: Debian 12+, Debian 13 (Trixie/Sid)
- **权限**: Root 或 sudo
- **网络**: 需要互联网连接下载模块
- **依赖**: curl, wget, git, jq, rsync, sudo (自动安装)

## 文件结构

```
winter/
├── start.sh                    # 主脚本 (Debian 13 优化版)
├── modules/                    # 模块目录
│   ├── system-optimize.sh      # 系统优化
│   ├── kernel-optimize.sh      # 内核优化 (重写)
│   ├── auto-update-setup.sh    # 自动更新
│   └── mosdns-x.sh            # DNS 加速
├── Proxy/                      # 代理安装脚本
│   ├── realm.sh               # Realm 代理
│   └── snell.sh               # Snell 代理
├── mj.sh                      # Midjourney 部署
├── .gitignore                 # Git 忽略文件
└── README.md                  # 本文档
```

## 日志和输出

- **主日志**: `/var/log/debian-custom-setup.log`
- **更新日志**: `/var/log/system-auto-update.log`
- **部署摘要**: `/root/deployment_summary_custom.txt`

## 常见问题

### 1. 如何验证 BBR 已启用？

```bash
sysctl net.ipv4.tcp_congestion_control
# 输出: net.ipv4.tcp_congestion_control = bbr
```

### 2. 如何检查 Zram 状态？

```bash
swapon --show
# 应该看到 zram 设备
```

### 3. 如何修改自动更新时间？

```bash
crontab -e
# 编辑 cron 任务
```

### 4. 如何测试 MosDNS-X？

```bash
dig @127.0.0.1 -p 5533 google.com
```

## 安全建议

1. **备份**: 脚本会自动备份关键配置文件
2. **测试**: 建议先在测试环境运行
3. **日志**: 定期检查日志文件
4. **更新**: 保持脚本和系统更新

## 卸载

### 移除自动更新

```bash
crontab -l | grep -v 'system-auto-update' | crontab -
rm -f /usr/local/sbin/system-auto-update.sh
```

### 移除 MosDNS-X

```bash
systemctl stop mosdns-x
systemctl disable mosdns-x
rm -f /usr/local/bin/mosdns-x
rm -f /etc/systemd/system/mosdns-x.service
rm -rf /etc/mosdns-x
```

### 恢复内核参数

```bash
rm -f /etc/sysctl.d/99-kernel-optimize.conf
sysctl --system
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 版本历史

### v2.0.0 (Debian 13 优化版)
- ✨ 完全重写 kernel-optimize.sh
- ✨ 增强 start.sh 命令行支持
- ✨ 优化所有模块的错误处理
- ✨ 添加 Debian 13 特定优化
- ✨ 改进日志和状态显示
- 🐛 修复网络检测问题
- 🐛 修复 APT 锁冲突

### v1.0.0
- 初始版本

## 许可证

本项目采用 MIT 许可证。

## 作者

- 原作者: LucaLin233
- 优化: nnversace (Debian 13 优化版)

## 致谢

感谢所有贡献者和使用者的支持！

---

**注意**: 本脚本会修改系统配置，建议在使用前备份重要数据。
