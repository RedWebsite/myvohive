#!/bin/bash
# VoHive 离线安装脚本（基于已部署 VM 上的痕迹还原）
# 原始来源：curl -fsSL https://raw.githubusercontent.com/iniwex5/vohive-release/master/install.sh | bash
# 原仓库 iniwex5/vohive-release 已下线，本脚本改用本地二进制资产（与原版二进制 sha1 一致）
#
# 已验证可用的部署环境：Ubuntu 24.04 LTS / x86_64
# 备份二进制 sha1: ee16a5c0cd04505df43805fc81838f3e20b16aee
set -e

VOHIVE_DIR=/opt/vohive
BIN_PATH=$VOHIVE_DIR/bin/vohive
DATA_DIR=$VOHIVE_DIR/data
CONFIG_PATH=$VOHIVE_DIR/config/config.yaml
SERVICE_PATH=/etc/systemd/system/vohive.service
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. root 检查 ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "[!] 请用 root 运行：sudo bash $0"
  exit 1
fi

# ── 2. 架构检查 ──────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo "[!] 当前架构 $ARCH，备份的二进制是 x86_64，可能不兼容"
  read -p "继续? [y/N] " ans
  [ "$ans" = "y" ] || exit 1
fi

# ── 3. 资产检查 ──────────────────────────────────────────────
for f in vohive mcc-mnc-table.json; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo "[!] 缺少资产文件：$SCRIPT_DIR/$f"
    exit 1
  fi
done

# ── 4. 安装依赖（与原 install.sh 一致）────────────────────────
echo "[*] 安装系统依赖：socat usbutils pciutils"
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq socat usbutils pciutils
elif command -v dnf >/dev/null; then
  dnf install -y -q socat usbutils pciutils
elif command -v yum >/dev/null; then
  yum install -y -q socat usbutils pciutils
else
  echo "[!] 未识别的包管理器，请手动安装 socat usbutils pciutils"
fi

# ── 5. 创建目录结构 ───────────────────────────────────────────
echo "[*] 创建目录 $VOHIVE_DIR"
mkdir -p "$VOHIVE_DIR"/{bin,config,data,logs}

# ── 6. 部署二进制 ─────────────────────────────────────────────
echo "[*] 部署二进制 → $BIN_PATH"
install -m 0755 "$SCRIPT_DIR/vohive" "$BIN_PATH"

# ── 7. 部署 MCC/MNC 运营商表 ──────────────────────────────────
echo "[*] 部署 mcc-mnc-table.json → $DATA_DIR"
install -m 0644 "$SCRIPT_DIR/mcc-mnc-table.json" "$DATA_DIR/mcc-mnc-table.json"

# ── 8. 写默认 config.yaml（仅当不存在，避免覆盖已配置项）─────
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[*] 写入默认 config.yaml"
  cat > "$CONFIG_PATH" <<'EOF'
bark:
    enabled: false
    group: vohive
    icon: ""
    level: active
    urls: []
email:
    enabled: false
    from_address: ""
    password: ""
    smtp_host: ""
    smtp_port: 0
    to_addresses: []
    username: ""
feishu:
    app_id: ""
    app_secret: ""
    chat_ids: []
    enabled: false
pushplus:
    channel: wechat
    enabled: false
    token: ""
    topic: ""
qq:
    app_id: ""
    app_secret: ""
    direct_ids: ""
    enabled: false
    group_ids: ""
server:
    port: :7575
telegram:
    admin_id: 0
    base_url: ""
    bot_token: ""
    chat_id: 0
    enabled: false
    proxy: ""
web:
    password: "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
    username: admin
webhook:
    enabled: false
    headers: {}
    retry_max: 3
    secret: ""
    text_template: '{{device_label}} {{text}}'
    timeout_ms: 5000
    urls: []
devices: []
EOF
  chmod 0600 "$CONFIG_PATH"
  echo "    默认 web 账号：admin / admin（首次登录后请改密码）"
else
  echo "[*] 已存在 config.yaml，跳过（未覆盖）"
fi

# ── 9. 写 systemd 单元 ────────────────────────────────────────
echo "[*] 写 systemd unit → $SERVICE_PATH"
cat > "$SERVICE_PATH" <<'EOF'
[Unit]
Description=VoHive Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vohive
ExecStart=/opt/vohive/bin/vohive -c /opt/vohive/config/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# ── 10. 启用并启动服务 ───────────────────────────────────────
echo "[*] 启用 vohive.service"
systemctl daemon-reload
systemctl enable --now vohive

# ── 11. 验证 ─────────────────────────────────────────────────
sleep 2
if systemctl is-active --quiet vohive; then
  echo
  echo "[✓] VoHive 已启动"
  echo "    后台地址：http://$(hostname -I | awk '{print $1}'):7575"
  echo "    默认账号：admin / admin"
  echo "    日志：/opt/vohive/logs/app.log"
else
  echo "[!] 服务未正常运行，查看日志：journalctl -u vohive -n 50 --no-pager"
fi
