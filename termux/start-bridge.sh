#!/data/data/com.termux/files/usr/bin/bash
# start-bridge.sh — xd-bridge SUPERVISOR (one command, runs forever)
#
# S25 REWRITE (2026-10-19) — two root-cause fixes for the overnight deaths:
#   1. the supervisor loop is now `nohup` + `disown`ed: closing the Termux
#      session used to SIGHUP cloudflared and the tunnel died with it
#   2. periodic re-registration: the current tunnel URL is re-POSTed to the
#      worker registry every 5 minutes, so registry age = real liveness
#      (the worker now surfaces honest 502s when the phone side is gone)
#
# What it does:
#   1. kills any old bridge/tunnel copies
#   2. refreshes server.py + supervisor-loop.sh from GitHub
#   3. spawns the nohup'd supervisor loop (server + cloudflared + register)
#
# Run:  cd ~/xd && bash start-bridge.sh
# (a wake-lock session from the original setup helps Termux survive doze)
set -u
cd ~/xd

if [ ! -s .key ]; then
  echo "ERROR: no ~/xd/.key — write your XD key there first:"
  echo "  echo -n 'XD-xxxx...' > ~/xd/.key"
  exit 1
fi
KEY="$(cat .key 2>/dev/null | tr -d '[:space:]')"

pkill -f 'supervisor-loop.sh' 2>/dev/null
pkill -f 'python server.py' 2>/dev/null
pkill -f 'cloudflared tunnel' 2>/dev/null
sleep 1

# S26: repo move — the XD Assist bridge now lives at StXaviersOfficial/xd-assist.
# curl -f (fail on HTTP error): WITHOUT it a 404 page would overwrite
# server.py with a "404: Not Found" body and brick the bridge silently.
RAW=https://raw.githubusercontent.com/StXaviersOfficial/xd-assist/main/termux
curl -sfLo server.py.new "$RAW/server.py" \
  && [ -s server.py.new ] \
  && python -c 'import ast,sys; ast.parse(open("server.py.new").read())' 2>/dev/null \
  && mv server.py.new server.py || { rm -f server.py.new; echo "[supervisor] server.py: kept existing copy (download failed/invalid)"; }
curl -sfLo supervisor-loop.sh.new "$RAW/supervisor-loop.sh" \
  && [ -s supervisor-loop.sh.new ] \
  && bash -n supervisor-loop.sh.new 2>/dev/null \
  && mv supervisor-loop.sh.new supervisor-loop.sh || { rm -f supervisor-loop.sh.new; echo "[supervisor] supervisor-loop.sh: kept existing copy (download failed/invalid)"; }

echo "[supervisor] starting (key ${KEY:0:6}...) — nohup + disown: survives Termux close"
nohup bash supervisor-loop.sh >> supervisor.log 2>&1 &
disown
echo "[supervisor] running. Logs: supervisor.log | bridge.log"
echo "[supervisor] stop: pkill -f supervisor-loop.sh; pkill -f 'python server.py'; pkill -f 'cloudflared tunnel'"
