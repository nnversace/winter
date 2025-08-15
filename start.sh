#!/bin/bash
# -----------------------------------------------------------------------------
# 适用系统: Debian 12+
# 功能: 模块化部署（本地 Docker 启动 Snell / Sing-box、网络优化、SSH 加固等）
# 版本: 2.4.0 (Local-Docker-Start)
# -----------------------------------------------------------------------------

set -Eeuo pipefail
umask 022

# --- 全局配置 ---
SCRIPT_VERSION="2.4.0"
STATUS_FILE="/var/lib/system-deploy-status.json"
STATUS_SCHEMA_VERSION=1
TEMP_DIR="/tmp/debian_setup_modules"
RERUN_MODE=false
INTERACTIVE_MODE=true

# 数组初始化（避免 set -u 未绑定错误）
declare -A MODULES_TO_RUN=()
declare -a EXECUTED_MODULES=()
declare -a FAILED_MODULES=()

# APT 非交互默认
export DEBIAN_FRONTEND=noninteractive
APT_FLAGS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# --- 日志工具 ---
log()        { echo -e "$1"; }
step_start() { log "▶ $1..."; }
step_end()   { log "✓ $1 完成\n"; }
step_fail()  { log "✗ $1 失败"; exit 1; }

cleanup() { rm -rf "$TEMP_DIR" 2>/dev/null || true; }
trap 'cleanup' EXIT
on_error() { local c=$?; log "❗ 发生错误 (exit $c)，尝试写入状态..."; write_status_file || true; exit "$c"; }
trap on_error ERR

# --- 小工具 ---
detect_debian_major() { [[ -f /etc/debian_version ]] && cut -d. -f1 < /etc/debian_version || echo 0; }
detect_ssh_port()     { (sshd -T 2>/dev/null | awk '/^port /{print $2; exit}') || echo "22"; }
docker_container_state(){ docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || echo "unknown"; }

# 启动 Docker（本地已有为前提，不联网安装）
ensure_docker_running() {
  if command -v docker &>/dev/null; then
    if systemctl list-unit-files | grep -q '^docker\.service'; then
      systemctl enable --now docker 2>/dev/null || true
    else
      # 非 systemd 或精简发行版
      service docker start 2>/dev/null || dockerd >/dev/null 2>&1 & disown || true
    fi
    # 等 5 秒看看能否 talking
    timeout 5s bash -c 'until docker info &>/dev/null; do sleep 1; done' || true
    docker info &>/dev/null && return 0 || return 1
  else
    return 2  # 未安装
  fi
}

# 在常见路径寻找 compose
find_compose_dir() {
  local svc="$1"
  local candidates=(
    "/opt/${svc}"
    "/srv/${svc}"
    "/etc/${svc}"
    "/usr/local/${svc}"
    "/root/${svc}"
  )
  for d in "${candidates[@]}"; do
    [[ -f "$d/docker-compose.yml" || -f "$d/compose.yml" ]] && { echo "$d"; return 0; }
  done
  return 1
}

# 通用：优先启动已有容器；否则尝试 compose；都无则提示
start_local_service() {
  local cname="$1"    # 期望容器名
  local svcdir_hint="$2"  # 查找 compose 的服务目录提示（如 snell / sing-box）
  local pretty="$3"   # 展示名

  log "  尝试启动 $pretty ..."

  # 1) 容器存在则启动
  if docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
    if docker start "$cname" >/dev/null; then
      log "  $pretty: 已启动 (container: $cname, 状态: $(docker_container_state "$cname"))."
      return 0
    else
      log "  $pretty: 启动容器失败 (container: $cname)。"
      return 1
    fi
  fi

  # 2) 查找 compose
  local d
  if d=$(find_compose_dir "$svcdir_hint"); then
    ( cd "$d"
      if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        docker compose up -d && { log "  $pretty: 通过 compose 启动 (目录: $d)。"; return 0; }
      elif command -v docker-compose &>/dev/null; then
        docker-compose up -d && { log "  $pretty: 通过 docker-compose 启动 (目录: $d)。"; return 0; }
      else
        log "  $pretty: 未找到 docker compose / docker-compose 可用命令。"
        return 1
      fi
    )
  else
    log "  $pretty: 未发现现有容器或 compose 文件。请确保本地已准备好镜像/compose。"
    return 1
  fi
}

# --- 状态写入 ---
write_status_file() {
  local SSH_PORT=$(detect_ssh_port)
  local CURR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  local OS_NAME=$(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Debian")
  local KERNEL=$(uname -r)

  mkdir -p "$(dirname "$STATUS_FILE")"
  if command -v jq &>/dev/null; then
    local executed_json failed_json
    if (( ${#EXECUTED_MODULES[@]} )); then
      executed_json=$(printf '%s\n' "${EXECUTED_MODULES[@]}" | jq -R . | jq -s .)
    else executed_json='[]'; fi
    if (( ${#FAILED_MODULES[@]} )); then
      failed_json=$(printf '%s\n' "${FAILED_MODULES[@]}" | jq -R . | jq -s .)
    else failed_json='[]'; fi

    jq -n \
      --arg version "$SCRIPT_VERSION" \
      --arg last_run "$(date '+%Y-%m-%d %H:%M:%S')" \
      --arg os "$OS_NAME" \
      --arg kernel "$KERNEL" \
      --arg ssh_port "$SSH_PORT" \
      --argjson executed "$executed_json" \
      --argjson failed "$failed_json" \
      --argjson schema_version "$STATUS_SCHEMA_VERSION" \
      '{
        "schema_version": $schema_version,
        "script_version": $version,
        "last_run": $last_run,
        "executed_modules": $executed,
        "failed_modules": $failed,
        "system_info": {
          "os": $os,
          "kernel": $kernel,
          "ssh_port": $ssh_port,
          "tcp_congestion_control": "'$CURR_CC'"
        }
      }' > "$STATUS_FILE"
  else
    local executed_json="" failed_json=""
    (( ${#EXECUTED_MODULES[@]} )) && executed_json=$(printf '"%s",' "${EXECUTED_MODULES[@]}" | sed 's/,$//')
    (( ${#FAILED_MODULES[@]} ))   && failed_json=$(printf '"%s",' "${FAILED_MODULES[@]}" | sed 's/,$//')
    cat > "$STATUS_FILE" <<EOF
{
  "schema_version": ${STATUS_SCHEMA_VERSION},
  "script_version": "${SCRIPT_VERSION}",
  "last_run": "$(date '+%Y-%m-%d %H:%M:%S')",
  "executed_modules": [${executed_json}],
  "failed_modules": [${failed_json}],
  "system_info": {
    "os": "${OS_NAME//\"/}",
    "kernel": "${KERNEL}",
    "ssh_port": "${SSH_PORT}",
    "tcp_congestion_control": "${CURR_CC}"
  }
}
EOF
  fi
}

# --- 交互 ---
was_module_executed_successfully() {
  local module_name="$1"
  [[ -f "$STATUS_FILE" ]] || return 1
  if command -v jq &>/dev/null; then
    jq -e --arg mod "$module_name" '.executed_modules | index($mod) != null' "$STATUS_FILE" &>/dev/null
  else
    grep -q "\"$module_name\"" "$STATUS_FILE" 2>/dev/null
  fi
}

ask_user_for_module() {
  local module_name="$1" description="$2" choice
  local prompt_msg="? 是否执行 $description 模块?"

  if (( ${#MODULES_TO_RUN[@]} > 0 )); then
    [[ -n "${MODULES_TO_RUN[$module_name]:-}" ]] && return 0 || return 1
  fi
  if ! $INTERACTIVE_MODE; then return 0; fi

  if $RERUN_MODE && was_module_executed_successfully "$module_name"; then
    read -p "$prompt_msg (已执行过，建议选 n) [y/N]: " choice; choice="${choice:-N}"
  else
    read -p "$prompt_msg [Y/n]: " choice; choice="${choice:-Y}"
  fi
  [[ "$choice" =~ ^[Yy]$ ]]
}

# --- 主要流程 ---
main() {
  # 参数
  while [[ "${1:-}" != "" ]]; do
    case "$1" in
      -y|--yes) INTERACTIVE_MODE=false; shift ;;
      -m|--module)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          MODULES_TO_RUN["$2"]=1; shift 2
        else log "错误: --module 需要模块名"; exit 1; fi ;;
      *) log "未知参数: $1"; exit 1 ;;
    esac
  done

  # 步骤 1
  step_start "步骤 1: 基础环境检查和准备"
  [[ "$(id -u)" = "0" ]] || step_fail "必须以 root 运行"
  [[ -f /etc/debian_version ]] || step_fail "仅适用于 Debian 系统"

  debian_version=$(detect_debian_major)
  if (( debian_version < 12 )); then
    log "警告: 建议 Debian 12+。当前: $(cat /etc/debian_version)"
    if $INTERACTIVE_MODE; then read -p "确定继续? (y/n): " c; [[ "$c" != "y" ]] && exit 1; fi
  fi

  [[ -f "$STATUS_FILE" ]] && RERUN_MODE=true && log "检测到历史状态，进入更新模式。"

  log "检查网络连通性（不强制）..."
  if curl -fsSL --connect-timeout 5 --head https://cp.cloudflare.com >/dev/null; then
    log "网络连通性良好。"
  else
    log "提示: 当前外网不可达或不稳定（本脚本对 Snell/Sing-box 仅做本地启动，无需联网）。"
  fi

  log "检查基础工具..."; apt-get update -qq
  BASE_TOOLS=(curl wget jq ca-certificates)
  NEED=(); for t in "${BASE_TOOLS[@]}"; do command -v "$t" &>/dev/null || NEED+=("$t"); done
  (( ${#NEED[@]} )) && apt-get install $APT_FLAGS "${NEED[@]}"

  mkdir -p "$TEMP_DIR"
  step_end "步骤 1"

  # 步骤 2: 系统更新（可离线继续）
  step_start "步骤 2: 系统更新"
  apt-get update || true
  if $RERUN_MODE; then
    log "更新模式: apt upgrade"
    apt-get upgrade $APT_FLAGS || true
  else
    log "首次运行: apt full-upgrade"
    apt-get full-upgrade $APT_FLAGS || true
  fi
  apt-get autoremove -y || true; apt-get autoclean -y || true

  # 核心包（尽量少，离线也不硬装）
  CORE_PKGS=(dnsutils rsync chrony cron)
  MISS=(); for p in "${CORE_PKGS[@]}"; do dpkg -s "$p" &>/dev/null || MISS+=("$p"); done
  (( ${#MISS[@]} )) && { log "安装核心包: ${MISS[*]}"; apt-get install $APT_FLAGS "${MISS[@]}" || true; }

  # hosts 安全追加
  HOSTNAME=$(hostname)
  if ! grep -qE "^127\.0\.1\.1\s+.*\b${HOSTNAME}\b" /etc/hosts; then
    grep -qE "^127\.0\.0\.1\s+" /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
    echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
  fi
  step_end "步骤 2"

  # 步骤 3: 模块化执行（Snell/Sing-box 改为“本地 Docker 启动”）
  step_start "步骤 3: 模块化功能部署"

  MODULE_DEFINITIONS=(
    "system-optimize|系统优化 (Zram, 时区, 服务管理)"
    "docker-setup|Docker 本地服务启动"
    "snell-setup|Snell v5 (本地 Docker 启动)"
    "sing-box-setup|Sing-box (本地 Docker 启动)"
    "network-optimize|网络性能优化 (BBR + fq_codel)"
    "ssh-security|SSH 安全配置"
    "auto-update-setup|自动更新系统"
  )

  for def in "${MODULE_DEFINITIONS[@]}"; do
    module=$(echo "$def" | cut -d'|' -f1)
    desc=$(echo "$def"   | cut -d'|' -f2)
    if ask_user_for_module "$module" "$desc"; then
      log "\n处理模块: $module"
      case "$module" in
        docker-setup)
          st=0
          ensure_docker_running || st=$?
          if (( st == 0 )); then
            log "  Docker 本地服务已就绪。"
            EXECUTED_MODULES+=("$module")
          elif (( st == 2 )); then
            log "  未检测到本机 Docker。请先离线/手动安装 Docker 再运行我。"
            FAILED_MODULES+=("$module")
          else
            log "  Docker 已安装但启动失败，请检查 systemd / 日志。"
            FAILED_MODULES+=("$module")
          fi
          ;;
        snell-setup)
          if command -v docker &>/dev/null; then
            ensure_docker_running || true
            if start_local_service "snell-server-v5" "snell" "Snell v5"; then
              EXECUTED_MODULES+=("$module")
            else
              FAILED_MODULES+=("$module")
            fi
          else
            log "  本机未安装 Docker，无法启动 Snell 容器。"
            FAILED_MODULES+=("$module")
          fi
          ;;
        sing-box-setup)
          if command -v docker &>/dev/null; then
            ensure_docker_running || true
            if start_local_service "sing-box-server" "sing-box" "Sing-box"; then
              EXECUTED_MODULES+=("$module")
            else
              FAILED_MODULES+=("$module")
            fi
          else
            log "  本机未安装 Docker，无法启动 Sing-box 容器。"
            FAILED_MODULES+=("$module")
          fi
          ;;
        *)
          # 其余模块保持“在线/本地脚本自备”的模式
          # 如需完全离线，可把这些模块也改成本地实现
          log "  模块 '$module' 暂未内置本地实现，请按需自备脚本或略过。"
          FAILED_MODULES+=("$module")
          ;;
      esac
    else
      log "跳过模块: $module"
    fi
  done
  step_end "步骤 3"

  # 步骤 4: 摘要
  step_start "步骤 4: 生成部署摘要"
  log "\n╔═════════════════════════════════════════╗"
  log "║           系统部署完成摘要                ║"
  log "╚═════════════════════════════════════════╝"
  show_info(){ log " • $1: $2"; }

  SSH_PORT=$(detect_ssh_port)
  OS_NAME=$(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Debian")
  KERNEL=$(uname -r)
  CURR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")

  show_info "脚本版本" "$SCRIPT_VERSION"
  show_info "部署模式" "$( $RERUN_MODE && echo 更新模式 || echo 首次部署 )"
  show_info "操作系统" "$OS_NAME"
  show_info "内核版本" "$KERNEL"

  (( ${#EXECUTED_MODULES[@]} )) && { log "\n✅ 成功执行的模块:"; printf "   • %s\n" "${EXECUTED_MODULES[@]}"; }
  (( ${#FAILED_MODULES[@]}   )) && { log "\n❌ 执行失败的模块:"; printf "   • %s\n" "${FAILED_MODULES[@]}"; }

  log "\n📊 当前系统状态:"
  if command -v docker &>/dev/null; then
    show_info "Docker" "可用 ($(docker --version 2>/dev/null))"
    if docker ps -a --format '{{.Names}}' | grep -qx "snell-server-v5"; then
      show_info "Snell v5" "容器存在 (状态: $(docker_container_state snell-server-v5))"
    else
      show_info "Snell v5" "未检测到容器"
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "sing-box-server"; then
      show_info "Sing-box" "容器存在 (状态: $(docker_container_state sing-box-server))"
    else
      show_info "Sing-box" "未检测到容器"
    fi
  else
    show_info "Docker" "未安装"
  fi

  show_info "SSH 端口" "$SSH_PORT"
  show_info "网络拥塞控制" "$CURR_CC"

  log "\n──────────────────────────────────────────────────"
  log " 部署完成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  log "──────────────────────────────────────────────────\n"
  step_end "步骤 4"

  # 步骤 5: 写状态
  step_start "步骤 5: 保存部署状态"
  write_status_file
  step_end "步骤 5"

  # 完成提示
  cleanup
  log "✅ 所有任务完成！"
  if printf '%s\n' "${EXECUTED_MODULES[@]}" | grep -qx "ssh-security"; then
    [[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]] && {
      log "⚠️  SSH 端口已更改为 $SSH_PORT"
      log "   用新端口连接: ssh -p $SSH_PORT user@server"
    }
  fi
  log "🔄 可随时重跑本脚本进行维护。"
  log "📄 部署状态: $STATUS_FILE"
}

main "$@"
exit 0
