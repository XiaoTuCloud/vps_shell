#!/bin/bash

# ================= 配置区 =================
DOWNLOAD_URL="https://github.com/XiaoTuCloud/vps_shell/releases/download/v1.0.0/ech0-linux-amd64"
APP_USER="ech0"
APP_DIR="/opt/ech0"
BIN_PATH="/usr/local/bin/ech0"
# ==========================================

echo "======================================"
echo "开始一键部署 Ech0..."
echo "======================================"

# 1. 检查 Root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行此脚本！"
  exit 1
fi

# 2. 清理可能存在的旧版本（保证干净重装）
echo "=> [1/7] 正在清理旧版本残留..."
systemctl stop ech0 >/dev/null 2>&1
systemctl disable ech0 >/dev/null 2>&1
rm -f /etc/systemd/system/ech0.service
rm -f "$BIN_PATH"
# 保留数据目录以防覆盖，如果确定不需要数据可以取消下一行的注释
# rm -rf "$APP_DIR"

# 3. 创建系统用户和目录
echo "=> [2/7] 创建专用运行用户和目录..."
id "$APP_USER" >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d "$APP_DIR" "$APP_USER"
mkdir -p "$APP_DIR/data" /etc/ech0
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# 4. 下载二进制文件
echo "=> [3/7] 开始下载程序 (约92MB，请耐心等待)..."
# 使用 wget 下载，带进度条防止网页终端断开
if ! wget -O "$BIN_PATH" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败，请检查网络或下载链接是否有效。"
    exit 1
fi
chmod +x "$BIN_PATH"

# 5. 配置环境变量 (自动生成固定的随机密钥)
echo "=> [4/7] 生成环境变量配置文件..."
if [ ! -s /etc/ech0/ech0.env ]; then
    SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '\n')
    echo -e "JWT_SECRET=$SECRET\nTZ=Asia/Shanghai" > /etc/ech0/ech0.env
fi
chmod 600 /etc/ech0/ech0.env

# 6. 写入 Systemd 服务文件
echo "=> [5/7] 配置 Systemd 后台服务..."
cat > /etc/systemd/system/ech0.service <<EOF
[Unit]
Description=Ech0 Self-hosted Platform
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=$BIN_PATH
Restart=on-failure
RestartSec=5s
EnvironmentFile=/etc/ech0/ech0.env

# 日志限制配置：防止日志文件无限增大撑爆磁盘
StandardOutput=journal
StandardError=journal
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务
echo "=> [6/7] 启动服务并设置开机自启..."
systemctl daemon-reload
systemctl enable ech0 >/dev/null 2>&1
systemctl restart ech0

# 8. 结果检查
echo "=> [7/7] 检查服务运行状态..."
sleep 2
if systemctl is-active --quiet ech0; then
    echo "======================================"
    echo "✅ 部署成功！Ech0 已经在后台稳定运行。"
    echo "🌐 访问地址: http://服务器IP:6277"
    echo "🔑 提示: 第一个注册的账号将自动成为管理员(Owner)！"
    echo "📁 数据目录: $APP_DIR/data"
    echo "======================================"
else
    echo "❌ 服务启动失败，请执行以下命令查看报错日志："
    echo "journalctl -u ech0 -n 20 --no-pager"
fi
