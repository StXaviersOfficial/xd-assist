#!/data/data/com.termux/files/usr/bin/bash
set -u
cd ~/xd
if [ ! -s .key ]; then echo "ERROR: no ~/xd/.key — ask the agent for the current key"; exit 1; fi
KEY="$(cat .key 2>/dev/null | tr -d '[:space:]')"
pkill -f 'supervisor-loop.sh' 2>/dev/null
pkill -f 'python.*server\.py' 2>/dev/null
pkill -f 'cloudflared tunnel' 2>/dev/null
sleep 1
BASE="https://raw.githubusercontent.com/StXaviersOfficial/xd-assist/main/termux"
for f in server.py supervisor-loop.sh; do
  curl -sfL -m 30 "$BASE/$f" -o "$f.new" && [ -s "$f.new" ] && mv "$f.new" "$f"
  rm -f "$f.new"
done
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
echo "[supervisor] starting (key ${KEY:0:6}...) — nohup + disown: survives Termux close"
nohup bash supervisor-loop.sh >> supervisor.log 2>&1 &
disown
echo "[supervisor] running. Logs: supervisor.log | bridge.log"
echo "[supervisor] stop: pkill -f supervisor-loop.sh; pkill -f 'python.*server.py'; pkill -f 'cloudflared tunnel'"
