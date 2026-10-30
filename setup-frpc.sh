#!/bin/bash

FRPC_DIR="/root/frpc"
FRPC_BIN="$FRPC_DIR/frpc"
FRPC_CONF="$FRPC_DIR/frpc.toml"
TEMP_CONF="${FRPC_CONF}.tmp"
SERVICE_FILE="/etc/systemd/system/frpc.service"
URL="https://raw.githubusercontent.com/XiaoTuCloud/vps_frp/refs/heads/main/frpc"

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本 (sudo bash install-frpc.sh)"
    exit 1
fi

echo "==> 1. 正在准备环境..."
mkdir -p "$FRPC_DIR"
cd "$FRPC_DIR" || exit 1

echo "==> 2. 正在下载 frpc 核心文件..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$FRPC_BIN" "$URL"
else
    wget -qO "$FRPC_BIN" "$URL"
fi

if [ ! -f "$FRPC_BIN" ]; then
    echo "❌ 下载失败！请检查服务器网络是否能访问 GitHub。"
    exit 1
fi
chmod +x "$FRPC_BIN"

echo "==> 3. 请配置 frpc.toml"
echo "--------------------------------------------------------"
echo "请将你的 frpc.toml 内容粘贴到下方。"
echo "👉 粘贴完成后，请另起一行，输入 ok 并回车。"
echo "--------------------------------------------------------"

# 清空临时文件
> "$TEMP_CONF"

# 开始读取输入
while IFS= read -r line; do
    # 核心兼容处理：去掉 Windows 粘贴带来的 \r 回车符
    line="${line%$'\r'}"
    
    # 匹配 ok，允许后面有空格
    if [[ "$line" =~ ^ok[[:space:]]*$ ]]; then
        break
    fi
    printf '%s\n' "$line" >> "$TEMP_CONF"
done

# 检查文件是否为空
if [ ! -s "$TEMP_CONF" ]; then
    echo "❌ 错误：未检测到配置内容，脚本退出。"
    rm -f "$TEMP_CONF"
    exit 1
fi

# 替换正式配置
mv "$TEMP_CONF" "$FRPC_CONF"
echo "--------------------------------------------------------"
echo "✅ 配置文件已成功保存至: $FRPC_CONF"

echo "==> 4. 正在写入系统服务 (systemd)..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=frpc
After=network.target

[Service]
Type=simple
ExecStart=$FRPC_BIN -c $FRPC_CONF
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "==> 5. 正在启动 frpc 服务..."
systemctl daemon-reload
systemctl enable frpc >/dev/null 2>&1
systemctl restart frpc

echo "--------------------------------------------------------"
echo "🎉 安装完成！以下是服务运行状态："
systemctl status frpc --no-pager

echo -e "\n如果状态不是 active (running)，请使用以下命令查看报错日志："
echo "journalctl -u frpc -f"
