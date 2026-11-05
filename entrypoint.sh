#!/bin/sh
# 由环境变量渲染 Xray 配置并启动。
# 必需变量：UUID（部署时在 Cloady 控制台填，绝不写进仓库）
# 可选变量：WS_PATH（默认 /ray）
set -e
if [ -z "$UUID" ]; then
  echo "UUID env var is required" >&2
  exit 1
fi
WS_PATH="${WS_PATH:-/ray}"
cat > /etc/xray.json <<EOF
{
  "inbounds": [
    {
      "port": 3000,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
exec /usr/local/bin/xray run -c /etc/xray.json
