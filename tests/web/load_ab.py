"""Load-time A/B of two Web builds in phone-emulated Chrome with CPU throttling (QA measurement only).

    python tests/web/load_ab.py <label=builddir> [<label=builddir> ...] [--rounds=N] [--throttle=4] [--out=file.json]

Per session (fresh Chrome profile = empty cache, one session per build per round, interleaved):
  boot     navigation start -> status overlay removed (engine running) -> boot screen ("Toque para comecar") drawn
  hunt     tap "Iniciar cacada" -> HUNT_TIMING lines (console) -> loading overlay gone (HUNT_TIMING total_ms)
  frames   requestAnimationFrame intervals from page start; reports the 10 worst frames in the first 5 s after the
           loading overlay is gone, and the worst frames during the loading itself.
The build is served unmodified except index.html, rewritten on the fly so GODOT_CONFIG.args = ["--", "--hunt-timing"]
(src/hunt/hunt_controller.gd ARG_TIMING).  Chrome and the HTTP server are always killed on exit.
Detection of the boot screen is by pixel colour of a downscaled screenshot (polled ~5x/s), so boot_screen_ms has an
error of about +-0.3 s; the other numbers come from page / console timestamps.
"""
import base64
import functools
import http.server
import io
import json
import os
import re
import shutil
import sys
import tempfile
import threading
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cdp  # noqa: E402
import phone  # noqa: E402

THROTTLE = 4
ARGS_JSON = '"args":["--","--hunt-timing"' + ''.join(',"%s"' % x for x in os.environ.get("EXTRA_ARGS", "").split()) + ']'
INIT_JS = r"""
(() => {
  window.__ft = []; window.__marks = {};
  let last = performance.now();
  const f = (t) => { window.__ft.push([Math.round((performance.timeOrigin + t) * 10) / 10, Math.round((t - last) * 100) / 100]); last = t; requestAnimationFrame(f); };
  requestAnimationFrame(f);
  const mo = new MutationObserver(() => {
    if (!window.__marks.status_hidden && document.body && !document.getElementById('status')) {
      window.__marks.status_hidden = performance.timeOrigin + performance.now();
      mo.disconnect();
    }
  });
  mo.observe(document, {childList: true, subtree: true});
})();
"""


def make_server(directory):
    class H(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm",
                          ".js": "text/javascript", ".pck": "application/octet-stream", ".html": "text/html"}

        def log_message(self, *a):
            pass

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path in ("/", "/index.html"):
                with open(os.path.join(directory, "index.html"), "r", encoding="utf-8") as f:
                    txt = f.read()
                txt2 = re.sub(r'"args":\[[^\]]*\]', ARGS_JSON, txt, count=1)
                assert txt2 != txt or ARGS_JSON in txt, "args pattern not found"
                body = txt2.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                return
            super().do_GET()

    class S(http.server.ThreadingHTTPServer):
        def handle_error(self, request, client_address):
            pass

    httpd = S(("127.0.0.1", 0), functools.partial(H, directory=directory))
    th = threading.Thread(target=httpd.serve_forever, daemon=True)
    th.start()
    return httpd


def shot_small(c):
    """Tiny RGB image of the viewport (PIL)."""
    from PIL import Image
    r = c.call("Page.captureScreenshot", {"format": "png", "clip": {"x": 0, "y": 0, "width": phone.WIDTH, "height": phone.HEIGHT, "scale": 0.15 / phone.DPR * 3}})
    return Image.open(io.BytesIO(base64.b64decode(r["data"]))).convert("RGB")


def is_boot_screen(im):
    """Boot screen: dark brown background (UiKit.BG_COLOR ~ 30,26,22) over most of the top half."""
    w, h = im.size
    # Since 0.7.x the boot screen is a painted picture: many distinct colours, unlike the flat page/splash before it.
    if len(set((r // 16, g // 16, b // 16) for r, g, b in im.get_flattened_data())) > 100:
        return True
    n = ok = 0
    for y in range(2, int(h * 0.55), 2):
        for x in range(2, w, 3):
            r, g, b = im.getpixel((x, y))
            n += 1
            if abs(r - 30) < 8 and abs(g - 26) < 8 and abs(b - 22) < 8:
                ok += 1
    return n > 0 and ok / n > 0.8


def img_diff(a, b):
    from PIL import ImageChops
    d = ImageChops.difference(a, b)
    h = d.histogram()
    # mean abs diff over channels
    tot = sum(v * (i % 256) for i, v in enumerate(h))
    return tot / (a.size[0] * a.size[1] * 3)


def console_events(c):
    out = []
    for method, p in list(c.events):
        if method == "Runtime.consoleAPICalled":
            txt = " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
            out.append((p.get("timestamp", 0.0), txt))
    return out


def session(tag, build, throttle):
    httpd = make_server(build)
    port = httpd.server_address[1]
    keep_prof = os.environ.get("PROFILE_DIR")   # reuse a profile across sessions to see the effect of Chrome's GPU shader cache
    if keep_prof:
        os.makedirs(keep_prof, exist_ok=True)
    prof = keep_prof or tempfile.mkdtemp(prefix="chrome_load_", dir=phone.SCRATCH)
    chrome = cdp.ChromeProc(prof, cdp.free_port())
    res = {"tag": tag, "build": build, "throttle": throttle}
    c = None
    try:
        c = chrome.connect()
        for d in ("Page", "Runtime", "Log"):
            c.call(f"{d}.enable")
        c.call("Emulation.setDeviceMetricsOverride", {"width": phone.WIDTH, "height": phone.HEIGHT, "deviceScaleFactor": phone.DPR, "mobile": True,
                                                       "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
        c.call("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
        c.call("Emulation.setUserAgentOverride", {"userAgent": phone.UA, "platform": "Android"})
        if not keep_prof:
            c.call("Network.clearBrowserCache")
        c.call("Network.setCacheDisabled", {"cacheDisabled": True})
        c.call("Page.addScriptToEvaluateOnNewDocument", {"source": INIT_JS})
        c.call("Emulation.setCPUThrottlingRate", {"rate": throttle})
        t_nav = time.time()
        c.call("Page.navigate", {"url": f"http://127.0.0.1:{port}/index.html"})

        def js(expr):
            r = c.call("Runtime.evaluate", {"expression": expr, "returnByValue": True})
            return r.get("result", {}).get("value")

        # --- boot: poll screenshots until the boot screen is drawn
        t_boot = None
        boot_img = None
        end = time.time() + 150
        while time.time() < end:
            try:
                im = shot_small(c)
            except Exception:
                time.sleep(0.3)
                continue
            if is_boot_screen(im):
                t_boot = time.time()
                boot_img = im
                break
            time.sleep(0.1)
        res["boot_screen_ms"] = None if t_boot is None else round((t_boot - t_nav) * 1000)
        marks = js("window.__marks") or {}
        origin = js("performance.timeOrigin")
        res["status_hidden_ms"] = round(marks["status_hidden"] - origin) if "status_hidden" in marks else None
        res["nav_to_origin_ms"] = round(origin - t_nav * 1000)
        if t_boot is None:
            raise RuntimeError("boot screen never detected")
        time.sleep(2.0)

        # --- tap boot -> menu (time until the screenshot changes)
        def tap(x, y, hold=0.12):
            pt = [{"x": x, "y": y, "id": 1, "radiusX": 12, "radiusY": 12, "force": 1.0}]
            c.call("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": pt})
            time.sleep(hold)
            c.call("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": pt})

        t_tap = time.time()
        tap(422, 195)
        t_menu = None
        end = time.time() + 20
        while time.time() < end:
            im = shot_small(c)
            if img_diff(im, boot_img) > 8:
                t_menu = time.time()
                break
            time.sleep(0.05)
        res["boot_tap_to_menu_ms"] = None if t_menu is None else round((t_menu - t_tap) * 1000)
        time.sleep(3.0)
        tap(150, 197); time.sleep(4.0)      # Jogar (poster menu, 0.7.3+)
        tap(400, 95); time.sleep(4.0)       # Mato Grosso
        tap(200, 110); time.sleep(1.5)      # contract 1
        n_before = len(console_events(c))
        shot_small(c)
        if os.environ.get("TRACE"):
            c.call("Tracing.start", {"categories": os.environ["TRACE"], "transferMode": "ReportEvents"})
        t_start = time.time()
        tap(730, 352)                       # Iniciar cacada
        # --- wait for total_ms
        total_ts = None
        end = time.time() + 150
        evs = []
        while time.time() < end:
            evs = console_events(c)
            for ts, txt in evs:
                if "HUNT_TIMING total_ms" in txt:
                    total_ts = ts
            if total_ts:
                break
            time.sleep(0.2)
        if total_ts is None:
            res["console_tail"] = [t for _, t in evs[-15:]]
            raise RuntimeError("no HUNT_TIMING total_ms")
        timing = {}
        first_ts = None
        for ts, txt in evs:
            m = re.search(r"HUNT_TIMING (\w+)=(\d+)", txt)
            if m:
                timing[m.group(1)] = int(m.group(2))
                if first_ts is None:
                    first_ts = ts
        res["timing"] = {k: v for k, v in timing.items() if k != "frame_mark_ms"}
        res["timing_events"] = [[round(ts - t_start * 1000), txt] for ts, txt in evs if "HUNT_TIMING" in txt or "HUNT_PROGRESS" in txt]
        res["tap_to_overlay_gone_ms"] = round(total_ts - t_start * 1000)
        res["tap_to_first_lap_ms"] = round(first_ts - t_start * 1000)
        res["overlay_gone_epoch"] = total_ts
        time.sleep(float(os.environ.get("POST_S", "7")))
        if os.environ.get("TRACE"):
            n0 = len(c.events)
            c.call("Tracing.end")
            for _ in range(120):
                if any(m == "Tracing.tracingComplete" for m, _p in c.events[n0:]):
                    break
                time.sleep(0.5)
            agg = {}
            for m, p in c.events[n0:]:
                if m == "Tracing.dataCollected":
                    for ev in p.get("value", []):
                        if ev.get("ph") == "X" and "dur" in ev:
                            k = (ev.get("name"), ev.get("cat"), ev.get("pid"), ev.get("tid"))
                            a = agg.setdefault(k, [0, 0, 0])
                            a[0] += ev["dur"]; a[1] += 1; a[2] = max(a[2], ev["dur"])
            top = sorted(agg.items(), key=lambda kv: -kv[1][0])[:40]
            res["trace_top"] = [{"name": k[0], "cat": k[1], "pid": k[2], "tid": k[3], "total_ms": round(v[0] / 1000, 1), "n": v[1], "max_ms": round(v[2] / 1000, 1)} for k, v in top]
        ft = js("window.__ft") or []
        # frames after overlay gone (first 5 s), frames during loading (tap -> overlay gone)
        after = [dt for t, dt in ft if total_ts <= t <= total_ts + 5000]
        during = [dt for t, dt in ft if t_start * 1000 <= t <= total_ts]
        worst = sorted(after, reverse=True)[:10]
        res["frames_raw_since_tap"] = [[round(t - t_start * 1000), dt] for t, dt in ft if t >= t_start * 1000]
        res["frames_after_n"] = len(after)
        res["worst10_after_ms"] = worst
        res["worst10_after_sum"] = round(sum(worst), 1)
        res["mean_after_ms"] = round(sum(after) / len(after), 2) if after else None
        later = [dt for t, dt in ft if total_ts + 5000 < t <= total_ts + 7000]
        res["mean_5to7s_ms"] = round(sum(later) / len(later), 2) if later else None
        res["worst10_during_load_ms"] = sorted(during, reverse=True)[:10]
        # attribution: frames > 150 ms during loading, with time since the tap and the HUNT_TIMING lap printed just before
        laps = []
        for ts, txt in evs:
            m = re.search(r"HUNT_TIMING (\w+)=(\d+)", txt)
            if m:
                laps.append((ts, m.group(1)))
        big = []
        for t, dt in ft:
            if t_start * 1000 <= t <= total_ts + 100 and dt > 150:
                prev = [n for ts, n in laps if ts <= t]
                big.append({"t_since_tap_ms": round(t - t_start * 1000), "dt_ms": dt, "after_lap": prev[-1] if prev else "(before first lap)"})
        res["big_frames_loading"] = big
        res["lap_times_since_tap_ms"] = {n: round(ts - t_start * 1000) for ts, n in laps}
        res["during_load_n"] = len(during)
        errs = [t for _, t in console_events(c) if re.search(r"error|ERROR|WARNING", t)]
        res["console_errors"] = errs[:5]
    except Exception as e:
        res["error"] = repr(e)
        traceback.print_exc()
    finally:
        try:
            if c:
                c.close()
        except Exception:
            pass
        chrome.kill()
        httpd.shutdown(); httpd.server_close()
        time.sleep(1.0)
        if not keep_prof:
            shutil.rmtree(prof, ignore_errors=True)
    return res


def main():
    builds = {}
    rounds = 1
    throttle = THROTTLE
    out = os.path.join(phone.SCRATCH, "load_ab_results.json")
    for a in sys.argv[1:]:
        if a.startswith("--rounds="):
            rounds = int(a.split("=")[1])
        elif a.startswith("--throttle="):
            throttle = float(a.split("=")[1])
        elif a.startswith("--out="):
            out = a.split("=", 1)[1]
        elif "=" in a:
            k, v = a.split("=", 1)
            builds[k] = v
    allres = []
    for r in range(rounds):
        for label, b in builds.items():
            res = session(f"{label}{r}", b, throttle)
            res["label"] = label
            res["round"] = r
            print(json.dumps(res), flush=True)
            allres.append(res)
            json.dump(allres, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
