# XD Assist — device rig bridge for the owner's phone

Companion project to **XavierDrive** (`StXaviersOfficial/stxaviers-android`).
It lives in its own repository on purpose: XD Assist is *not part of the
school app* — it is the remote-control rig (screen + shell) for the owner's
own device. Keeping it separate means code sweeps of the XavierDrive app
never touch (or mistake) rig code, and vice versa.

## What it is

| Piece | Where | Runs on | What it does |
|---|---|---|---|
| **XD Assist app** | `app/` | The phone (Android) | Accessibility service that polls the worker's `/rig/next-cmd` and executes screen commands (tap / swipe / type / dump / open / back / home). Key-authenticated with the XD key. |
| **Termux bridge** | `termux/` | The phone (Termux) | `server.py` (localhost:25570) exposing `/exec`, `/fs/*`, `/rig/*` behind `X-Backend-Key`, plus a cloudflared tunnel with a **self-healing supervisor** that re-registers every tunnel URL with the worker registry — tunnel URLs never get pasted anywhere. |
| **Worker proxy** | *not in this repo* | Cloudflare | `xd-bridge` permanent device bridge at `https://xd-bridge.quackeditzofficial.workers.dev` — key-gated proxy that forwards `/exec`, `/fs/*`, `/rig/*` to whatever tunnel URL is currently registered (KV tunnel registry). The school worker (`stxaviers-auth`) is retired for device-bridge use. |

The two phone-side pieces talk to the same worker and share the same XD key,
so one command revives everything: `cd ~/xd && bash start-bridge.sh`.

## Layout

```
app/                XD Assist APK source (com.stxaviers.assist)
  AndroidManifest.xml
  build-assist.sh     flat aapt2/javac/d8/apksigner pipeline (no Gradle)
  res/  src/
termux/             Phone-side bridge (Termux)
  SETUP.md            the owner's command list (start here)
  server.py           bridge server — /exec, /fs/*, /rig/*
  start-bridge.sh     ONE command: kills old procs, self-updates from this
                      repo (curl -f + syntax-checked), spawns supervisor
  supervisor-loop.sh  nohup'd loop: keeps server + cloudflared alive,
                      re-registers the tunnel URL every 5 min
```

## Building the app

```bash
cd app && bash build-assist.sh
# env overrides if your SDK/JDK/keystore live elsewhere:
# ANDROID_SDK=... JAVA17_HOME=... XD_KEYSTORE=... XD_KEYSTORE_PASS=... bash build-assist.sh
```

Output: `app/build/xdassist-<version>.apk` (release-signed with the
`stxaviers-upload` key). Binaries are **never committed to this repo** —
release APKs ship via the update channel (Cloudflare Pages + worker
`APP_LATEST`), not via Git.

## Security notes

- Every hop (app → worker → tunnel → server.py) requires the XD key via
  `X-Device-Key` / `X-Backend-Key`; the bridge **refuses to start** without it.
- `server.py` clamps filesystem access to Termux home + shared storage,
  bounds queued rig results, and returns clean 4xx errors.
- `start-bridge.sh` verifies downloads before swapping them in
  (`curl -f` + `ast.parse` / `bash -n` guards) — a broken upstream can no
  longer brick the bridge with a 404 page.
