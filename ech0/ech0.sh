#!/bin/bash

# ================= 基础配置区 =================
APP_USER="ech0"
APP_DIR="/opt/ech0"
BIN_PATH="/usr/local/bin/ech0"
# ==============================================

echo "======================================"
echo "开始一键部署 Ech0 (./ech0 serve 模式)..."
echo "======================================"

# 1. 检查 Root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行此脚本！"
  exit 1
fi

# 2. 自动识别架构并设置下载链接
ARCH=$(uname -m)
echo "=> [0/7] 正在检测系统架构..."
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    echo "✅ 检测到架构: AMD64 (x86_64)"
    DOWNLOAD_URL="https://github.com/XiaoTuCloud/vps_shell/releases/download/v1.0.0/ech0-linux-amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    echo "✅ 检测到架构: ARM64 (aarch64)"
    DOWNLOAD_URL="https://github.com/XiaoTuCloud/vps_shell/releases/download/v1.0.0/ech0-linux-arm64"
else
    echo "❌ 错误：暂不支持当前系统架构 ($ARCH)！"
    exit 1
fi

# 3. 清理旧的服务配置（保留数据目录 /opt/ech0/data）
echo "=> [1/7] 正在清理旧的 systemd 服务..."
systemctl stop ech0 >/dev/null 2>&1
systemctl disable ech0 >/dev/null 2>&1
rm -f /etc/systemd/system/ech0.service
systemctl daemon-reload

# 4. 创建专用系统用户和目录
echo "=> [2/7] 创建用户和目录..."
id "$APP_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d "$APP_DIR" "$APP_USER"
mkdir -p "$APP_DIR/data" /etc/ech0
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# 5. 下载二进制文件
echo "=> [3/7] 正在下载 Ech0 程序..."
echo "下载链接: $DOWNLOAD_URL"
if ! wget -O "$BIN_PATH" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败，请检查网络或链接。"
    exit 1
fi
chmod +x "$BIN_PATH"
chown "$APP_USER:$APP_USER" "$BIN_PATH"

# 6. 配置环境变量（固定 JWT_SECRET）
echo "=> [4/7] 配置 JWT_SECRET..."
if [ ! -s /etc/ech0/ech0.env ]; then
    SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '\n')
    echo -e "JWT_SECRET=$SECRET\nTZ=Asia/Shanghai" > /etc/ech0/ech0.env
    echo "✅ 已生成全新的 JWT_SECRET。"
else
    echo "✅ 检测到现有配置，保留原 JWT_SECRET。"
fi
chmod 600 /etc/ech0/ech0.env

# 7. 写入 Systemd 服务文件（核心：ExecStart 使用 serve 参数）
echo "=> [5/7] 配置 Systemd 服务..."
cat > /etc/systemd/system/ech0.service <<EOF
[Unit]
Description=Ech0 Self-hosted Platform
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
# 官方推荐启动方式：ech0 serve
ExecStart=$BIN_PATH serve
Restart=on-failure
RestartSec=5s
EnvironmentFile=/etc/ech0/ech0.env

# 日志限制
StandardOutput=journal
StandardError=journal
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000

[Install]
WantedBy=multi-user.target
EOF

# 8. 启动服务
echo "=> [6/7] 启动服务并设置开机自启..."
systemctl daemon-reload
systemctl enable ech0 >/dev/null 2>&1
systemctl restart ech0

# 9. 结果检查
echo "=> [7/7] 检查服务状态..."
sleep 2
if systemctl is-active --quiet ech0; then
    echo "======================================"
    echo "✅ 部署成功！Ech0 正在后台稳定运行。"
    echo "🌐 访问地址: http://服务器IP:6277"
    echo "🔑 第一个注册的账号将成为管理员(Owner)！"
    echo "📁 数据目录: $APP_DIR/data"
    echo "======================================"
else
    echo "❌ 启动失败，请执行以下命令查看详细日志："
    echo "journalctl -u ech0 -n 50 --no-pager"
fi
