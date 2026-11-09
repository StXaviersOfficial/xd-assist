#!/usr/bin/env python3
# xdclient.py — XD Bridge v2 phone client (Termux, pure STDLIB, no key).
#
# Replaces the old server.py + cloudflared tunnel stack entirely: this one
# process holds a WebSocket to the permanent Cloudflare worker
# (xd-bridge.quackeditzofficial.workers.dev) and executes whatever the
# agent sends — shell commands and file ops. Screen control (RIG) runs
# through the same worker but is handled by the XD Assist app, not us.
#
# No key. No tunnel. No cloudflared. It reconnects forever.
import base64
import json
import os
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse

WORKER = "wss://xd-bridge.quackeditzofficial.workers.dev/device-ws"
HOME = os.path.expanduser("~")
SHARED = os.path.join(HOME, "storage", "shared")
PING_EVERY = 25          # keep the Cloudflare websocket alive (idle cutoff ~60-100s)
READ_CHUNK = 65536


def log(msg):
    print("[%s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


# ── path rules (same as the old server.py) ──────────────────────────────
def resolve(path):
    if not path:
        raise ValueError("empty path")
    if path == "home":
        return HOME
    if path.startswith("home/"):
        return os.path.normpath(os.path.join(HOME, path[len("home/"):]))
    if path == "shared":
        return SHARED if os.path.isdir(SHARED) else HOME
    if path.startswith("shared/"):
        return os.path.normpath(os.path.join(SHARED, path[len("shared/"):]))
    if path.startswith("abs/"):
        return os.path.normpath(path[len("abs/"):])
    raise ValueError("path must start with home/ shared/ or abs/")


# ── websocket client (RFC 6455, client side only, stdlib only) ─────────
class WS:
    def __init__(self, url):
        u = urlparse(url)
        self.host = u.hostname
        self.port = u.port or (443 if u.scheme == "wss" else 80)
        self.path = (u.path or "/") + ("?" + u.query if u.query else "")
        self.tls = u.scheme == "wss"
        self.sock = None
        self.buf = b""

    def connect(self, timeout=25):
        raw = socket.create_connection((self.host, self.port), timeout=timeout)
        raw.settimeout(timeout)
        if self.tls:
            ctx = ssl.create_default_context()
            self.sock = ctx.wrap_socket(raw, server_hostname=self.host)
        else:
            self.sock = raw
        key = base64.b64encode(os.urandom(16)).decode()
        req = ("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n"
               "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
               "Sec-WebSocket-Version: 13\r\nUser-Agent: XDClient/2.0 (Termux)\r\n\r\n"
               % (self.path, self.host, key))
        self.sock.sendall(req.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("closed during handshake")
            head += chunk
        status = head.split(b"\r\n", 1)[0].decode(errors="replace")
        if " 101 " not in status:
            raise ConnectionError("handshake rejected: " + status)
        _, _, rest = head.partition(b"\r\n\r\n")
        self.buf = rest

    def _read_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(READ_CHUNK)
            if not chunk:
                raise ConnectionError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _send_frame(self, opcode, payload):
        mask = os.urandom(4)
        header = bytearray([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def send_text(self, text):
        self._send_frame(0x1, text.encode("utf-8"))

    def send_pong(self, data=b""):
        self._send_frame(0xA, data)

    def recv_text(self):
        """Blocks; returns a str. Answers server pings transparently.
        Raises socket.timeout (caller sends its own ping) or ConnectionError."""
        frag = b""
        frag_op = None
        while True:
            h = self._read_exact(2)
            fin = h[0] & 0x80
            opcode = h[0] & 0x0F
            masked = h[1] & 0x80
            ln = h[1] & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._read_exact(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if masked else None
            data = self._read_exact(ln) if ln else b""
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x9:              # server ping → pong
                self.send_pong(data)
                continue
            if opcode == 0xA:              # pong (our keepalive answered)
                continue
            if opcode == 0x8:              # close
                raise ConnectionError("server sent close frame")
            if opcode in (0x1, 0x2):
                if fin:
                    return data.decode("utf-8", "replace")
                frag, frag_op = data, opcode
                continue
            if opcode == 0x0:              # continuation
                frag += data
                if fin:
                    return frag.decode("utf-8", "replace")
                continue
            # unknown opcode — skip


# ── command handlers ────────────────────────────────────────────────────
def op_exec(m):
    cmd = str(m.get("cmd", ""))
    tmo = int(m.get("timeout", 30))
    if not cmd:
        return {"id": m.get("id"), "ok": False, "error": "no cmd"}
    try:
        p = subprocess.run(["bash", "-lc", cmd], capture_output=True,
                           text=True, timeout=tmo)
        return {"id": m.get("id"), "ok": p.returncode == 0,
                "code": p.returncode, "out": p.stdout, "err": p.stderr}
    except subprocess.TimeoutExpired:
        return {"id": m.get("id"), "ok": False, "code": -1,
                "error": "command timed out after %ss" % tmo}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "code": -1, "error": str(e)}


def op_fs_list(m):
    try:
        real = resolve(m.get("path", "shared"))
        entries = []
        for name in sorted(os.listdir(real)):
            full = os.path.join(real, name)
            try:
                st = os.stat(full)
                entries.append({"name": name, "dir": os.path.isdir(full),
                                "size": st.st_size, "mtime": int(st.st_mtime)})
            except Exception:
                entries.append({"name": name, "dir": None, "size": 0, "mtime": 0})
        return {"id": m.get("id"), "ok": True, "real": real, "entries": entries}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "error": str(e)}


def op_fs_read(m):
    try:
        real = resolve(m.get("path", ""))
        with open(real, "rb") as f:
            data = f.read()
        if len(data) > 900 * 1024:
            return {"id": m.get("id"), "ok": False,
                    "error": "file >900KB — too large for the WS bridge"}
        return {"id": m.get("id"), "ok": True, "b64": base64.b64encode(data).decode(),
                "size": len(data)}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "error": str(e)}


def op_fs_write(m):
    try:
        real = resolve(m.get("path", ""))
        data = base64.b64decode(m.get("b64", ""))
        os.makedirs(os.path.dirname(real), exist_ok=True)
        with open(real, "wb") as f:
            f.write(data)
        return {"id": m.get("id"), "ok": True, "size": len(data), "real": real}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "error": str(e)}


def op_fs_mkdir(m):
    try:
        real = resolve(m.get("path", ""))
        os.makedirs(real, exist_ok=True)
        return {"id": m.get("id"), "ok": True, "real": real}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "error": str(e)}


def op_fs_delete(m):
    try:
        real = resolve(m.get("path", ""))
        if os.path.isdir(real):
            shutil.rmtree(real)
        else:
            os.remove(real)
        return {"id": m.get("id"), "ok": True}
    except Exception as e:
        return {"id": m.get("id"), "ok": False, "error": str(e)}


HANDLERS = {
    "exec": op_exec,
    "fs_list": op_fs_list,
    "fs_read": op_fs_read,
    "fs_write": op_fs_write,
    "fs_mkdir": op_fs_mkdir,
    "fs_delete": op_fs_delete,
}


def handle(m):
    h = HANDLERS.get(m.get("op"))
    if not h:
        return {"id": m.get("id"), "ok": False, "error": "unknown op: %s" % m.get("op")}
    return h(m)


# ── main loop ───────────────────────────────────────────────────────────
def worker(ws, replies):
    """Runs commands in threads so long execs never stall the ping loop."""
    def run(m):
        try:
            r = handle(m)
        except Exception as e:
            r = {"id": m.get("id"), "ok": False, "error": "handler crashed: %s" % e}
        replies.append(json.dumps(r))
    while True:
        m = QUEUE.pop(0) if QUEUE else None
        if not m:
            time.sleep(0.15)
            continue
        threading.Thread(target=run, args=(m,), daemon=True).start()


QUEUE = []


def main():
    try:
        subprocess.run(["termux-wake-lock"], capture_output=True, timeout=10)
        log("wake lock acquired")
    except Exception:
        log("no termux-wake-lock (fine)")
    backoff = 3
    while True:
        ws = WS(WORKER)
        try:
            ws.connect()
            backoff = 3
            log("CONNECTED to %s — bridge is live (no key needed)" % WORKER)
            replies = []
            threading.Thread(target=worker, args=(ws, replies), daemon=True).start()
            last_ping = time.time()
            while True:
                # drain handler replies first
                while replies:
                    ws.send_text(replies.pop(0))
                try:
                    ws.sock.settimeout(2)
                    msg = ws.recv_text()
                except socket.timeout:
                    msg = None
                if msg is None:
                    if time.time() - last_ping >= PING_EVERY:
                        ws.send_text("ping")
                        last_ping = time.time()
                    continue
                if msg in ("pong", "ping"):
                    continue
                if msg.startswith("{"):
                    QUEUE.append(json.loads(msg))
        except Exception as e:
            log("connection lost: %s — reconnecting in %ss" % (e, backoff))
            try:
                ws.sock.close()
            except Exception:
                pass
            time.sleep(backoff)
            backoff = min(backoff * 2, 30)


if __name__ == "__main__":
    log("XD Bridge client v2.0 starting (pid %d)" % os.getpid())
    main()
