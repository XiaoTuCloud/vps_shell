#!/bin/bash

FRPC_DIR="/root/frpc"
FRPC_BIN="$FRPC_DIR/frpc"
FRPC_CONF="$FRPC_DIR/frpc.toml"
TEMP_CONF="${FRPC_CONF}.tmp"
SERVICE_FILE="/etc/systemd/system/frpc.service"
URL="https://raw.githubusercontent.com/XiaoTuCloud/vps_frp/refs/heads/main/frpc"

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    exit 1
fi

mkdir -p "$FRPC_DIR" && cd "$FRPC_DIR" || exit 1

echo "==> 正在下载 frpc ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$FRPC_BIN" "$URL"
else
    wget -qO "$FRPC_BIN" "$URL"
fi

if [ ! -f "$FRPC_BIN" ]; then
    echo "❌ 下载失败！请检查网络是否能访问 GitHub。"
    exit 1
fi
chmod +x "$FRPC_BIN"

echo "==> 请粘贴 frpc.toml 内容，输入单独一行 ok 并回车："
> "$TEMP_CONF"

while IFS= read -r line; do
    # 【消毒 1】删掉所有的 DEL 控制字符 (八进制 177)
    line=$(printf '%s' "$line" | tr -d '\177')
    
    # 【消毒 2】去除 Windows 回车符 (\r)
    line="${line%$'\r'}"
    
    if [ ! -s "$TEMP_CONF" ]; then
        # 【消毒 3】如果是第一行，去掉 BOM 头和任何不可见的控制字符
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

echo "==> 正在写入系统服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=frpc
After=network.target

[Service]
Type=simple
WorkingDirectory=$FRPC_DIR
ExecStart=$FRPC_BIN -c $FRPC_CONF
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "==> 正在启动服务..."
systemctl daemon-reload
systemctl enable frpc >/dev/null 2>&1
systemctl restart frpc

echo "🎉 安装完成！当前状态如下："
systemctl status frpc --no-pager
