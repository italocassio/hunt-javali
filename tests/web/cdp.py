"""Minimal Chrome DevTools Protocol client (stdlib only): hand-written WebSocket + CDP helpers.

Used by tests/web/mobile_probe.py. No third-party packages.
"""
import base64
import http.server
import json
import os
import socket
import struct
import subprocess
import threading
import time
import urllib.request
import functools

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


# ---------------------------------------------------------------------------
# Static server
# ---------------------------------------------------------------------------

class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
        ".html": "text/html",
    }

    def log_message(self, *args):
        pass


class StaticServer:
    def __init__(self, directory: str, port: int = 0):
        handler = functools.partial(_QuietHandler, directory=directory)
        class _Server(http.server.ThreadingHTTPServer):
            def handle_error(self, request, client_address):
                pass   # the browser aborts transfers on page reload; not interesting

        self.httpd = _Server(("127.0.0.1", port), handler)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        try:
            self.httpd.shutdown()
            self.httpd.server_close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# WebSocket client
# ---------------------------------------------------------------------------

class WebSocket:
    def __init__(self, host: str, port: int, path: str):
        self.sock = socket.create_connection((host, port), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("handshake closed")
            buf += chunk
        head, _, rest = buf.partition(b"\r\n\r\n")
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise ConnectionError("handshake failed: " + head.decode(errors="replace"))
        self._buf = rest
        self.sock.settimeout(None)
        self._send_lock = threading.Lock()

    def _read_exact(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                raise ConnectionError("socket closed")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def send_text(self, text: str):
        payload = text.encode()
        header = bytearray([0x81])
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        with self._send_lock:
            self.sock.sendall(bytes(header) + masked)

    def _send_control(self, opcode: int, payload: bytes = b""):
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        with self._send_lock:
            self.sock.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)

    def recv_text(self) -> str:
        message = b""
        while True:
            b0, b1 = self._read_exact(2)
            fin = b0 & 0x80
            opcode = b0 & 0x0F
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read_exact(8))[0]
            if b1 & 0x80:
                mask = self._read_exact(4)
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(self._read_exact(length)))
            else:
                data = self._read_exact(length)
            if opcode == 0x9:
                self._send_control(0xA, data)
                continue
            if opcode == 0x8:
                raise ConnectionError("closed by peer")
            if opcode in (0x1, 0x0, 0x2):
                message += data
                if fin:
                    return message.decode()

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# CDP session
# ---------------------------------------------------------------------------

class Cdp:
    def __init__(self, ws: WebSocket):
        self.ws = ws
        self._id = 0
        self._pending = {}
        self._cv = threading.Condition()
        self.events = []          # (method, params) of everything received
        self.console = []         # formatted console / log lines
        self._alive = True
        self._thread = threading.Thread(target=self._reader, daemon=True)
        self._thread.start()

    def _reader(self):
        while self._alive:
            try:
                msg = json.loads(self.ws.recv_text())
            except Exception:
                break
            with self._cv:
                if "id" in msg:
                    self._pending[msg["id"]] = msg
                else:
                    method = msg.get("method", "")
                    params = msg.get("params", {})
                    self.events.append((method, params))
                    self._collect_console(method, params)
                self._cv.notify_all()

    def _collect_console(self, method, params):
        t = round(time.time() % 100000, 2)
        if method == "Runtime.consoleAPICalled":
            parts = []
            for a in params.get("args", []):
                parts.append(str(a.get("value", a.get("description", a.get("type")))))
            self.console.append(f"[{t}] console.{params.get('type')}: " + " ".join(parts))
        elif method == "Log.entryAdded":
            e = params.get("entry", {})
            self.console.append(f"[{t}] log.{e.get('level')}: {e.get('text')} {e.get('url', '')}")
        elif method == "Runtime.exceptionThrown":
            d = params.get("exceptionDetails", {})
            self.console.append(f"[{t}] EXCEPTION: {d.get('text')} {d.get('exception', {}).get('description', '')}")

    def call(self, method: str, params: dict = None, timeout: float = 120.0):
        with self._cv:
            self._id += 1
            mid = self._id
        self.ws.send_text(json.dumps({"id": mid, "method": method, "params": params or {}}))
        deadline = time.time() + timeout
        with self._cv:
            while mid not in self._pending:
                left = deadline - time.time()
                if left <= 0:
                    raise TimeoutError(f"CDP timeout: {method}")
                self._cv.wait(left)
            msg = self._pending.pop(mid)
        if "error" in msg:
            raise RuntimeError(f"CDP error in {method}: {msg['error']}")
        return msg.get("result", {})

    def close(self):
        self._alive = False
        self.ws.close()


def free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class ChromeProc:
    def __init__(self, user_data_dir: str, debug_port: int):
        self.port = debug_port
        args = [CHROME, "--headless=new", f"--remote-debugging-port={debug_port}",
                f"--user-data-dir={user_data_dir}", "--enable-unsafe-swiftshader",
                "--ignore-gpu-blocklist", "--no-first-run", "--no-default-browser-check",
                "--autoplay-policy=no-user-gesture-required", "about:blank"]
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def connect(self, timeout: float = 30.0) -> Cdp:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/json", timeout=2) as r:
                    targets = json.loads(r.read())
                pages = [t for t in targets if t.get("type") == "page"]
                if pages:
                    path = pages[0]["webSocketDebuggerUrl"].split(f":{self.port}", 1)[1]
                    return Cdp(WebSocket("127.0.0.1", self.port, path))
            except Exception:
                pass
            time.sleep(0.5)
        raise TimeoutError("Chrome did not expose a page target")

    def kill(self):
        try:
            subprocess.run(["taskkill", "/PID", str(self.proc.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        except Exception:
            pass
        try:
            self.proc.kill()
        except Exception:
            pass
