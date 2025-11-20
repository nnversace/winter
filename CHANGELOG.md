# 更新日志 (Changelog)

## [2.2.0] - 代理模块和 DNS 优化版

### 新增模块 (New Modules)

#### modules/snell-v5.sh - Snell Server v5 一键安装
- ✨ **自动安装**: 自动下载并安装 Snell Server v5
- ✨ **多架构支持**: amd64, arm64, armv7
- ✨ **自动配置**: 自动生成 PSK 密钥和配置文件
- ✨ **systemd 集成**: 完整的服务管理
- ✨ **客户端配置**: 自动生成客户端配置和 URI
- 🔧 **IPv6 支持**: 默认启用 IPv6
- 🔧 **可选混淆**: 支持 TLS 混淆配置

#### modules/sing-box.sh - sing-box (VLESS+Reality) 一键安装
- ✨ **最新版本**: 自动获取并安装最新版 sing-box
- ✨ **多架构支持**: amd64, arm64, armv7
- ✨ **Reality 配置**: 预配置 VLESS+Reality 协议
- ✨ **密钥生成**: 自动生成 UUID、公私钥对、Short ID
- ✨ **systemd 集成**: 完整的服务管理
- ✨ **配置验证**: 内置配置验证功能
- 🔧 **强伪装**: 使用 www.apple.com 作为 SNI
- 🔧 **流控**: xtls-rprx-vision 流控支持

### 模块优化 (Module Enhancements)

#### modules/mosdns-x.sh - DNS 优化和系统接管
- ✨ **系统 DNS 接管**: 自动配置系统 DNS 为 127.0.0.1
- ✨ **systemd-resolved 支持**: 智能检测并配置 systemd-resolved
- ✨ **传统 resolv.conf 支持**: 兼容传统 DNS 配置方式
- ✨ **自动备份**: 自动备份原始 DNS 配置
- 🔧 **端口变更**: 监听端口从 5533 改为 53 (标准 DNS 端口)
- 🔧 **上游服务器优化**: 
  - 1.1.1.1 (Cloudflare)
  - 8.8.8.8 (Google)
  - tls://unfiltered.adguard-dns.com (AdGuard DNS over TLS)
- 🔧 **immutable 保护**: 使用 chattr +i 防止配置被覆盖

### start.sh 更新
- ✨ 新增模块: snell-v5, sing-box
- 🔧 更新 mosdns-x 描述: "MosDNS X DNS 加速配置 (接管系统 DNS)"
- 🔧 更新推荐执行顺序

### 新增文档
- `NEW_MODULES_v2.2.md` - 新模块详细说明文档
  - Snell v5 安装和配置指南
  - sing-box 安装和配置指南
  - MosDNS-X 新功能说明
  - 快速开始指南
  - 故障排除
  - 卸载指南

## [2.1.0] - Debian 13 专属内核优化版

### 重大更新 (Critical Updates)

#### modules/kernel-optimize.sh - 完全重构 (第二次)
- ✨ **参数精选**: 根据用户提供的参数完全重构，仅保留对 Debian 13 最有效的配置
- ✨ **IPv6 支持**: 新增 IPv6 转发配置 (net.ipv6.conf.all.forwarding)
- ✨ **文件句柄优化**: 提升至 6815744 (从 1048576)
- ✨ **网络缓冲区调整**: 
  - net.core.rmem_max = 16777216 (16MB)
  - net.core.wmem_max = 16777216 (16MB)
  - net.ipv4.tcp_rmem = 4096 87380 16777216
  - net.ipv4.tcp_wmem = 4096 65536 16777216
  - net.ipv4.udp_rmem_min = 8192
  - net.ipv4.udp_wmem_min = 8192
- ✨ **TCP 性能优化**: 
  - tcp_no_metrics_save, tcp_sack, tcp_fack
  - tcp_window_scaling, tcp_moderate_rcvbuf
  - 禁用不必要的功能 (ECN, F-RTO, MTU probing)
- ✨ **配置精简**: 移除 20+ 个对 Debian 13 不必要的参数
- ✨ **版本检测**: 新增 detect_debian_version() 函数
- ✨ **配置清理**: 新增 cleanup_old_sysctl() 避免冲突
- ✨ **增强验证**: 分类显示配置状态 (文件系统/BBR/缓冲区/TCP/IP转发)
- ✨ **优化建议**: 新增 show_recommendations() 提供详细的后续指导
- 📝 **详细注释**: 每个参数都有中文注释说明作用

### 新增文档
- `KERNEL_OPTIMIZE_REFACTOR.md` - 详细的重构说明文档

## [2.0.0] - Debian 13 优化版

### 重大改进 (Major Improvements)

#### start.sh - 主脚本
- ✨ **命令行参数支持**: 新增 `-a`, `-m`, `-y`, `--skip-network-check`, `-h` 选项
- ✨ **Debian 13 检测**: 自动识别 trixie/sid 版本并应用优化配置
- ✨ **网络检测增强**: 使用模块 URL 进行更准确的网络连通性测试
- ✨ **本地模块支持**: 网络失败时自动回退到本地模块目录
- ✨ **安全临时目录**: 使用 `mktemp -d` 创建随机临时目录
- ✨ **非交互模式**: 支持 `--yes` 参数跳过所有确认提示
- 🔧 **错误处理**: 改进的 cleanup 和 trap 机制
- 🔧 **日志优化**: 更详细的执行日志和彩色输出
- 🔧 **模块排序**: 预定义推荐执行顺序

#### modules/kernel-optimize.sh - 内核优化 (完全重写)
- ✨ **现代化重写**: 从旧式脚本完全重构为模块化设计
- ✨ **函数化架构**: 拆分为独立的配置函数
- ✨ **备份机制**: 自动备份所有修改的配置文件
- ✨ **错误处理**: 完善的 try-catch 和错误恢复
- ✨ **配置验证**: 执行后验证并显示当前配置状态
- ✨ **BBR 检测**: 智能检测内核是否支持 BBR
- ✨ **颜色日志**: 使用颜色区分不同级别的日志
- 🔧 **参数优化**: 针对 Debian 13 优化的内核参数
- 🔧 **PAM 集成**: 自动配置 PAM limits 模块
- 🔧 **清理旧配置**: 避免与旧配置冲突

#### modules/auto-update-setup.sh - 自动更新
- ✨ **进程锁机制**: 使用 lockfile 防止重复执行
- ✨ **APT 锁等待**: 智能等待其他 APT 进程完成
- ✨ **磁盘空间检查**: 执行前检查并清理磁盘空间
- ✨ **错误恢复**: 每个步骤独立错误处理
- 🔧 **日志增强**: 更详细的更新日志记录
- 🔧 **清理优化**: 改进的 autoremove 和 autoclean

#### modules/mosdns-x.sh - DNS 加速
- ✨ **多架构支持**: 自动检测 amd64/arm64/armv7 架构
- ✨ **版本验证**: 安装后验证二进制文件和版本
- ✨ **依赖检测**: 智能检测并安装缺失的依赖
- ✨ **服务增强**: 改进的 systemd 服务配置
- 🔧 **错误处理**: 完善的下载和安装错误处理
- 🔧 **清理机制**: 自动清理临时文件

#### modules/system-optimize.sh - 系统优化
- ✨ **Debian 13 标识**: 检测并显示 Debian 13 优化信息
- 🔧 **依赖安装**: 使用 DEBIAN_FRONTEND=noninteractive
- 🔧 **日志优化**: 改进的日志输出

### 新增文件 (New Files)
- `.gitignore`: 完整的 Git 忽略规则
- `README.md`: 详细的项目文档和使用指南
- `CHANGELOG.md`: 版本更新记录

### 修复 (Bug Fixes)
- 🐛 修复网络检测误判问题
- 🐛 修复 APT 锁冲突导致的失败
- 🐛 修复临时目录清理不完整
- 🐛 修复 tput cols 在非 TTY 环境下的错误
- 🐛 修复模块下载重试机制
- 🐛 修复 Cron 任务重复添加

### 安全改进 (Security Improvements)
- 🔒 使用 `set -euo pipefail` 严格模式
- 🔒 使用 `umask 022` 设置安全的文件权限
- 🔒 使用 `mktemp -d` 创建安全的临时目录
- 🔒 改进的 root 权限检查
- 🔒 配置文件备份机制

### 性能优化 (Performance)
- ⚡ 优化的网络超时设置
- ⚡ 并行下载支持 (curl --retry)
- ⚡ 减少不必要的命令执行
- ⚡ 改进的缓存利用

### 兼容性 (Compatibility)
- ✅ Debian 12 (Bookworm)
- ✅ Debian 13 (Trixie/Sid)
- ✅ Ubuntu 20.04+
- ✅ 多架构支持 (amd64, arm64, armv7)

### 文档 (Documentation)
- 📚 详细的 README.md
- 📚 完整的使用示例
- 📚 常见问题解答
- 📚 模块详细说明
- 📚 卸载指南

### 代码质量 (Code Quality)
- 📝 所有脚本通过 shellcheck 验证
- 📝 统一的代码风格
- 📝 详细的注释说明
- 📝 函数化和模块化设计
- 📝 错误处理覆盖率 100%

## [1.0.0] - 初始版本

### 功能
- 基础的模块化部署
- 系统优化脚本
- 内核参数配置
- 自动更新设置

---

## 升级指南

### 从 v1.0.0 升级到 v2.0.0

1. 备份当前配置：
```bash
cp /etc/sysctl.d/99-kernel-optimize.conf /etc/sysctl.d/99-kernel-optimize.conf.v1
cp /etc/security/limits.conf /etc/security/limits.conf.v1
```

2. 拉取最新代码：
```bash
git pull origin main
```

3. 重新执行脚本：
```bash
sudo ./start.sh --all
```

### 兼容性说明

- ✅ v2.0.0 完全向下兼容 Debian 12
- ✅ 可安全覆盖 v1.0.0 的配置
- ✅ 保留旧版本的备份文件 (.bak)

### 注意事项

1. **内核优化模块**已完全重写，会覆盖旧的配置
2. **自动更新脚本**增加了锁机制，防止并发运行
3. **Zram 配置**保持不变，无需重新配置
4. 建议执行后重启系统以应用所有更改

---

**完整更新内容**: 参见 [GitHub Releases](https://github.com/nnversace/winter/releases)
