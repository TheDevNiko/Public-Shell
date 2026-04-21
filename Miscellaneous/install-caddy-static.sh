#!/usr/bin/env bash
set -euo pipefail

DOMAIN=""
PORT=""
CF_TOKEN=""

usage() {
  echo "用法："
  echo "  bash install-caddy-static.sh --domain example.com --port 8443 --cf-token xxx"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="${2:-}"; shift 2 ;;
    --port)
      PORT="${2:-}"; shift 2 ;;
    --cf-token)
      CF_TOKEN="${2:-}"; shift 2 ;;
    *)
      usage ;;
  esac
done

[[ -z "$DOMAIN" || -z "$PORT" || -z "$CF_TOKEN" ]] && usage

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 运行"
  exit 1
fi

detect_debian_codename() {
  if [[ ! -r /etc/os-release ]]; then
    echo "无法读取 /etc/os-release"
    exit 1
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "debian" ]]; then
    echo "当前系统不是 Debian，检测到 ID=${ID:-unknown}"
    exit 1
  fi

  local ver major codename
  ver="${VERSION_ID:-}"
  major="${ver%%.*}"

  case "$major" in
    11) codename="bullseye" ;;
    12) codename="bookworm" ;;
    13) codename="trixie" ;;
    *)
      echo "暂不支持的 Debian 版本: ${ver:-unknown}"
      exit 1
      ;;
  esac

  echo "$codename"
}

backup_and_replace_sources() {
  local codename="$1"
  local backup_file

  echo "[1/7] 备份并替换 Debian 官方源..."

  backup_file="/etc/apt/sources.list.bak.$(date +%F-%H%M%S)"
  if [[ -f /etc/apt/sources.list ]]; then
    cp -a /etc/apt/sources.list "$backup_file"
    echo "已备份旧源到: $backup_file"
  fi

  cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF

  echo "已写入 Debian 官方源: ${codename}"
}

install_caddy() {
  echo "[2/7] 更新软件包索引..."
  apt-get update --allow-releaseinfo-change

  echo "[3/7] 安装 Caddy 官方源依赖..."
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

  echo "[4/7] 安装 Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null

  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  chmod o+r /etc/apt/sources.list.d/caddy-stable.list

  apt-get update --allow-releaseinfo-change
  apt-get install -y caddy
}

ensure_plugin() {
  echo "[5/7] 检查 Cloudflare DNS 插件..."

  if caddy list-modules | grep -q '^dns.providers.cloudflare$'; then
    echo "已存在 dns.providers.cloudflare"
  else
    echo "安装 dns.providers.cloudflare ..."
    caddy add-package github.com/caddy-dns/cloudflare
  fi
}

write_config() {
  echo "[6/7] 生成配置..."

  mkdir -p /etc/caddy

  cat > /etc/caddy/caddy.env <<EOF
CLOUDFLARE_API_TOKEN=${CF_TOKEN}
EOF
  chmod 600 /etc/caddy/caddy.env

  cat > /etc/caddy/Caddyfile <<EOF
{
    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    auto_https disable_redirects
}

${DOMAIN}:${PORT} {
    tls {
        key_type p256
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    root * /usr/share/caddy
    file_server

    encode gzip zstd
}
EOF

  mkdir -p /etc/systemd/system/caddy.service.d
  cat > /etc/systemd/system/caddy.service.d/override.conf <<EOF
[Service]
EnvironmentFile=/etc/caddy/caddy.env
EOF
}

start_service() {
  echo "[7/7] 校验并启动服务..."

  export CLOUDFLARE_API_TOKEN="$CF_TOKEN"
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

  systemctl daemon-reload
  systemctl enable --now caddy
  systemctl restart caddy

  echo
  echo "✅ 部署完成"
  echo "----------------------------------"
  echo "域名:    https://${DOMAIN}:${PORT}"
  echo "目录:    /usr/share/caddy"
  echo "源文件:  /etc/apt/sources.list"
  echo
  echo "测试页面："
  echo "  echo 'hello world' > /usr/share/caddy/index.html"
  echo
  echo "查看状态："
  echo "  systemctl status caddy"
  echo
  echo "查看日志："
  echo "  journalctl -u caddy -f"
  echo
  echo "重载配置："
  echo "  systemctl reload caddy"
  echo "----------------------------------"
}

echo "========== 开始部署 =========="

CODENAME="$(detect_debian_codename)"
echo "检测到 Debian 代号: ${CODENAME}"

backup_and_replace_sources "$CODENAME"
install_caddy
ensure_plugin
write_config
start_service
