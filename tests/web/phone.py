"""Phone emulation on top of cdp.py: serves build/web, drives headless Chrome with real touch events."""
import json
import os
import shutil
import tempfile
import time

from cdp import ChromeProc, StaticServer, free_port

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD_DIR = os.path.join(ROOT, "build", "web")
SHOTS_DIR = r"C:\Users\adrie\AppData\Local\Temp\claude\90ca056d862530a5\5cd4ecfb-1f57-4211-b698-70930ccb7ffe\scratchpad\shots\mobile"
SCRATCH = r"C:\Users\adrie\AppData\Local\Temp\claude\90ca056d862530a5\5cd4ecfb-1f57-4211-b698-70930ccb7ffe\scratchpad"

WIDTH, HEIGHT, DPR = 844, 390, 3
QUERY = "?probe=1"   # enables the game's window.huntProbe QA hook (src/hud/hud.gd)
UA = ("Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0.0.0 Mobile Safari/537.36")

# Logs every DOM input event so we can see what the browser really delivers to the canvas.
HOOK_JS = r"""
(() => {
  window.__ev = [];
  const log = (phase) => (e) => {
    if (window.__ev.length > 3000) window.__ev.shift();
    const t = (e.changedTouches && e.changedTouches[0]) || e;
    window.__ev.push({ts: Math.round(performance.now()), ph: phase, type: e.type,
      x: Math.round(t.clientX || 0), y: Math.round(t.clientY || 0), id: t.identifier ?? e.pointerId ?? null,
      n: e.touches ? e.touches.length : null, trusted: e.isTrusted, dp: e.defaultPrevented,
      src: e.sourceCapabilities ? e.sourceCapabilities.firesTouchEvents : null});
  };
  for (const type of ['touchstart','touchmove','touchend','touchcancel','mousedown','mouseup','click',
                      'pointerdown','pointerup','pointercancel']) {
    window.addEventListener(type, log('cap'), true);
    window.addEventListener(type, log('bub'), false);
  }
})();
"""


class Phone:
    def __init__(self, tag: str = "run"):
        os.makedirs(SHOTS_DIR, exist_ok=True)
        self.tag = tag
        self.step = 0
        self.server = StaticServer(BUILD_DIR)
        self.server.start()
        self.profile = tempfile.mkdtemp(prefix="chrome_prof_", dir=SCRATCH)
        self.chrome = ChromeProc(self.profile, free_port())
        self.cdp = None
        self.fingers = {}
        self.notes = []

    # -- lifecycle ---------------------------------------------------------
    def start(self):
        self.cdp = self.chrome.connect()
        c = self.cdp
        for domain in ("Page", "Runtime", "Log"):
            c.call(f"{domain}.enable")
        c.call("Emulation.setDeviceMetricsOverride", {
            "width": WIDTH, "height": HEIGHT, "deviceScaleFactor": DPR, "mobile": True,
            "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
        c.call("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
        c.call("Emulation.setEmitTouchEventsForMouse", {"enabled": False})
        c.call("Emulation.setUserAgentOverride", {"userAgent": UA, "platform": "Android"})
        c.call("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK_JS})
        c.call("Page.navigate", {"url": self.url()})

    def url(self) -> str:
        return f"http://127.0.0.1:{self.server.port}/index.html{QUERY}"

    def stop(self):
        try:
            if self.cdp:
                self.cdp.close()
        except Exception:
            pass
        self.chrome.kill()
        self.server.stop()
        time.sleep(1.0)
        shutil.rmtree(self.profile, ignore_errors=True)

    # -- observation -------------------------------------------------------
    def shot(self, name: str) -> str:
        """Saves a JPEG screenshot (for humans) and keeps the last PNG bytes in self.last_png (for diffs)."""
        import base64
        self.step += 1
        res = self.cdp.call("Page.captureScreenshot", {
            "format": "jpeg", "quality": 70,
            "clip": {"x": 0, "y": 0, "width": WIDTH, "height": HEIGHT, "scale": 1.0 / DPR}})
        path = os.path.join(SHOTS_DIR, f"{self.tag}_{self.step:02d}_{name}.jpg")
        with open(path, "wb") as f:
            f.write(base64.b64decode(res["data"]))
        return path

    def png(self) -> bytes:
        """Screenshot as PNG bytes (844x390) without saving."""
        import base64
        res = self.cdp.call("Page.captureScreenshot", {
            "format": "png", "clip": {"x": 0, "y": 0, "width": WIDTH, "height": HEIGHT, "scale": 0.5 / DPR}})
        return base64.b64decode(res["data"])

    def js(self, expr: str):
        r = self.cdp.call("Runtime.evaluate", {"expression": expr, "returnByValue": True})
        return r.get("result", {}).get("value")

    def dom_events(self, clear: bool = True, phase: str = "cap"):
        evs = self.js("window.__ev") or []
        if clear:
            self.js("window.__ev = []")
        return [e for e in evs if e["ph"] == phase] if phase else evs

    def probe(self):
        """Current window.huntProbe (dict) or None."""
        raw = self.js("window.huntProbe ? JSON.stringify(window.huntProbe) : null")
        return json.loads(raw) if raw else None

    def fresh_probe(self, timeout: float = 3.0):
        """Waits for a publish newer than the last one seen, so reads are never stale."""
        last = getattr(self, "_last_t", -1)
        end = time.time() + timeout
        st = None
        while time.time() < end:
            st = self.probe()
            if st and st["t_ms"] != last:
                self._last_t = st["t_ms"]
                return st
            time.sleep(0.05)
        return st

    def console_tail(self, n: int = 30):
        return self.cdp.console[-n:]

    # -- touch -------------------------------------------------------------
    def _dispatch(self, kind: str, changed_ids=None):
        pts = [{"x": x, "y": y, "id": i, "radiusX": 12, "radiusY": 12, "force": 1.0}
               for i, (x, y) in sorted(self.fingers.items())]
        self.cdp.call("Input.dispatchTouchEvent", {"type": kind, "touchPoints": pts})

    def down(self, fid: int, x: float, y: float):
        self.fingers[fid] = (x, y)
        self._dispatch("touchStart")

    def move(self, fid: int, x: float, y: float):
        self.fingers[fid] = (x, y)
        self._dispatch("touchMove")

    def move_many(self, targets: dict):
        """Moves several fingers in ONE touchMove event. targets: {finger_id: (x, y)}."""
        self.fingers.update(targets)
        self._dispatch("touchMove")

    def up(self, fid: int):
        """Lifts one finger. CDP semantics (verified): touchEnd.touchPoints lists the points being RELEASED
        (listing the remaining ones would release those instead)."""
        x, y = self.fingers.pop(fid, (0, 0))
        pts = [{"x": x, "y": y, "id": fid, "radiusX": 12, "radiusY": 12, "force": 1.0}]
        self.cdp.call("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": pts})

    def tap(self, x: float, y: float, hold: float = 0.12, fid: int = 1):
        self.down(fid, x, y)
        time.sleep(hold)
        self.up(fid)

    def drag(self, fid: int, x0, y0, x1, y1, steps: int = 12, dt: float = 0.03):
        for i in range(1, steps + 1):
            t = i / steps
            self.move(fid, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
            time.sleep(dt)

    def hold(self, seconds: float, jitter_fid: int = None, dt: float = 0.1):
        """Wait in real time; if jitter_fid is set keep sending tiny moves so the finger looks alive."""
        end = time.time() + seconds
        while time.time() < end:
            if jitter_fid is not None and jitter_fid in self.fingers:
                x, y = self.fingers[jitter_fid]
                self.move(jitter_fid, x, y)
            time.sleep(dt)

    def release_all(self):
        for fid in list(self.fingers):
            self.up(fid)

    def navigate(self):
        self.fingers.clear()
        self.cdp.call("Page.navigate", {"url": self.url()})
        time.sleep(2.0)

    def wait_game_loaded(self, timeout: float = 120.0):
        """Loaded once the canvas exists and Godot started drawing (status overlay hidden)."""
        end = time.time() + timeout
        while time.time() < end:
            ok = self.js("""(()=>{const s=document.getElementById('status');
                const c=document.getElementById('canvas');
                return !!c && c.width>0 && (!s || getComputedStyle(s).visibility==='hidden');})()""")
            if ok:
                return True
            time.sleep(1.0)
        return False
