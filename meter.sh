#!/bin/sh
# 流量表生成循环：每 60 秒读容器网口出口（TX）计数，写流量表页与 traffic.json。
# 计数口径：容器出口流量（TX），即 Cloady 计费的出站流量；含少量 TLS/协议开销误差，
# 以官方 90% 邮件与 100% 停服为准。Xray 统计口径不可靠（本地实测计数不动），故不用。
# 月度归零：每月 1 号 UTC 重置；容器重建会丢基线文件，巡检用自己的基线接着算。
ALLOWANCE=16106127360
WWW=/www
BASE_FILE=$WWW/.traffic-baseline
MONTH_FILE=$WWW/.traffic-month
mkdir -p "$WWW"

fmt_gb() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'
}

while true; do
  YM=$(date -u +%Y-%m)
  Y=${YM%-*}; M=${YM#*-}
  # 下月 1 号 UTC（重置日）
  M=${M#0}; NM=$((M + 1)); NY=$Y
  if [ "$NM" -gt 12 ]; then NM=1; NY=$((Y + 1)); fi
  RESET=$(printf '%04d-%02d-01T00:00:00Z' "$NY" "$NM")

  # 读网口计数：RX 第 2 列，TX 第 10 列；排除 lo
  set -- $(awk '$1 ~ /:/ { gsub(/:/, "", $1); if ($1 != "lo") { rx += $2; tx += $10 } } END { print rx+0, tx+0 }' /proc/net/dev)
  RX=$1; TX=$2

  # 本月基线：月份变了，基线记为 -当前 TX，本月从 0 起算（网口计数本身不随月份归零）
  SM=$(cat "$MONTH_FILE" 2>/dev/null || echo "")
  BASE=$(cat "$BASE_FILE" 2>/dev/null || echo 0)
  if [ "$SM" != "$YM" ]; then
    BASE=$((-TX))
    echo "$YM" > "$MONTH_FILE.tmp" && mv "$MONTH_FILE.tmp" "$MONTH_FILE"
    echo "$BASE" > "$BASE_FILE.tmp" && mv "$BASE_FILE.tmp" "$BASE_FILE"
  fi

  USED=$((BASE + TX))
  if [ "$USED" -lt 0 ]; then USED=0; fi
  if [ "$USED" -gt "$ALLOWANCE" ]; then REMAIN=0; else REMAIN=$((ALLOWANCE - USED)); fi
  PCT=$(awk -v u="$USED" -v a="$ALLOWANCE" 'BEGIN { printf "%.1f", u / a * 100 }')
  USED_GB=$(fmt_gb "$USED")
  REMAIN_GB=$(fmt_gb "$REMAIN")
  UPDATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat > "$WWW/traffic.json.tmp" <<EOF
{"month": "$YM", "allowance_bytes": $ALLOWANCE, "used_bytes": $USED, "remaining_bytes": $REMAIN, "used_gb": $USED_GB, "remaining_gb": $REMAIN_GB, "percent": $PCT, "reset_utc": "$RESET", "updated_utc": "$UPDATED"}
EOF
  mv "$WWW/traffic.json.tmp" "$WWW/traffic.json"

  cat > "$WWW/index.html.tmp" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="60">
<meta name="color-scheme" content="light dark">
<title>Cloady 节点 · 剩余流量</title>
<style>
:root { color-scheme: light dark; --bg: #f6f4ef; --fg: #222; --card: #fff; --muted: #666; --line: #ddd; --accent: #2563eb; --track: #e5e5e5; }
@media (prefers-color-scheme: dark) { :root { --bg: #141414; --fg: #e8e8e8; --card: #1e1e1e; --muted: #aaa; --line: #333; --accent: #7aa7ff; --track: #333; } }
body { margin: 0; background: var(--bg); color: var(--fg); font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; line-height: 1.7; padding: 24px 16px 48px; }
.wrap { max-width: 560px; margin: 0 auto; }
h1 { font-weight: 300; letter-spacing: .06em; font-size: 26px; margin: 8px 0 4px; }
.sub { color: var(--muted); font-size: 14px; margin: 0 0 20px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 18px; margin: 16px 0; }
.big { font-size: 40px; font-weight: 300; letter-spacing: .02em; line-height: 1.2; }
.big small { font-size: 16px; color: var(--muted); }
.bar { height: 12px; border-radius: 6px; background: var(--track); overflow: hidden; margin: 12px 0 6px; }
.bar i { display: block; height: 100%; background: var(--accent); }
.row { display: flex; justify-content: space-between; font-size: 14px; color: var(--muted); }
.note { font-size: 13px; color: var(--muted); }
</style>
</head>
<body>
<div class="wrap">
<h1>剩余流量</h1>
<p class="sub">Cloady 节点 · xray-node · US West USW1</p>
<div class="card">
<div class="big">$REMAIN_GB <small>GB 剩余</small></div>
<div class="bar"><i style="width: $PCT%"></i></div>
<div class="row"><span>本月已用 $USED_GB GB（$PCT%）</span><span>额度 15 GB</span></div>
<div class="row"><span>本月 $YM</span><span>下次重置 $RESET</span></div>
</div>
<div class="card note">
<p>更新于 $UPDATED（每 60 秒刷新一次）。计数口径为容器出口流量，即 Cloady 计费的出站流量，含少量协议开销误差；官方到 90% 会发邮件提醒，超 100% 会停应用、次月 1 号才能再跑。容器重建会丢计数基线，巡检保留跨重启的月度累计用于阈值提醒。</p>
</div>
</div>
</body>
</html>
EOF
  mv "$WWW/index.html.tmp" "$WWW/index.html"
  sleep 60
done
