# kernel-optimize.sh 重构说明 (Debian 13 专属版)

## 概述

本次重构根据用户提供的参数，完全重构了 `kernel-optimize.sh` 脚本，精选适合 Debian 13 的内核参数，并优化了脚本结构。

## 重构目标

1. **参数精简**: 仅保留对 Debian 13 最有效的内核参数
2. **配置优化**: 使用更适合 Debian 13 的参数值
3. **IPv6 支持**: 新增 IPv6 转发配置
4. **文档完善**: 详细注释每个参数的作用

## 采用的参数

### 文件系统优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `fs.file-max` | 6815744 | 系统级别打开文件描述符的最大数量 (从 1048576 提升) |

**变更原因**: 更大的文件句柄限制适合高并发场景，特别是运行大量容器或服务的系统。

### 网络核心优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.core.rmem_max` | 16777216 | 接收缓冲区最大值 16MB (从 33554432 调整) |
| `net.core.wmem_max` | 16777216 | 发送缓冲区最大值 16MB (从 33554432 调整) |
| `net.core.default_qdisc` | fq | Fair Queue 队列调度算法 (与 BBR 配合) |

**变更原因**: 16MB 的缓冲区对大多数场景已经足够，同时避免过度占用内存。

### TCP 缓冲区优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv4.tcp_rmem` | 4096 87380 16777216 | TCP 接收缓冲区: 最小 4KB, 默认 85KB, 最大 16MB |
| `net.ipv4.tcp_wmem` | 4096 65536 16777216 | TCP 发送缓冲区: 最小 4KB, 默认 64KB, 最大 16MB |

**变更原因**: 调整后的值更适合现代网络环境，平衡了性能和内存使用。

### UDP 缓冲区优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv4.udp_rmem_min` | 8192 | UDP 接收缓冲区最小值 8KB (从 16384 调整) |
| `net.ipv4.udp_wmem_min` | 8192 | UDP 发送缓冲区最小值 8KB (从 16384 调整) |

**变更原因**: 8KB 对大多数 UDP 应用已经足够，减少内存占用。

### TCP 性能优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv4.tcp_no_metrics_save` | 1 | 禁用 TCP 连接指标缓存 |
| `net.ipv4.tcp_ecn` | 0 | 禁用显式拥塞通知 (ECN) |
| `net.ipv4.tcp_frto` | 0 | 禁用快速重传恢复 (F-RTO) |
| `net.ipv4.tcp_mtu_probing` | 0 | 禁用 TCP MTU 探测 |
| `net.ipv4.tcp_rfc1337` | 0 | 禁用 RFC1337 TIME-WAIT 防护 |
| `net.ipv4.tcp_sack` | 1 | 启用选择性确认 (SACK) |
| `net.ipv4.tcp_fack` | 1 | 启用转发确认 (FACK) |
| `net.ipv4.tcp_window_scaling` | 1 | 启用 TCP 窗口缩放 |
| `net.ipv4.tcp_adv_win_scale` | 1 | TCP 窗口缩放因子 |
| `net.ipv4.tcp_moderate_rcvbuf` | 1 | 启用接收缓冲区自动调整 |

**变更原因**: 这些参数是经过实践验证的 TCP 性能优化配置。

### BBR 拥塞控制

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv4.tcp_congestion_control` | bbr | 使用 BBR 拥塞控制算法 |

**变更原因**: BBR 是现代网络环境下最优的拥塞控制算法。

### IPv4 转发和路由

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv4.ip_forward` | 1 | 启用 IPv4 包转发 |
| `net.ipv4.conf.all.route_localnet` | 1 | 允许本地路由 |
| `net.ipv4.conf.all.forwarding` | 1 | 启用所有接口的 IPv4 转发 |
| `net.ipv4.conf.default.forwarding` | 1 | 启用默认接口的 IPv4 转发 |

### IPv6 转发 (新增)

| 参数 | 值 | 说明 |
|------|-----|------|
| `net.ipv6.conf.all.forwarding` | 1 | 启用所有接口的 IPv6 转发 |
| `net.ipv6.conf.default.forwarding` | 1 | 启用默认接口的 IPv6 转发 |

**新增原因**: Debian 13 对 IPv6 支持更完善，启用 IPv6 转发以支持双栈网络。

## 移除的参数

以下参数在 Debian 13 环境下不是必需的，已被移除以简化配置：

- `fs.inotify.max_user_instances`
- `net.core.somaxconn`
- `net.core.netdev_max_backlog`
- `net.ipv4.tcp_mem`
- `net.ipv4.udp_mem`
- `net.ipv4.tcp_syncookies`
- `net.ipv4.tcp_fin_timeout`
- `net.ipv4.tcp_tw_reuse`
- `net.ipv4.ip_local_port_range`
- `net.ipv4.tcp_max_syn_backlog`
- `net.ipv4.tcp_max_tw_buckets`
- `net.ipv4.route.gc_timeout`
- `net.ipv4.tcp_syn_retries`
- `net.ipv4.tcp_synack_retries`
- `net.ipv4.tcp_timestamps`
- `net.ipv4.tcp_max_orphans`
- `net.ipv4.tcp_keepalive_time`
- `net.ipv4.tcp_notsent_lowat`

**移除原因**: 这些参数要么 Debian 13 默认值已经足够好，要么在现代内核中已不再需要手动调整。

## 脚本结构优化

### 新增功能

1. **Debian 版本检测**
   ```bash
   detect_debian_version()
   ```
   - 自动检测 Debian 13 (Trixie/Sid)
   - 提供版本特定的提示信息

2. **清理旧配置**
   ```bash
   cleanup_old_sysctl()
   ```
   - 自动清理 `/etc/sysctl.conf` 中的冲突参数
   - 避免配置冲突

3. **增强的验证输出**
   ```bash
   verify_configuration()
   ```
   - 分类显示配置状态 (文件系统、TCP BBR、网络缓冲区、TCP 优化、IP 转发)
   - 更清晰的输出格式

4. **优化建议**
   ```bash
   show_recommendations()
   ```
   - 提供详细的后续操作建议
   - 包含验证命令和回滚方法

### 保留的优秀特性

- ✅ 完善的错误处理 (`set -euo pipefail`)
- ✅ 文件自动备份 (`.bak` 后缀)
- ✅ 彩色日志输出
- ✅ PAM limits 集成
- ✅ BBR 模块自动加载
- ✅ 配置验证和状态显示

## 使用方法

### 基本使用

```bash
# 执行优化
sudo bash modules/kernel-optimize.sh

# 查看脚本帮助
sudo bash modules/kernel-optimize.sh --help
```

### 验证配置

```bash
# 验证 BBR 是否启用
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr

# 检查文件句柄限制
cat /proc/sys/fs/file-max
ulimit -n

# 检查 IPv6 转发
cat /proc/sys/net/ipv6/conf/all/forwarding
```

### 回滚配置

```bash
# 移除优化配置
sudo rm /etc/sysctl.d/99-kernel-optimize.conf

# 恢复备份
sudo cp /etc/security/limits.conf.bak /etc/security/limits.conf

# 重新加载配置
sudo sysctl --system
```

## 性能影响

### 预期改进

1. **网络性能**: BBR 算法可提升 10-20% 的吞吐量
2. **文件操作**: 更大的文件句柄限制支持更多并发连接
3. **内存效率**: 优化的缓冲区大小减少内存浪费
4. **IPv6 支持**: 完整的双栈转发能力

### 适用场景

- ✅ 代理服务器 (Nginx, HAProxy)
- ✅ 容器化环境 (Docker, Kubernetes)
- ✅ 高并发 Web 服务
- ✅ VPN 和隧道服务
- ✅ IPv6 网络环境

## 兼容性

- ✅ Debian 13 (Trixie/Sid) - 推荐
- ✅ Debian 12 (Bookworm) - 兼容
- ✅ Ubuntu 22.04+ - 兼容
- ⚠️ 旧版本系统 - 部分参数可能不支持

## 安全考虑

1. **配置备份**: 所有修改前自动备份
2. **错误处理**: 严格的错误检查和日志
3. **参数验证**: 执行后验证配置是否生效
4. **回滚机制**: 提供完整的回滚方案

## 测试结果

### 语法检查
```
✅ bash -n modules/kernel-optimize.sh
语法检查通过
```

### 功能测试
- ✅ Root 权限检查
- ✅ Debian 版本检测
- ✅ 文件备份机制
- ✅ sysctl 配置应用
- ✅ BBR 模块加载
- ✅ 配置验证输出

## 维护建议

1. **定期更新**: 随 Debian 13 内核更新可能需要调整参数
2. **监控性能**: 使用 `ss`, `netstat` 监控网络性能
3. **日志检查**: 定期查看 dmesg 和系统日志
4. **基准测试**: 优化前后进行性能对比

## 参考资料

- [Linux Kernel Documentation - sysctl](https://www.kernel.org/doc/Documentation/sysctl/)
- [TCP BBR Congestion Control](https://github.com/google/bbr)
- [Debian Wiki - Network Configuration](https://wiki.debian.org/NetworkConfiguration)
- [IPv6 Configuration](https://wiki.debian.org/DebianIPv6)

## 更新日志

### v2.1.0 - Debian 13 专属优化版
- ✨ 根据提供参数完全重构
- ✨ 新增 IPv6 转发支持
- ✨ 优化文件句柄限制 (6815744)
- ✨ 调整网络缓冲区大小 (16MB)
- ✨ 精简不必要的参数
- ✨ 新增 Debian 版本检测
- ✨ 增强配置验证和建议
- 🔧 改进错误处理和日志
- 🔧 优化脚本结构

---

**重构完成**: 2024-11-20  
**版本**: v2.1.0  
**适用系统**: Debian 13 (Trixie/Sid), Debian 12+
