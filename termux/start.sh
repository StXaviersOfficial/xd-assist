#!/data/data/com.termux/files/usr/bin/bash
# start.sh — XD Bridge v2 launcher (KEYLESS, no tunnel, no cloudflared).
# One-liner for the owner:
#   curl -sfL https://raw.githubusercontent.com/StXaviersOfficial/xd-assist/main/termux/start.sh | bash
set -u

APK_URL="https://raw.githubusercontent.com/StXaviersOfficial/xd-delivery/main/xdassist-1.1.0.apk"
BASE="https://raw.githubusercontent.com/StXaviersOfficial/xd-assist/main/termux"

mkdir -p ~/xd && cd ~/xd

echo "[start] XD Bridge v2 (keyless) — stopping the old stack…"
pkill -f 'supervisor-loop.sh' 2>/dev/null
pkill -f 'python.*server\.py' 2>/dev/null
pkill -f 'cloudflared tunnel' 2>/dev/null
pkill -f 'xdclient\.py' 2>/dev/null
sleep 1

command -v python >/dev/null 2>&1 || { echo "[start] installing python…"; pkg install -y python >/dev/null 2>&1 || { echo "[start] pkg install python failed — run: pkg install python"; exit 1; }; }

echo "[start] downloading the new keyless client…"
curl -sfL -m 60 "$BASE/xdclient.py" -o xdclient.py.new && [ -s xdclient.py.new ] && mv xdclient.py.new xdclient.py || { echo "[start] download failed — check internet and retry"; exit 1; }

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock

# also drop the new keyless XD Assist APK into Download for a quick install
if [ -d ~/storage/shared/Download ]; then
  echo "[start] fetching the new XD Assist 1.1.0 APK into Download…"
  curl -sfL -m 300 "$APK_URL" -o ~/storage/shared/Download/xdassist-1.1.0.apk \
    && echo "[start] APK saved: Download/xdassist-1.1.0.apk (install it — it replaces the old app, no key anymore)" \
    || echo "[start] (APK download skipped — ask the agent for it once the bridge is up)"
fi

echo "[start] launching the bridge (background; survives Termux close)…"
nohup python xdclient.py >> bridge.log 2>&1 &
disown
sleep 5
echo "[start] last log lines:"
tail -n 6 bridge.log 2>/dev/null
echo "[start] done — no key needed anymore. Logs: ~/xd/bridge.log | stop: pkill -f xdclient.py"
