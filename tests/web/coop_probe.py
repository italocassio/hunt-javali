"""Co-op WebRTC probe (docs/multiplayer.md section 9, F2/F3/F6): two real Chrome instances play the real Web build.

    python tests/web/coop_probe.py [--scenarios=rtc,drop_ice,invite,server_unreachable,invite_unknown,shop_in_room] [--build-dir=DIR]
                                   [--load-timeout=S] [--keep] [--help]

What it does, end to end
  1. exports the Web build with tools/godot.sh into a TEMP directory (never build/web), unless --build-dir=DIR
     points at an existing export;
  2. serves it over HTTP on 127.0.0.1 and starts the local Bun room server (server/server.js) on a free port;
  3. opens two Chrome instances (own profile each) on
        http://127.0.0.1:<port>/index.html?probe=1&server=ws://127.0.0.1:<bun_port>/ws[&drop_ice=1]
     (no ?mp=1: since F6 the "Jogar com amigos (beta)" button is always in the menu);
     A: menu -> "Jogar com amigos (beta)" -> "Criar sala" (code read from the server's `created` frame, mirrored by
     a WebSocket hook in the page); B: types the code -> "Entrar" (or opens the invite link, see `invite`);
     A: "Iniciar cacada" must NOT start the hunt while B has not pressed "Pronto"; B: "Pronto"; A: "Iniciar cacada"
     until the hunt loads;
  4. both walk (W key) and stop; window.huntProbe (src/hud/hud.gd) is read in each page.

Scenarios
  rtc       acceptance: huntProbe.path == "rtc" on both; allies[0] of the viewer is within 1 m of the walker's real
            position 2 s after it stopped, A seen by B and B seen by A (walk distance and "viewer saw it move" are
            checked too, so a passing run cannot be vacuous). Also: the relay carries (almost) no state frames
            once on RTC.
  drop_ice  `&drop_ice=1` on both pages (candidates are never sent): the link must stay "relay" after
            ice_timeout_s (data/net.json), no RTCPeerConnection may reach connected/completed, relay frames keep
            flowing, and the same position criterion passes over the relay. A failure here that comes from the ICE
            deadline itself is F3 work (section 9, F3), reported as such.
  invite    F6: A creates the room; B opens `?sala=<code in lower case>&probe=1&server=...` and, after the boot tap,
            lands in the lobby and joins WITHOUT typing the code (the join frame the page sends carries it); then
            the same ready/start/walk checks as `rtc` (without the path assertions).
  server_unreachable
            F6: the page points `?server=` at a port nobody listens on. "Criar sala" must show the
            `server_unreachable` message (red text, found by pixel colour: the lobby is a canvas) in <= 9 s, "Voltar"
            must lead back to the menu, and entering the lobby again must not show a stale message.
  invite_unknown
            F6 edge: `?sala=zzzzz` (no such room, live server): the lobby shows the `room_not_found` message by itself
            in <= 9 s and "Voltar" goes to the menu.
  shop_in_room
            F6 edge: a client that is READY opens "Loja" from the room, then the host presses "Iniciar cacada". Both
            pages must reach the hunt (or the host must be blocked); a stranded client is a bug.
  Not covered here (no way to do it from the browser, reported instead): the spectator. Nothing in the Web build
  kills the local hunter on demand (no JavaScriptBridge hook) and window.huntProbe has no spectating field; the
  spectator is covered by src/player/debug/spectator_sandbox.tscn (tests/net_unit.tscn).

Every Chrome, the HTTP server and Bun are killed on every way out (success, failure, exception, Ctrl+C); the temp
directory with the export and the Chrome profiles is deleted. Screenshots (always) go to <tmp>/shots; the folder is
kept and printed when something fails or with --keep.  Exit code 0 only if every expectation holds.
Chrome gets --disable-features=WebRtcHideLocalIpsWithMdns so host candidates carry real addresses (two instances on
one machine cannot resolve each other's mDNS names) and focus emulation so a page never auto-pauses on blur.
Stdlib only; needs Chrome (tests/web/cdp.py:CHROME), Bun (PATH, $BUN or ~/.bun/bin) and Godot (tools/godot.sh).
"""
import atexit
import base64
import json
import math
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imgdiff  # noqa: E402
from cdp import CHROME, Cdp, StaticServer, WebSocket, free_port  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NET_JSON = os.path.join(ROOT, "data", "net.json")

# --- page geometry (CSS px). The game viewport is 720 tall (stretch aspect=expand): scale = H / 720.
W, H = 960, 540
SCALE = H / 720.0
BOOT_TAP = (W / 2, H / 2)                 # "Toque para comecar": anywhere
MENU_FRIENDS = (247, 296)                 # "Jogar com amigos (beta)"
LOBBY_CREATE = (292, 295)                 # "Criar sala"
LOBBY_CODE = (667, 228)                   # code field
LOBBY_JOIN = (667, 291)                   # "Entrar"
LOBBY_BACK = (105, 492)                   # "Voltar" (entry screen only)
ROOM_START = (802, 488)                   # "Iniciar cacada" (host) ...
ROOM_SHOP = (282, 488)                    # "Loja" in the room footer
ROOM_READY = (802, 488)                   # ... and "Pronto" (client): the same button slot of the footer

# --- timing / criteria
LOAD_TIMEOUT_S = 120.0
STEP_TIMEOUT_S = 40.0
WALK_S = 1.5
SETTLE_S = 2.0                            # stopped for this long before the positions are compared
MAX_ERROR_M = 1.0                         # F2 acceptance
MIN_WALK_M = 1.0
RTC_EXTRA_WAIT_S = 20.0                   # on top of ice_timeout_s, to reach path == "rtc"
KEY_W = ("KeyW", 87)

# --- F6: the error message of the lobby (UiKit.DANGER_COLOR, 0.851/0.271/0.169) is the only red text on the entry screen
MESSAGE_RGB = (217, 69, 43)
MESSAGE_TOL = 30
MESSAGE_MIN_PX = 100                      # the shortest message (room_not_found) has a few hundred; the idle screen has 0
MESSAGE_DEADLINE_S = 9.0                  # docs/multiplayer.md F6 acceptance
SCENARIOS = ("rtc", "drop_ice", "invite", "server_unreachable", "invite_unknown", "shop_in_room")

RESULTS = []
CLEANUP = []                              # callables run on every way out, most recent first


def log(msg):
    print(msg, flush=True)


def record(name, ok, measured, note=""):
    RESULTS.append({"test": name, "ok": bool(ok), "measured": measured, "note": note})
    log(f"  [{'OK ' if ok else 'FAIL'}] {name}: {measured}" + (f"  ({note})" if note else ""))


def run_cleanup():
    while CLEANUP:
        fn = CLEANUP.pop()
        try:
            fn()
        except Exception:
            pass


atexit.register(run_cleanup)


def kill_tree(proc):
    """Kills a process and everything it started (Chrome spawns many; Bun is one process)."""
    if proc is None:
        return
    try:
        if proc.poll() is None:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=20)
            proc.kill()
    except Exception:
        pass
    try:
        proc.wait(timeout=10)
    except Exception:
        pass


# --- page hooks ---------------------------------------------------------------------------------
# Mirrors every text frame (both directions) and counts binary frames of every WebSocket the page opens, and
# keeps every RTCPeerConnection, so the probe can read the room code and prove which path carried the traffic.
HOOK_JS = r"""
(() => {
  window.__ws = {urls: [], rx: [], tx: [], bin_rx: 0, bin_rx_bytes: 0, bin_tx: 0, closes: []};
  const OW = window.WebSocket;
  class Spy extends OW {
    constructor(...a) {
      super(...a);
      window.__ws.urls.push(String(a[0]));
      this.addEventListener('message', (e) => {
        if (typeof e.data === 'string') { if (window.__ws.rx.length < 500) window.__ws.rx.push(e.data); }
        else { window.__ws.bin_rx++; window.__ws.bin_rx_bytes += (e.data.byteLength || e.data.size || 0); }
      });
      this.addEventListener('close', (e) => window.__ws.closes.push(e.code));
    }
    send(d) {
      if (typeof d === 'string') { if (window.__ws.tx.length < 500) window.__ws.tx.push(d); }
      else window.__ws.bin_tx++;
      return super.send(d);
    }
  }
  window.WebSocket = Spy;
  window.__pcs = [];
  const OP = window.RTCPeerConnection;
  if (OP) {
    window.RTCPeerConnection = class extends OP {
      constructor(...a) { super(...a); window.__pcs.push(this); window.__pcs_ever = (window.__pcs_ever || []); }
    };
  }
  window.__pc_summary = () => window.__pcs.map(pc => ({conn: pc.connectionState, ice: pc.iceConnectionState,
                                                         sig: pc.signalingState}));
  window.__pc_ever_connected = false;
  setInterval(() => {
    for (const pc of window.__pcs) {
      if (pc.connectionState === 'connected' || pc.iceConnectionState === 'connected' ||
          pc.iceConnectionState === 'completed') window.__pc_ever_connected = true;
    }
  }, 50);
})();
"""


class Browser:
    """One headless Chrome (own profile) driven over CDP."""

    def __init__(self, name, workdir, shots_dir):
        self.name = name
        self.shots_dir = shots_dir
        self.shot_n = 0
        self.profile = os.path.join(workdir, "profile_" + name)
        os.makedirs(self.profile, exist_ok=True)
        self.port = free_port()
        args = [CHROME, "--headless=new", f"--remote-debugging-port={self.port}", f"--user-data-dir={self.profile}",
                "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-first-run",
                "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required",
                "--disable-features=WebRtcHideLocalIpsWithMdns",
                "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                "--disable-backgrounding-occluded-windows", f"--window-size={W},{H}", "about:blank"]
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        CLEANUP.append(self.close)
        self.cdp = None
        self._last_t = -1

    def connect(self, timeout=30.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/json", timeout=2) as r:
                    targets = json.loads(r.read())
                pages = [t for t in targets if t.get("type") == "page"]
                if pages:
                    path = pages[0]["webSocketDebuggerUrl"].split(f":{self.port}", 1)[1]
                    self.cdp = Cdp(WebSocket("127.0.0.1", self.port, path))
                    break
            except Exception:
                pass
            time.sleep(0.5)
        if self.cdp is None:
            raise TimeoutError(f"Chrome {self.name} did not expose a page target")
        c = self.cdp
        for domain in ("Page", "Runtime", "Log"):
            c.call(f"{domain}.enable")
        c.call("Emulation.setDeviceMetricsOverride", {"width": W, "height": H, "deviceScaleFactor": 1, "mobile": False})
        c.call("Emulation.setFocusEmulationEnabled", {"enabled": True})
        c.call("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK_JS})

    def close(self):
        try:
            if self.cdp:
                self.cdp.close()
        except Exception:
            pass
        kill_tree(self.proc)
        time.sleep(0.5)
        shutil.rmtree(self.profile, ignore_errors=True)

    # -- page ---------------------------------------------------------------------
    def navigate(self, url):
        self.cdp.call("Page.navigate", {"url": url})

    def js(self, expr, await_promise=False):
        r = self.cdp.call("Runtime.evaluate", {"expression": expr, "returnByValue": True,
                                               "awaitPromise": await_promise})
        return r.get("result", {}).get("value")

    def wait_loaded(self, timeout=None):
        end = time.time() + (LOAD_TIMEOUT_S if timeout is None else timeout)
        while time.time() < end:
            ok = self.js("""(()=>{const s=document.getElementById('status');
                const c=document.getElementById('canvas');
                return !!c && c.width>0 && (!s || getComputedStyle(s).visibility==='hidden');})()""")
            if ok:
                return True
            time.sleep(0.5)
        return False

    def shot(self, label):
        self.shot_n += 1
        try:
            r = self.cdp.call("Page.captureScreenshot", {"format": "jpeg", "quality": 70}, timeout=30)
            path = os.path.join(self.shots_dir, f"{self.name}_{self.shot_n:02d}_{label}.jpg")
            with open(path, "wb") as f:
                f.write(base64.b64decode(r["data"]))
        except Exception:
            pass

    def png(self):
        """Screenshot as decoded PNG rows (w, h, channels, rows); None if the capture failed."""
        try:
            r = self.cdp.call("Page.captureScreenshot", {"format": "png"}, timeout=30)
            return imgdiff.decode_png(base64.b64decode(r["data"]))
        except Exception:
            return None

    def count_color(self, rgb, tol=40, box=None):
        """Pixels within `tol` per channel of `rgb` (optionally inside box=(x0,y0,x1,y1)); -1 if no capture."""
        img = self.png()
        if img is None:
            return -1
        w, h, ch, rows = img
        x0, y0, x1, y1 = box or (0, 0, w, h)
        n = 0
        for y in range(max(y0, 0), min(y1, h)):
            line = rows[y]
            for x in range(max(x0, 0), min(x1, w)):
                o = x * ch
                if abs(line[o] - rgb[0]) <= tol and abs(line[o + 1] - rgb[1]) <= tol and abs(line[o + 2] - rgb[2]) <= tol:
                    n += 1
        return n

    def console(self, n=12):
        return self.cdp.console[-n:]

    # -- input ----------------------------------------------------------------------
    def click(self, x, y):
        for kind in ("mouseMoved", "mousePressed", "mouseReleased"):
            self.cdp.call("Input.dispatchMouseEvent", {
                "type": kind, "x": x, "y": y, "button": "none" if kind == "mouseMoved" else "left",
                "buttons": 1 if kind == "mousePressed" else 0, "clickCount": 1})
            time.sleep(0.06)

    def key(self, down, code, vk, text=None, key=None):
        params = {"type": "keyDown" if down else "keyUp", "code": code, "windowsVirtualKeyCode": vk,
                  "key": key or code.replace("Key", "").replace("Digit", "")}
        if down and text:
            params["text"] = text
        self.cdp.call("Input.dispatchKeyEvent", params)

    def type_text(self, text):
        for ch in text:
            vk = ord(ch.upper())
            code = ("Digit" if ch.isdigit() else "Key") + ch.upper()
            self.key(True, code, vk, text=ch, key=ch)
            time.sleep(0.04)
            self.key(False, code, vk, key=ch)
            time.sleep(0.04)

    # -- observation ------------------------------------------------------------------
    def probe(self):
        raw = self.js("window.huntProbe ? JSON.stringify(window.huntProbe) : null")
        return json.loads(raw) if raw else None

    def fresh_probe(self, timeout=3.0):
        """Waits for a publish newer than the last one this browser returned."""
        end = time.time() + timeout
        st = None
        while time.time() < end:
            st = self.probe()
            if st and st["t_ms"] != self._last_t:
                self._last_t = st["t_ms"]
                return st
            time.sleep(0.05)
        return st

    def wire(self):
        raw = self.js("JSON.stringify(window.__ws)")
        return json.loads(raw) if raw else {}

    def room_code(self):
        """Code from the server's `created` frame (the only text the page can see: the lobby is drawn on a canvas)."""
        for m in self.wire().get("rx", []):
            try:
                d = json.loads(m)
            except Exception:
                continue
            if d.get("t") == "created":
                return d.get("code", "")
        return ""

    def server_frames(self, kind):
        out = []
        for m in self.wire().get("rx", []):
            try:
                d = json.loads(m)
            except Exception:
                continue
            if d.get("t") == kind:
                out.append(d)
        return out

    def rtc_summary(self):
        v = self.js("JSON.stringify({pcs: window.__pc_summary ? window.__pc_summary() : [], "
                    "ever: !!window.__pc_ever_connected})")
        return json.loads(v) if v else {"pcs": [], "ever": False}

    def selected_pair(self):
        """Informational: the nominated candidate pair of the connected RTCPeerConnection (host/srflx/relay)."""
        expr = """(async () => {
          const pc = (window.__pcs || []).find(p => p.connectionState === 'connected'); if (!pc) return null;
          const stats = await pc.getStats(); let pair = null; const cands = {};
          stats.forEach(s => { if (s.type === 'local-candidate' || s.type === 'remote-candidate') cands[s.id] = s; });
          stats.forEach(s => { if (s.type === 'candidate-pair' && (s.nominated || s.state === 'succeeded')) pair = s; });
          if (!pair) return null;
          const l = cands[pair.localCandidateId] || {}, r = cands[pair.remoteCandidateId] || {};
          return JSON.stringify({local: l.candidateType, remote: r.candidateType, rtt_ms: Math.round((pair.currentRoundTripTime || 0) * 1000)});
        })()"""
        try:
            v = self.js(expr, await_promise=True)
            return json.loads(v) if v else None
        except Exception:
            return None


# --- helpers ------------------------------------------------------------------------------------
def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def xz(p):
    return (p["x"], p["z"])


def ally_xz(p):
    return (p["allies"][0]["x"], p["allies"][0]["z"]) if p and p.get("allies") else None


def wait_for(cond, timeout, step=0.25):
    end = time.time() + timeout
    while time.time() < end:
        v = cond()
        if v:
            return v
        time.sleep(step)
    return None


def load_net_cfg():
    with open(NET_JSON, encoding="utf-8") as f:
        return json.load(f)


def find_bun():
    cands = [os.environ.get("BUN", ""), os.path.join(os.path.expanduser("~"), ".bun", "bin", "bun.exe"),
             os.path.join(os.path.expanduser("~"), ".bun", "bin", "bun")]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    return shutil.which("bun") or ""


def godot_cmd():
    """tools/godot.sh through sh when available (Git Bash), else tools/godot.ps1 through PowerShell."""
    sh = shutil.which("sh") or shutil.which("bash")
    if sh:
        return [sh, os.path.join(ROOT, "tools", "godot.sh")]
    ps = shutil.which("powershell") or shutil.which("pwsh")
    if ps:
        return [ps, "-NoProfile", "-File", os.path.join(ROOT, "tools", "godot.ps1")]
    raise RuntimeError("neither sh nor PowerShell found to run tools/godot.sh|ps1")


def export_web(dest):
    log(f"=== exporting the Web build to {dest}")
    os.makedirs(dest, exist_ok=True)
    cmd = godot_cmd() + ["--headless", "--path", ROOT, "--export-release", "Web", os.path.join(dest, "index.html")]
    r = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    ok = os.path.isfile(os.path.join(dest, "index.html")) and os.path.isfile(os.path.join(dest, "index.wasm"))
    record("export Web build", r.returncode == 0 and ok, f"exit {r.returncode}, index.html+wasm present={ok}")
    if not ok:
        log(r.stdout.decode(errors="replace")[-1500:])
    return ok


def start_bun(bun):
    port = free_port()
    proc = subprocess.Popen([bun, "server.js", "--port", str(port), "--host", "127.0.0.1"],
                            cwd=os.path.join(ROOT, "server"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    CLEANUP.append(lambda: kill_tree(proc))
    end = time.time() + 15
    import socket
    while time.time() < end:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return port, proc
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("Bun room server did not open its port")


# --- the scenario ---------------------------------------------------------------------------------
def walk(walker, viewer, label):
    """walker holds W for WALK_S and stops; viewer must see it end within MAX_ERROR_M."""
    before_w = walker.fresh_probe()
    before_v = viewer.fresh_probe()
    seen_before = ally_xz(before_v)
    wire_a = viewer.wire()
    t0 = time.time()
    walker.key(True, *KEY_W)
    time.sleep(WALK_S)
    walker.key(False, *KEY_W)
    time.sleep(SETTLE_S)
    after_w = walker.fresh_probe()
    after_v = viewer.fresh_probe()
    t1 = time.time()
    wire_b = viewer.wire()
    seen_after = ally_xz(after_v)
    walked = dist2(xz(before_w), xz(after_w))
    record(f"{label}: walker moved", walked >= MIN_WALK_M, f"{walked:.2f} m (min {MIN_WALK_M})")
    if seen_before is None or seen_after is None:
        record(f"{label}: viewer has allies[0]", False, f"before={seen_before} after={seen_after}")
        return None
    err = dist2(xz(after_w), seen_after)
    record(f"{label}: allies[0] within {MAX_ERROR_M} m of the real position {SETTLE_S:.0f} s after the stop",
           err <= MAX_ERROR_M,
           f"error {err:.3f} m (real {xz(after_w)}, seen {seen_after})")
    saw_move = dist2(seen_before, seen_after)
    record(f"{label}: viewer saw it move", saw_move >= MIN_WALK_M, f"{saw_move:.2f} m")
    bins = wire_b.get("bin_rx", 0) - wire_a.get("bin_rx", 0)
    return {"err": err, "walked": walked, "saw_move": saw_move, "relay_bin_rx": bins, "secs": t1 - t0}


# --- steps through the real menus ------------------------------------------------------------------
def load_pages(browsers, base_url, query):
    for br in browsers:
        br.navigate(f"{base_url}/index.html?{query}")
    for br in browsers:
        if not br.wait_loaded():
            record(f"page {br.name} loads", False, "game did not load")
            return False
    time.sleep(4)
    return True


def to_menu(br):
    """Boot tap -> main menu."""
    br.click(*BOOT_TAP)
    time.sleep(2.5)


def to_lobby(br):
    """Menu -> "Jogar com amigos (beta)" (no ?mp=1 anywhere: the button is always there since F6)."""
    br.click(*MENU_FRIENDS)
    time.sleep(2.5)


def create_room(a, label="A creates a room through the lobby"):
    a.click(*LOBBY_CREATE)
    code = wait_for(a.room_code, STEP_TIMEOUT_S)
    a.shot("room_created")
    record(label, bool(code), f"code {code!r}")
    if not code:
        log("A console: " + " | ".join(a.console()))
    return code


def join_typing(b, code):
    b.click(*LOBBY_CODE)
    time.sleep(0.3)
    b.type_text(code)
    time.sleep(0.5)
    b.shot("code_typed")
    b.click(*LOBBY_JOIN)


def wait_joined(b, label):
    joined = wait_for(lambda: b.server_frames("joined"), STEP_TIMEOUT_S)
    t_join = time.time()
    b.shot("joined")
    record(label, bool(joined), f"joined frame {joined[0] if joined else None}")
    if not joined:
        log("B console: " + " | ".join(b.console()))
    return t_join if joined else None


def ready_and_start(a, b):
    """The host cannot start while the client is not ready; after "Pronto" it can. True once both reach the hunt."""
    time.sleep(1.0)
    a.shot("room_with_two")
    b.shot("room_not_ready")
    for _ in range(2):
        a.click(*ROOM_START)
        time.sleep(1.0)
    early = a.probe() is not None or b.probe() is not None
    record("host cannot start before the client pressed Pronto", not early,
           "hunt NOT started after 2 presses of Iniciar" if not early else "the hunt started with a client not ready")
    b.click(*ROOM_READY)
    time.sleep(1.2)
    b.shot("client_ready")
    deadline = time.time() + STEP_TIMEOUT_S
    n = 0
    while time.time() < deadline:
        a.click(*ROOM_START)
        n += 1
        if wait_for(lambda: a.probe() is not None and b.probe() is not None, 2.5):
            break
    pa, pb = a.probe(), b.probe()
    record("B presses Pronto, A starts the hunt, both pages reach it", bool(pa and pb),
           f"start presses {n}; A role {pa and pa.get('role')}, B role {pb and pb.get('role')}")
    if not (pa and pb):
        a.shot("start_failed")
        b.shot("start_failed")
        log("A console: " + " | ".join(a.console()))
        log("B console: " + " | ".join(b.console()))
        return False
    return True


def drive_to_hunt(a, b, base_url, query):
    """Menu -> lobby -> room -> ready -> hunt in both pages, typing the code. Returns the time B joined, or None."""
    if not load_pages((a, b), base_url, query):
        return None
    to_menu(a)
    to_menu(b)
    to_lobby(a)
    to_lobby(b)
    a.shot("lobby")
    code = create_room(a)
    if not code:
        return None
    join_typing(b, code)
    t_join = wait_joined(b, "B joins with the typed code")
    if t_join is None or not ready_and_start(a, b):
        return None
    return t_join


def drive_to_hunt_invite(a, b, base_url, query):
    """B opens the invite link (?sala=code, lower case on purpose) instead of typing. Returns the time B joined."""
    if not load_pages((a,), base_url, query):
        return None
    to_menu(a)
    to_lobby(a)
    a.shot("lobby")
    code = create_room(a)
    if not code:
        return None
    if not load_pages((b,), base_url, f"sala={code.lower()}&{query}"):
        return None
    to_menu(b)   # the boot tap: with an invite it goes straight to the lobby, which joins by itself
    t_join = wait_joined(b, "B joins from ?sala=<code> without typing it")
    if t_join is None:
        return None
    urls = [u for u in b.wire().get("urls", []) if "t=join" in u]
    record("B's join request carries the invite code", any(f"code={code}" in u for u in urls),
           f"{len(urls)} join URL(s) opened by the page", note="the code was never typed")
    if not ready_and_start(a, b):
        return None
    return t_join


def scenario(name, base_url, bun_port, workdir, shots_root, net_cfg):
    log(f"=== scenario {name}")
    drop = name == "drop_ice"
    invite = name == "invite"
    query = f"probe=1&server=ws://127.0.0.1:{bun_port}/ws" + ("&drop_ice=1" if drop else "")
    shots = os.path.join(shots_root, name)
    os.makedirs(shots, exist_ok=True)
    a = Browser(f"{name}_A", workdir, shots)
    b = Browser(f"{name}_B", workdir, shots)
    try:
        a.connect()
        b.connect()
        t_join = (drive_to_hunt_invite if invite else drive_to_hunt)(a, b, base_url, query)
        if t_join is None:
            return
        ice_s = float(net_cfg["ice_timeout_s"])
        pa, pb = a.fresh_probe(), b.fresh_probe()
        record("probe reports roles/slots", pa["role"] == "host" and pb["role"] == "client" and pa["slot"] == 0 and pb["slot"] == 1,
               f"A {pa['role']}/slot {pa['slot']}, B {pb['role']}/slot {pb['slot']}")
        record("each page sees one ally", len(pa["allies"]) == 1 and len(pb["allies"]) == 1,
               f"A allies {pa['allies']} B allies {pb['allies']}")
        if invite:
            pass   # the path is not the point of this scenario (rtc/drop_ice cover it)
        elif not drop:
            t0 = time.time()
            got = wait_for(lambda: (a.fresh_probe() or {}).get("path") == "rtc" and (b.fresh_probe() or {}).get("path") == "rtc",
                           ice_s + RTC_EXTRA_WAIT_S, step=0.4)
            pa, pb = a.fresh_probe(), b.fresh_probe()
            record('huntProbe.path == "rtc" on both', bool(got),
                   f"A path {pa['path']}, B path {pb['path']} after {time.time() - t0:.1f} s (join at -{t0 - t_join:.1f} s); "
                   f"A pcs {a.rtc_summary()}, B pcs {b.rtc_summary()}")
            record("RTC pair selected", True, f"A {a.selected_pair()}, B {b.selected_pair()}", note="info")
            if not got:
                a.shot("no_rtc")
                b.shot("no_rtc")
        else:
            # The deadline counts from the link creation (the join). Wait for it to pass, with margin.
            wait_s = t_join + ice_s + 2.0 - time.time()
            log(f"  waiting {max(wait_s, 0):.1f} s for ice_timeout_s ({ice_s}) to elapse")
            end = time.time() + max(wait_s, 0)
            seen_paths = set()
            while time.time() < end:
                for br in (a, b):
                    p = br.probe()
                    if p:
                        seen_paths.add(p["path"])
                time.sleep(0.25)
            pa, pb = a.fresh_probe(), b.fresh_probe()
            record('huntProbe.path == "relay" on both after ice_timeout_s', pa["path"] == "relay" and pb["path"] == "relay",
                   f"A {pa['path']}, B {pb['path']}, paths seen meanwhile {sorted(seen_paths)}",
                   note="" if pa["path"] == "relay" and pb["path"] == "relay" else "F3 pending: ICE deadline / relay fallback")
            rs_a, rs_b = a.rtc_summary(), b.rtc_summary()
            record("no RTCPeerConnection ever connected (candidates dropped)", not rs_a["ever"] and not rs_b["ever"],
                   f"A {rs_a}, B {rs_b}")
            sent_cands = sum(1 for br in (a, b) for m in br.wire().get("tx", []) if '"candidate"' in m)
            record("no ICE candidate was signalled", sent_cands == 0, f"{sent_cands} candidate signal frames sent")
            record("RTC state after the deadline", True, f"A {rs_a['pcs']}, B {rs_b['pcs']}", note="info: the connection should be closed")
        # A walks, B watches; then B walks, A watches.
        r1 = walk(a, b, "A walks, B watches")
        r2 = walk(b, a, "B walks, A watches")
        pa, pb = a.fresh_probe(), b.fresh_probe()
        if not invite:
            record("path unchanged after walking", pa["path"] == pb["path"] == ("relay" if drop else "rtc"),
                   f"A {pa['path']}, B {pb['path']}")
        for label, r in (("A walks", r1), ("B walks", r2)):
            if r is None or invite:
                continue
            rate = r["relay_bin_rx"] / max(r["secs"], 0.1)
            if drop:
                # relay_hz = 10: a walking minute of state flows through the WebSocket
                record(f"{label}: viewer receives state through the relay", rate >= 3.0,
                       f"{r['relay_bin_rx']} binary frames in {r['secs']:.1f} s ({rate:.1f}/s, expected about {net_cfg['relay_hz']}/s)")
            else:
                record(f"{label}: relay is (almost) silent once on RTC", rate <= 3.0,
                       f"{r['relay_bin_rx']} binary relay frames in {r['secs']:.1f} s ({rate:.1f}/s; relay mode would be about {net_cfg['relay_hz']}/s)")
        a.shot("end")
        b.shot("end")
    finally:
        a.close()
        b.close()


def _frame_diff(img_a, img_b):
    """Mean absolute RGB difference between two decoded PNGs of the same size (every 3rd pixel)."""
    wa, ha, ca, ra = img_a
    wb, hb, cb, rb = img_b
    total = n = 0
    for y in range(0, min(ha, hb), 3):
        la, lb = ra[y], rb[y]
        for x in range(0, min(wa, wb), 3):
            for k in range(3):
                total += abs(la[x * ca + k] - lb[x * cb + k])
            n += 3
    return total / max(n, 1)


def scenario_server_unreachable(base_url, dead_port, workdir, shots_root):
    """F6 acceptance: unreachable room server -> `server_unreachable` message in <= 9 s, "Voltar" works."""
    log("=== scenario server_unreachable")
    shots = os.path.join(shots_root, "server_unreachable")
    os.makedirs(shots, exist_ok=True)
    a = Browser("server_unreachable_A", workdir, shots)
    try:
        a.connect()
        if not load_pages((a,), base_url, f"probe=1&server=ws://127.0.0.1:{dead_port}/ws"):
            return
        to_menu(a)
        time.sleep(0.5)
        menu_ref = a.png()
        a.shot("menu")
        to_lobby(a)
        a.shot("lobby_entry")
        lobby_img = a.png()
        before = a.count_color(MESSAGE_RGB, MESSAGE_TOL)
        record("lobby entry screen has no error text before trying", 0 <= before <= MESSAGE_MIN_PX // 5,
               f"{before} red pixels (threshold {MESSAGE_MIN_PX})")
        t0 = time.time()
        a.click(*LOBBY_CREATE)
        shown, px = None, 0
        while time.time() - t0 < MESSAGE_DEADLINE_S + 4.0:
            n = a.count_color(MESSAGE_RGB, MESSAGE_TOL)
            if n >= MESSAGE_MIN_PX:
                shown = time.time() - t0
                px = n
                break
            time.sleep(0.3)
        a.shot("message")
        record("server_unreachable message shown within 9 s of Criar sala", shown is not None and shown <= MESSAGE_DEADLINE_S,
               f"red message text ({px} px) after {shown:.1f} s" if shown is not None else "no error text within the limit",
               note="detected by pixel colour (canvas UI)")
        urls = a.wire().get("urls", [])
        record("the page really tried the dead port", any(f":{dead_port}/" in u for u in urls), f"WebSocket URLs {urls}")
        a.click(*LOBBY_BACK)
        time.sleep(2.0)
        back_img = a.png()
        a.shot("after_voltar")
        if menu_ref is not None and back_img is not None:
            d_menu, d_lobby = _frame_diff(menu_ref, back_img), _frame_diff(lobby_img, back_img)
            record("Voltar returns to the main menu", d_menu < 3.0 and d_lobby > 8.0,
                   f"diff vs the menu {d_menu:.2f}, vs the lobby {d_lobby:.2f}")
        else:
            record("Voltar returns to the main menu", False, "no capture")
        to_lobby(a)
        stale = a.count_color(MESSAGE_RGB, MESSAGE_TOL)
        a.shot("lobby_again")
        record("entering the lobby again shows no stale error", 0 <= stale <= MESSAGE_MIN_PX // 5, f"{stale} red pixels")
    finally:
        a.close()



def scenario_invite_unknown(base_url, bun_port, workdir, shots_root):
    """F6 edge: an invite link to a room that does not exist (live server): the lobby shows `room_not_found` (red
    text) in <= 9 s without anyone typing, and "Voltar" goes to the menu."""
    log("=== scenario invite_unknown")
    shots = os.path.join(shots_root, "invite_unknown")
    os.makedirs(shots, exist_ok=True)
    a = Browser("invite_unknown_A", workdir, shots)
    base_query = f"probe=1&server=ws://127.0.0.1:{bun_port}/ws"
    try:
        a.connect()
        if not load_pages((a,), base_url, base_query):
            return
        to_menu(a)
        time.sleep(0.5)
        menu_ref = a.png()
        if not load_pages((a,), base_url, f"sala=zzzzz&{base_query}"):
            return
        t0 = time.time()
        to_menu(a)   # the boot tap goes straight to the lobby, which tries to join ZZZZZ
        shown, px = None, 0
        while time.time() - t0 < MESSAGE_DEADLINE_S + 4.0:
            n = a.count_color(MESSAGE_RGB, MESSAGE_TOL)
            if n >= MESSAGE_MIN_PX:
                shown = time.time() - t0
                px = n
                break
            time.sleep(0.3)
        a.shot("message")
        record("unknown invite: room_not_found message shown within 9 s of the boot tap",
               shown is not None and shown <= MESSAGE_DEADLINE_S,
               f"red message text ({px} px) after {shown:.1f} s" if shown is not None else "no error text within the limit")
        urls = [u for u in a.wire().get("urls", []) if "t=join" in u]
        record("the page joined with the code of the link", any("code=ZZZZZ" in u for u in urls), f"join URLs {urls}")
        errs = [f.get("code") for f in a.server_frames("error")]
        record("the server answered room_not_found", "room_not_found" in errs, f"error frames {errs}")
        a.click(*LOBBY_BACK)
        time.sleep(2.0)
        back_img = a.png()
        a.shot("after_voltar")
        if menu_ref is not None and back_img is not None:
            d_menu = _frame_diff(menu_ref, back_img)
            record("Voltar returns to the main menu", d_menu < 3.0, f"diff vs the menu {d_menu:.2f}")
        else:
            record("Voltar returns to the main menu", False, "no capture")
    finally:
        a.close()


def scenario_shop_in_room(base_url, bun_port, workdir, shots_root):
    """F6 edge: a READY client opens "Loja" from the room (the lobby scene is gone while it is in the shop) and the
    host starts the hunt. Expected: the client is not stranded; both pages reach the hunt (or the host cannot start)."""
    log("=== scenario shop_in_room")
    shots = os.path.join(shots_root, "shop_in_room")
    os.makedirs(shots, exist_ok=True)
    a = Browser("shop_in_room_A", workdir, shots)
    b = Browser("shop_in_room_B", workdir, shots)
    query = f"probe=1&server=ws://127.0.0.1:{bun_port}/ws"
    try:
        a.connect()
        b.connect()
        if not load_pages((a, b), base_url, query):
            return
        for br in (a, b):
            to_menu(br)
        for br in (a, b):
            to_lobby(br)
        code = create_room(a)
        if not code:
            return
        join_typing(b, code)
        if wait_joined(b, "B joins with the typed code") is None:
            return
        time.sleep(1.0)
        b.click(*ROOM_READY)
        time.sleep(1.0)
        b.click(*ROOM_SHOP)
        time.sleep(2.5)
        b.shot("client_in_shop")
        a.shot("host_sees_client_ready")
        a.click(*ROOM_START)
        time.sleep(1.0)
        a.shot("host_pressed_start")
        reached = wait_for(lambda: a.probe() is not None and b.probe() is not None, 40)
        started_a = a.probe() is not None
        record("client in the shop when the host starts: both reach the hunt (or the host is blocked)",
               bool(reached) or not started_a,
               f"A in hunt {started_a}, B in hunt {b.probe() is not None}")
        a.shot("end")
        b.shot("end")
    finally:
        a.close()
        b.close()


def main():
    wanted = list(SCENARIOS)
    build_dir = ""
    keep = False
    for arg in sys.argv[1:]:
        if arg.startswith("--scenarios="):
            wanted = [s for s in arg.split("=", 1)[1].split(",") if s]
            if any(s not in SCENARIOS for s in wanted):
                print(__doc__)
                return 2
        elif arg.startswith("--build-dir="):
            build_dir = arg.split("=", 1)[1]
        elif arg.startswith("--load-timeout="):
            global LOAD_TIMEOUT_S
            LOAD_TIMEOUT_S = float(arg.split("=", 1)[1])
        elif arg == "--keep":
            keep = True
        else:
            print(__doc__)
            return 0 if arg in ("--help", "-h") else 2

    signal.signal(signal.SIGINT, lambda *_: (run_cleanup(), sys.exit(130)))
    if hasattr(signal, "SIGBREAK"):
        signal.signal(signal.SIGBREAK, lambda *_: (run_cleanup(), sys.exit(130)))
    if not os.path.isfile(CHROME):
        log(f"Chrome not found at {CHROME}")
        return 2
    bun = find_bun()
    if not bun:
        log("Bun not found (PATH, $BUN or ~/.bun/bin): cannot start the room server. NOT RUN.")
        return 2

    net_cfg = load_net_cfg()
    work = tempfile.mkdtemp(prefix="javali_coop_")
    shots_root = os.path.join(work, "shots")
    os.makedirs(shots_root, exist_ok=True)
    export_dir = build_dir or os.path.join(work, "web")
    t0 = time.time()
    try:
        if not build_dir and not export_web(export_dir):
            return finish(t0, work, shots_root, keep)
        http = StaticServer(export_dir)
        http.start()
        CLEANUP.append(http.stop)
        bun_port, _ = start_bun(bun)
        base_url = f"http://127.0.0.1:{http.port}"
        log(f"=== serving {export_dir} at {base_url}; room server on ws://127.0.0.1:{bun_port}/ws")
        for name in wanted:
            try:
                if name == "server_unreachable":
                    scenario_server_unreachable(base_url, free_port(), work, shots_root)
                elif name == "shop_in_room":
                    scenario_shop_in_room(base_url, bun_port, work, shots_root)
                elif name == "invite_unknown":
                    scenario_invite_unknown(base_url, bun_port, work, shots_root)
                else:
                    scenario(name, base_url, bun_port, work, shots_root, net_cfg)
            except Exception:
                traceback.print_exc()
                record(f"scenario {name} crashed", False, "exception, see traceback above")
    finally:
        run_cleanup()
    return finish(t0, work, shots_root, keep)


def finish(t0, work, shots_root, keep):
    failed = [r for r in RESULTS if not r["ok"]]
    log(f"=== {len(RESULTS) - len(failed)} ok, {len(failed)} failed, {int(time.time() - t0)}s total")
    for r in failed:
        log(f"FAILED: {r['test']}: {r['measured']}" + (f" ({r['note']})" if r["note"] else ""))
    out = os.path.join(shots_root, "coop_results.json")
    try:
        with open(out, "w", encoding="utf-8") as f:
            json.dump(RESULTS, f, indent=1)
    except Exception:
        pass
    keep_shots = keep or bool(failed)
    for sub in os.listdir(work):
        if sub == "shots" and keep_shots:
            continue
        shutil.rmtree(os.path.join(work, sub), ignore_errors=True)
    if keep_shots:
        log(f"screenshots and results kept in {shots_root}")
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
