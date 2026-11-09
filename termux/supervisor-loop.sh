#!/data/data/com.termux/files/usr/bin/bash
set -u
cd ~/xd
WORKER="https://xd-bridge.quackeditzofficial.workers.dev"
KEY="$(cat .key 2>/dev/null | tr -d '[:space:]')"
if [ -z "$KEY" ]; then echo "[supervisor] no .key — exiting"; exit 1; fi

reg() {
  local u="$1"
  [ -n "$u" ] || return 0
  curl -s -m 10 -X POST -H "X-Device-Key: $KEY" -H "Content-Type: application/json" -d "{\"url\":\"$u\"}" "$WORKER/internal/device-tunnel" >/dev/null 2>&1 && touch tunnel.reg && echo "[supervisor] registered $u $(date)"
}

echo "[supervisor] loop started $(date)"
while true; do
  if ! curl -s -m 3 http://127.0.0.1:25570/health >/dev/null 2>&1; then
    pkill -f 'python.*server\.py' 2>/dev/null
    sleep 1
    nohup env XD_KEY="$KEY" python server.py >>bridge.log 2>&1 &
    sleep 2
  fi
  if [ -s tunnel.url ]; then
    NOW=$(date +%s); LASTREG=$(stat -c %Y tunnel.reg 2>/dev/null || echo 0)
    if [ $((NOW - LASTREG)) -ge 240 ]; then reg "$(cat tunnel.url)"; fi
  fi
  timeout 1800 cloudflared tunnel --url http://127.0.0.1:25570 2>&1 | grep --line-buffered -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | while read -r U; do [ -n "$U" ] && { echo "$U" > tunnel.url; reg "$U"; }; done
  sleep 3
done
