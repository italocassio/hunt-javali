"""Frame-time A/B of Web builds in phone-emulated Chrome (reuses phone.py / mobile_probe.py).

    python tests/web/perf_ab.py <label=builddir> [<label=builddir> ...] [--rounds=N] [--secs=S] [--out=file.json]

Per session: fresh Chrome profile -> boot -> seeds user://save.json in IndexedDB (rifle_308 in slot 1, carbine_22 in
slot 2; a label ending in "carbine" swaps them) -> enters a hunt by touch -> measures requestAnimationFrame
intervals (mean / p95) in conditions hip_x1, hip_x4 (CPU throttling 4x), ads_x4, ads_x1.  Env ONLY_HIP=1 measures
hip_x1 only; UNCAP=0 keeps Chrome's 60 Hz frame cap (default removes it).  Build dirs come from
tools/godot.sh --headless --path . --export-release "Web" <dir>/index.html.  Interleave labels (--rounds does it)
because the machine's background load drifts; discard sessions whose frame time jumps ~2x.
Chrome uses the real GPU here (ANGLE/D3D11), not SwiftShader.  Scratch: JAVALI_SCRATCH or the temp dir.
"""
import os, sys, time, json, statistics, traceback
S = os.path.dirname(os.path.abspath(__file__))
TESTS = S
sys.path.insert(0, TESTS)
import cdp
EXTRA = ["--disable-frame-rate-limit", "--disable-gpu-vsync"] if os.environ.get("UNCAP", "1") == "1" else []
_Orig = cdp.ChromeProc
class Chrome2(_Orig):
    def __init__(self, user_data_dir, debug_port):
        import subprocess
        self.port = debug_port
        args = [cdp.CHROME, "--headless=new", f"--remote-debugging-port={debug_port}", f"--user-data-dir={user_data_dir}",
                "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-first-run", "--no-default-browser-check",
                "--autoplay-policy=no-user-gesture-required"] + EXTRA + ["about:blank"]
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
import phone
phone.ChromeProc = Chrome2
import mobile_probe as mp

SAMPLER = """(()=>{window.__ft=[];let last=performance.now();window.__run=true;
 const f=(t)=>{if(!window.__run)return;window.__ft.push(t-last);last=t;requestAnimationFrame(f)};requestAnimationFrame(f)})()"""

def seed(p, weapons):
    key_js = """new Promise(r=>{const q=indexedDB.open('/userfs');q.onsuccess=()=>{const db=q.result;const os=db.transaction('FILE_DATA').objectStore('FILE_DATA');
      const t=os.getAllKeys();t.onsuccess=()=>{const k=t.result.find(x=>x.endsWith('/save.json'));if(!k){r(null);return}
      const g=os.get(k);g.onsuccess=()=>r(JSON.stringify({k:k,txt:new TextDecoder().decode(g.result.contents)}))}}})"""
    for _ in range(20):
        r = p.cdp.call("Runtime.evaluate", {"expression": key_js, "awaitPromise": True, "returnByValue": True})["result"].get("value")
        if r:
            break
        time.sleep(1)
    if not r:
        raise RuntimeError("no save.json in IDB")
    info = json.loads(r)
    save = json.loads(info["txt"])
    inv = save["inventory"]["weapons"]
    for w in weapons:
        if w not in inv:
            inv.append(w)
    save["loadout"]["weapons"] = list(weapons)
    new_txt = json.dumps(save)
    put = """new Promise(r=>{const q=indexedDB.open('/userfs');q.onsuccess=()=>{const db=q.result;const tx=db.transaction('FILE_DATA','readwrite');const os=tx.objectStore('FILE_DATA');
      const k=%s;const g=os.get(k);g.onsuccess=()=>{const v=g.result;v.contents=new TextEncoder().encode(%s);v.timestamp=new Date();os.put(v,k)};tx.oncomplete=()=>r('ok')}})""" % (json.dumps(info["k"]), json.dumps(new_txt))
    out = p.cdp.call("Runtime.evaluate", {"expression": put, "awaitPromise": True, "returnByValue": True})["result"].get("value")
    return out

def stats(ft):
    ft = sorted(ft)
    n = len(ft)
    mean = sum(ft) / n
    q = lambda f: ft[min(n - 1, int(f * n))]
    return {"n": n, "mean_ms": round(mean, 2), "p50_ms": round(q(.5), 2), "p95_ms": round(q(.95), 2), "p99_ms": round(q(.99), 2),
            "max_ms": round(ft[-1], 1), "fps": round(1000 / mean, 1), "fps_p95": round(1000 / q(.95), 1)}

def measure(p, label, secs, throttle):
    p.cdp.call("Emulation.setCPUThrottlingRate", {"rate": throttle})
    time.sleep(2.5)
    p.js(SAMPLER)
    time.sleep(secs)
    p.js("window.__run=false")
    ft = p.js("window.__ft") or []
    ft = ft[3:]
    s = stats(ft)
    s["cond"] = label
    p.cdp.call("Emulation.setCPUThrottlingRate", {"rate": 1})
    return s

def session(tag, build, weapons, secs):
    os.environ["JAVALI_BUILD_DIR"] = build
    phone.BUILD_DIR = build
    p = phone.Phone(tag)
    p.server.stop()
    from cdp import StaticServer
    p.server = StaticServer(build); p.server.start()
    res = []
    try:
        p.start()
        if not p.wait_game_loaded():
            raise RuntimeError("no load")
        time.sleep(8)
        seed(p, weapons)
        mp.enter_hunt(p, first=False)
        time.sleep(6)
        st0 = p.fresh_probe(timeout=5)
        p.shot("hip")
        if os.environ.get("ONLY_HIP"):
            res.append(measure(p, "hip_x1", secs, 1))
        else:
            res.append(measure(p, "hip_x1", secs, 1))
            res.append(measure(p, "hip_x4", secs, 4))
            p.tap(*mp.AIM, hold=0.15, fid=1)
            time.sleep(1.5)
            p.shot("ads")
            res.append(measure(p, "ads_x4", secs, 4))
            res.append(measure(p, "ads_x1", secs, 1))
        st1 = p.fresh_probe(timeout=5)
        for r in res:
            r["ammo_mag_at_start"] = st0 and st0["ammo_mag"]
            r["health_end"] = st1 and st1["health"]
        print(tag, "console tail:", p.console_tail(4), flush=True)
    finally:
        p.stop()
    return res

def main():
    builds = {}
    rounds = 1; secs = 15; weapon = "rifle_308"; out = os.path.join(os.environ.get("JAVALI_SCRATCH") or __import__("tempfile").gettempdir(), "perf_ab_results.json")
    for a in sys.argv[1:]:
        if a.startswith("--rounds="): rounds = int(a.split("=")[1])
        elif a.startswith("--secs="): secs = int(a.split("=")[1])
        elif a.startswith("--out="): out = a.split("=", 1)[1]
        elif "=" in a:
            k, v = a.split("=", 1); builds[k] = v
    # label forms: old / new / newcarbine -> weapon chosen by suffix
    allres = []
    for r in range(rounds):
        for label, b in builds.items():
            weapons = ["carbine_22", "rifle_308"] if label.endswith("carbine") else ["rifle_308", "carbine_22"]
            try:
                res = session(f"{label}{r}", b, weapons, secs)
            except Exception:
                traceback.print_exc(); continue
            for x in res:
                x["build"] = label; x["round"] = r
                print(json.dumps(x), flush=True)
            allres += res
            json.dump(allres, open(out, "w"), indent=1)

if __name__ == "__main__":
    main()
