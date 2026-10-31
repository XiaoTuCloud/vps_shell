#!/usr/bin/env bash
set -euo pipefail

# ============ 配置区域（按需修改） ============
INSTALL_DIR="/opt/ech0"
DATA_DIR="${INSTALL_DIR}/data"
SERVICE_NAME="ech0"
ECH0_PORT="6277"
# =============================================

# ---------- 检查 root 权限 ----------
if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 权限运行此脚本：sudo bash $0"
  exit 1
fi

# ---------- 检测 CPU 架构 ----------
case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "不支持的架构：$(uname -m)，仅支持 x86_64 与 aarch64。"
    exit 1
    ;;
esac
echo "检测到架构：${ARCH}"

# ---------- 获取最新版本号 ----------
echo "正在获取 Ech0 最新版本..."
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/lin-snow/Ech0/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+' || true)
if [[ -z "${LATEST_TAG}" ]]; then
  echo "无法获取最新版本号，请检查网络或手动指定版本。"
  exit 1
fi
echo "最新版本：${LATEST_TAG}"

# ---------- 下载二进制包 ----------
TARBALL="ech0-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/lin-snow/Ech0/releases/download/${LATEST_TAG}/${TARBALL}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "正在下载：${DOWNLOAD_URL}"
curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DIR}/${TARBALL}"

# ---------- 解压并定位二进制 ----------
echo "正在解压..."
tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"

BINARY_PATH=$(find "${TMP_DIR}" -maxdepth 2 -type f -name "ech0" | head -n 1)
if [[ -z "${BINARY_PATH}" ]]; then
  echo "未在压缩包中找到 ech0 可执行文件。"
  exit 1
fi

# ---------- 安装到固定目录 ----------
echo "正在安装到 ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}" "${DATA_DIR}"
install -m 755 "${BINARY_PATH}" "${INSTALL_DIR}/ech0"

# ---------- 生成 JWT_SECRET ----------
JWT_SECRET=$(openssl rand -hex 32)
echo "已生成随机 JWT_SECRET（已写入 systemd 服务文件）"

# ---------- 创建 systemd 服务 ----------
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Ech0 Service (binary deployment)
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/ech0
Restart=on-failure
RestartSec=5

# 关键环境变量：固定 JWT_SECRET，避免重启后所有会话失效
Environment="JWT_SECRET=${JWT_SECRET}"

[Install]
WantedBy=multi-user.target
EOF

echo "已创建服务文件：${SERVICE_FILE}"

# ---------- 启动服务并设置开机自启 ----------
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

# ---------- 验证状态 ----------
echo ""
echo "=============================================="
systemctl status "${SERVICE_NAME}" --no-pager -l
echo "=============================================="
echo ""
echo "Ech0 已通过二进制方式安装并启动。"
echo "访问地址：http://<服务器IP>:${ECH0_PORT}"
echo "数据目录：${DATA_DIR}（备份此目录即可保留全部数据）"
echo ""
echo "常用命令："
echo "  查看状态： systemctl status ${SERVICE_NAME}"
echo "  查看日志： journalctl -u ${SERVICE_NAME} -f"
echo "  重启服务： systemctl restart ${SERVICE_NAME}"
echo "  停止服务： systemctl stop ${SERVICE_NAME}"
