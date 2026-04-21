#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/v2node"
CONFIG_DIR="/etc/v2node"
SERVICE_NAME="v2node"
PACKAGE_URL=""
START_SERVICE=1

usage() {
  cat <<'EOF'
用法:
  bash install.sh --package-url <URL> [选项]

选项:
  --package-url URL      必填，线上压缩包地址
  --install-dir DIR      二进制安装目录，默认 /usr/local/v2node
  --config-dir DIR       配置目录，默认 /etc/v2node
  --service-name NAME    systemd 服务名，默认 v2node
  --no-start             安装后不启用/重启 systemd 服务
  -h, --help             显示帮助

示例:
  curl -fsSL https://example.com/install.sh | bash -s -- \
    --package-url https://example.com/v2node_linux_amd64_v0.2.8.tar.gz
EOF
}

log() {
  echo "[v2node-install] $*"
}

die() {
  echo "[v2node-install] ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-url)
      [[ $# -ge 2 ]] || die "--package-url 缺少参数"
      PACKAGE_URL="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || die "--install-dir 缺少参数"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --config-dir)
      [[ $# -ge 2 ]] || die "--config-dir 缺少参数"
      CONFIG_DIR="$2"
      shift 2
      ;;
    --service-name)
      [[ $# -ge 2 ]] || die "--service-name 缺少参数"
      SERVICE_NAME="$2"
      shift 2
      ;;
    --no-start)
      START_SERVICE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1"
      ;;
  esac
done

[[ -n "${PACKAGE_URL}" ]] || die "请使用 --package-url 指定安装包 URL"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "请使用 root 权限运行"
fi

for cmd in tar install wget; do
  command -v "${cmd}" >/dev/null 2>&1 || die "缺少命令: ${cmd}"
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
PKG_FILE="${WORK_DIR}/v2node.tar.gz"
EXTRACT_DIR="${WORK_DIR}/extract"
mkdir -p "${EXTRACT_DIR}"

download_package() {
  local url="$1"
  local out="$2"
  rm -f "${out}"
  log "下载安装包（下载器: wget）: ${url}"
  wget -N --no-check-certificate -O "${out}" "${url}" || die "下载安装包失败: ${url}"
}

download_package "${PACKAGE_URL}" "${PKG_FILE}"

log "解压安装包"
tar -xzf "${PKG_FILE}" -C "${EXTRACT_DIR}" || die "解压失败，压缩包可能已损坏: ${PKG_FILE}"

required_files=(
  "v2node"
  "geosite.dat"
  "geoip.dat"
  "whiteList"
  "config.yaml"
  "dns.yaml"
  "routing.yaml"
  "outbounds.yaml"
  "v2node.service"
)

for f in "${required_files[@]}"; do
  [[ -f "${EXTRACT_DIR}/${f}" ]] || die "安装包缺少文件: ${f}"
done

mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}"

log "覆盖安装目录: ${INSTALL_DIR}"
find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -af "${EXTRACT_DIR}/." "${INSTALL_DIR}/"
chmod 0755 "${INSTALL_DIR}/v2node"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  local name="$3"
  if [[ -f "${dst}" ]]; then
    log "已存在 ${name}，跳过复制: ${dst}"
    return
  fi
  install -m 0644 "${src}" "${dst}"
  log "复制 ${name}: ${dst}"
}

copy_if_missing "${INSTALL_DIR}/config.yaml" "${CONFIG_DIR}/config.yaml" "config.yaml"
copy_if_missing "${INSTALL_DIR}/dns.yaml" "${CONFIG_DIR}/dns.yaml" "dns.yaml"
copy_if_missing "${INSTALL_DIR}/routing.yaml" "${CONFIG_DIR}/routing.yaml" "routing.yaml"
copy_if_missing "${INSTALL_DIR}/outbounds.yaml" "${CONFIG_DIR}/outbounds.yaml" "outbounds.yaml"
copy_if_missing "${INSTALL_DIR}/whiteList" "${CONFIG_DIR}/whiteList" "whiteList"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
install -m 0644 "${INSTALL_DIR}/v2node.service" "${SERVICE_FILE}"
log "安装/覆盖 systemd 服务: ${SERVICE_FILE}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    systemctl enable "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"
    log "服务已启用并重启: ${SERVICE_NAME}"
  else
    log "已跳过服务启动，可手动执行:"
    log "  systemctl enable ${SERVICE_NAME}.service"
    log "  systemctl restart ${SERVICE_NAME}.service"
  fi
else
  log "未检测到 systemctl，请手动配置服务启动"
fi

log "安装完成"
