#!/bin/sh
# 由环境变量渲染 Xray 配置并启动，同时起 nginx 分流与流量表。
# 必需变量：UUID（部署时在 Cloady 控制台填，绝不写进仓库）
# 可选变量：WS_PATH（默认 /ray）、XHTTP_PATH（默认 /xhttp）
# 结构（Cloady 一个应用只有一个公网主机名 → 单端口 3000 按路径分流）：
#   nginx 3000（公网）/ray → Xray WS 10000；/xhttp → Xray XHTTP 10001；/ → 流量表 /www
#   Xray 只监听本机（10000/10001），不直接对外；流量表由 nginx 直接供 /www。
#   任一关键进程（Xray/nginx）退出即整体退出，让容器重启，避免“看着活、代理已死”。
set -e
if [ -z "$UUID" ]; then
  echo "UUID env var is required" >&2
  exit 1
fi
WS_PATH="${WS_PATH:-/ray}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
cat > /etc/xray.json <<EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    },
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "$XHTTP_PATH", "mode": "auto" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
mkdir -p /www /tmp/nginx-client-body /tmp/nginx-proxy
/usr/local/bin/xray run -c /etc/xray.json &
XRAY_PID=$!
/meter.sh &
METER_PID=$!
nginx -c /etc/nginx/nginx.conf -g "daemon off;" &
NGINX_PID=$!
trap 'kill $XRAY_PID $NGINX_PID $METER_PID 2>/dev/null' TERM INT
while kill -0 $XRAY_PID 2>/dev/null && kill -0 $NGINX_PID 2>/dev/null; do
  sleep 5
done
kill $XRAY_PID $NGINX_PID $METER_PID 2>/dev/null
exit 1
