# xd-assist — XD Assist (keyless v1.1.0) + the v2 Termux bridge client

## What changed on 2026-11-09 (owner order: remove the entire key function)

- **The key system is completely gone.** No X-Backend-Key, no X-Device-Key,
  no DEVICE_KEY secret. Every endpoint on the permanent worker is open.
- **The cloudflared trycloudflare tunnel is gone.** The Termux client
  (`termux/xdclient.py`, pure Python stdlib) holds one WebSocket to the
  permanent Cloudflare worker and executes shell + file commands.
- **Screen control (RIG)** is served by the worker from a D1 queue
  (strongly consistent — ~1-3s command pickup).
- The app (v1.1.0) has no settings at all: install, enable accessibility,
  done. It only ever talks to `https://xd-bridge.quackeditzofficial.workers.dev`.

## Owner quick start (Termux)

    curl -sfL https://raw.githubusercontent.com/StXaviersOfficial/xd-assist/main/termux/start.sh | bash

That command: stops the old stack, downloads `xdclient.py`, starts it in the
background with a wake lock, and drops `xdassist-1.1.0.apk` into `Download/`.

## Layout

- `app/` — the XD Assist Android app (flat aapt2/javac/d8 build, no Gradle)
- `termux/xdclient.py` — the v2 phone client (websocket, keyless)
- `termux/start.sh` — the one-line launcher
- `termux/server.py`, `termux/supervisor-loop.sh` — the OLD v1 stack
  (HTTP server + cloudflared tunnel + key), kept for history only
