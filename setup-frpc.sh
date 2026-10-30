#!/bin/bash
set -euo pipefail

# ---------- 必须 root ----------
if [[ $EUID -ne 0 ]]; then
    echo "请用 root 运行：sudo bash $0" >&2
    exit 1
fi

FRPC_DIR=/root/frpc
FRPC_BIN=$FRPC_DIR/frpc
FRPC_CONF=$FRPC_DIR/frpc.toml
SERVICE_FILE=/etc/systemd/system/frpc.service
URL=https://raw.githubusercontent.com/XiaoTuCloud/vps_frp/refs/heads/main/frpc

# ---------- 1. 建目录 ----------
echo "==> 创建目录 $FRPC_DIR"
mkdir -p "$FRPC_DIR"
cd "$FRPC_DIR"

# ---------- 2. 下载 frpc ----------
echo "==> 下载 frpc ..."
if command -v wget >/dev/null 2>&1; then
    wget -O "$FRPC_BIN" "$URL"
else
    curl -fsSL -o "$FRPC_BIN" "$URL"
fi

# ---------- 3. 加执行权限并校验 ----------
chmod +x "$FRPC_BIN"
if ! "$FRPC_BIN" -v >/dev/null 2>&1; then
    echo "!! frpc 无法执行，下载可能失败（检查网络/被墙），已中止" >&2
    exit 1
fi
echo "==> frpc 下载成功：$("$FRPC_BIN" -v 2>&1 | head -n1)"

# ---------- 4. 交互写入 frpc.toml ----------
echo
echo "==> 请粘贴 frpc.toml 内容，输入单独一行 ok 并回车表示结束："
: > "$FRPC_CONF"
while IFS= read -r line; do
    [[ "$line" == "ok" ]] && break
    printf '%s\n' "$line" >> "$FRPC_CONF"
done

if [[ ! -s "$FRPC_CONF" ]]; then
    echo "!! 配置为空，已中止" >&2
    exit 1
fi
echo "==> 已写入 $FRPC_CONF，内容如下："
cat "$FRPC_CONF"

# ---------- 5. 写 systemd service ----------
echo "==> 写入 $SERVICE_FILE"
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

# ---------- 6. 启用并启动 ----------
systemctl daemon-reload
systemctl enable frpc
systemctl restart frpc
systemctl status frpc --no-pager || true

echo
echo "==> 完成。常用命令："
echo "    systemctl status frpc"
echo "    journalctl -u frpc -f"