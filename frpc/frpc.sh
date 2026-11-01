#!/bin/bash

FRPC_USER="frpc"
FRPC_DIR="/opt/frpc"
FRPC_BIN="$FRPC_DIR/frpc"
FRPC_CONF="$FRPC_DIR/frpc.toml"
TEMP_CONF="${FRPC_CONF}.tmp"
SERVICE_FILE="/etc/systemd/system/frpc.service"

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    exit 1
fi

# 1. 自动识别系统架构并设定下载链接
ARCH=$(uname -m)
echo "=> 正在检测系统架构..."
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    echo "✅ 检测到架构: AMD64"
    URL="https://raw.githubusercontent.com/XiaoTuCloud/vps_shell/refs/heads/main/frpc/amd64/frpc"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    echo "✅ 检测到架构: ARM64"
    URL="https://raw.githubusercontent.com/XiaoTuCloud/vps_shell/refs/heads/main/frpc/arm64/frpc"
else
    echo "❌ 错误：不支持的系统架构 ($ARCH)！"
    exit 1
fi

# 2. 安全升级：先停止旧服务，释放文件占用
echo "=> 正在清理旧服务..."
systemctl stop frpc >/dev/null 2>&1
systemctl disable frpc >/dev/null 2>&1

# 3. 创建专属系统用户和目录
if ! id "$FRPC_USER" >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -d "$FRPC_DIR" "$FRPC_USER"
fi
mkdir -p "$FRPC_DIR" && cd "$FRPC_DIR" || exit 1

# 4. 带进度条下载，防止网页终端假死
echo "==> 正在下载 frpc (保持屏幕滚动防断连) ..."
echo "下载链接: $URL"
if command -v curl >/dev/null 2>&1; then
    curl -fL -4 --retry 3 --progress-bar -o "$FRPC_BIN" "$URL"
else
    wget --tries=3 --show-progress -O "$FRPC_BIN" "$URL"
fi

if [ ! -f "$FRPC_BIN" ]; then
    echo "❌ 下载失败！请检查网络是否能访问 GitHub。"
    exit 1
fi
chmod +x "$FRPC_BIN"
chown -R "$FRPC_USER:$FRPC_USER" "$FRPC_DIR"

# 5. 读取配置文件（保留你的消毒逻辑）
echo "==> 请粘贴 frpc.toml 内容，输入单独一行 ok 并回车："
> "$TEMP_CONF"

while IFS= read -r line; do
    # 删掉所有的 DEL 控制字符 (八进制 177)
    line=$(printf '%s' "$line" | tr -d '\177')
    # 去除 Windows 回车符 (\r)
    line="${line%$'\r'}"
    
    if [ ! -s "$TEMP_CONF" ]; then
        # 如果是第一行，去掉 BOM 头和任何不可见的控制字符
        line=$(printf '%s' "$line" | sed '1s/^\xEF\xBB\xBF//; 1s/^[[:cntrl:][:space:]]*//')
    fi

    [[ "$line" =~ ^ok[[:space:]]*$ ]] && break
    printf '%s\n' "$line" >> "$TEMP_CONF"
done

if [ ! -s "$TEMP_CONF" ]; then
    echo "❌ 错误：未检测到配置内容。"
    rm -f "$TEMP_CONF"
    exit 1
fi
mv "$TEMP_CONF" "$FRPC_CONF"
chown "$FRPC_USER:$FRPC_USER" "$FRPC_CONF"
chmod 600 "$FRPC_CONF"

# 6. 写入更安全、带日志限制的 Systemd 服务
echo "==> 正在写入系统服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=frpc client
After=network.target

[Service]
Type=simple
User=$FRPC_USER
Group=$FRPC_USER
WorkingDirectory=$FRPC_DIR
ExecStart=$FRPC_BIN -c $FRPC_CONF
Restart=always
RestartSec=5s

# 日志防爆磁盘限制
StandardOutput=journal
StandardError=journal
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000

[Install]
WantedBy=multi-user.target
EOF

echo "==> 正在启动服务..."
systemctl daemon-reload
systemctl enable frpc >/dev/null 2>&1
systemctl restart frpc

echo "🎉 安装完成！当前状态如下："
systemctl status frpc --no-pager
