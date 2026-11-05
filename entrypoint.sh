#!/bin/sh
# 由环境变量渲染 Xray 配置并启动，同时起流量表服务。
# 必需变量：UUID（部署时在 Cloady 控制台填，绝不写进仓库）
# 可选变量：WS_PATH（默认 /ray）
# Xray 配置与原来完全一致（VLESS+WS 3000），不做任何改动；
# 流量表是独立的 httpd + 计数循环（8080），与代理互不影响。
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
mkdir -p /www
/usr/local/bin/xray run -c /etc/xray.json &
XRAY_PID=$!
busybox httpd -f -p 127.0.0.1:8080 -h /www &
/meter.sh &
trap 'kill $XRAY_PID 2>/dev/null' TERM INT
wait $XRAY_PID
