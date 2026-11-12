"""Mobile touch probe: drives the real Web build in headless Chrome (phone emulation) with real touch events.

    python tests/web/mobile_probe.py [--quick] [--groups=g1,g2,g3,g4,g5]

Pipeline exercised: browser touch events -> Godot Web -> InputSetup -> TouchControls -> TouchJoystick /
LookPad -> move_* actions -> Player.  Serves build/web/ (must already be exported).  Stdlib only.
Screenshots go to SHOTS_DIR (see phone.py).  Exit code 0 only if every expectation holds.
Chrome and the HTTP server are always killed on exit.
"""
import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imgdiff  # noqa: E402
from phone import Phone, SHOTS_DIR  # noqa: E402

# --- layout (CSS px, 844x390 landscape; game viewport is 1558x720 with stretch=expand => 0.5417 css/game px)
K = 390.0 / 720.0
JOY_START = (103.0, 303.0)             # joystick rest centre
LOOK_START = (600.0, 200.0)
ARM_TAP = (600.0, 150.0)               # empty look-zone spot used to (re)arm touch mode
FIRE = ((1558 - 125) * K, (720 - 130) * K)
PAUSE = (56 * K, 56 * K)
RESUME = (422.0, 166.0)
TINY_STEP = 0.5     # css px per touchmove: stays under InputSetup.MOUSE_MOTION_SWITCH_PX (see report, finding B)
NORMAL_STEP = 5.0   # css px per touchmove: what a human finger produces

# half-resolution PNG boxes (x0, y0, x1, y1)
SCENE = (85, 65, 260, 115)
AMMO = (235, 170, 275, 190)
# Scene diff above this = the hunter walked. Measured: 0.3 when the stick is dead (the id -1 bug),
# 6.7 to 30 when walking (lowest values on a second walk in the same spot). 4.0 separates both with margin.
MOVE_THRESHOLD = 4.0
WALK_SECONDS = 4.5  # drag + hold time of every joystick test, so scene diffs are comparable

RESULTS = []


def diff(a, b, box):
    return round(imgdiff.region_diff(a, b, box, step=1), 2)


def log(msg):
    print(msg, flush=True)


def enter_hunt(p):
    """Reload the page and walk boot -> menu -> maps -> preparation -> hunt by touch."""
    p.navigate()
    if not p.wait_game_loaded():
        raise RuntimeError("game did not load")
    time.sleep(3)
    p.tap(422, 195); time.sleep(3.0)          # boot: "Toque para comecar"
    p.tap(216, 133); time.sleep(3.0)          # menu: Jogar
    p.tap(400, 95); time.sleep(3.0)           # maps: Mato Grosso
    p.tap(200, 110); time.sleep(1.0)          # contract 1
    p.tap(730, 352); time.sleep(12.0)         # Iniciar cacada
    p.shot("hunt_entered")


def drag_by(p, fid, x0, y0, dx, dy, steps, dt=0.02):
    for i in range(1, steps + 1):
        t = i / steps
        p.move(fid, x0 + dx * t, y0 + dy * t)
        time.sleep(dt)


def record(name, ok, detail):
    RESULTS.append({"test": name, "ok": ok, "detail": detail})
    log(f"  [{'OK ' if ok else 'FAIL'}] {name}: {detail}")


def joystick_test(p, fid, label, step=TINY_STEP, expect=True, stage=""):
    """Hold the stick forward ~2.5 s with finger id `fid`; the view must change."""
    n = int(50 / step)
    p.tap(*ARM_TAP, fid=fid); time.sleep(0.6)
    a = p.png(); time.sleep(0.3)
    p.down(fid, *JOY_START); time.sleep(0.15)
    t0 = time.time()
    drag_by(p, fid, JOY_START[0], JOY_START[1], 0, -step * n, n, dt=0.02 if step < 1 else 0.03)
    # Same walking time whatever the drag speed: a fast drag ends sooner, so it holds longer.
    p.hold(max(2.0, WALK_SECONDS - (time.time() - t0)), jitter_fid=fid)
    shot = p.shot(f"{label}_joy_during")
    b = p.png()
    p.up(fid); time.sleep(0.4)
    d = diff(a, b, SCENE)
    moved = d > MOVE_THRESHOLD
    record(f"joystick {label}{stage}", moved == expect, f"scene diff {d} (moved={moved}) {os.path.basename(shot)}")
    return moved


def look_test(p, fid, label, step=TINY_STEP, stage=""):
    n = int(50 / step)
    p.tap(*ARM_TAP, fid=fid); time.sleep(0.5)
    a = p.png()
    p.down(fid, *LOOK_START); time.sleep(0.15)
    drag_by(p, fid, LOOK_START[0], LOOK_START[1], step * n, 0, n)
    time.sleep(0.3)
    shot = p.shot(f"{label}_look_after")
    b = p.png()
    p.up(fid); time.sleep(0.3)
    d = diff(a, b, SCENE)
    record(f"look {label}{stage}", d > MOVE_THRESHOLD, f"scene diff {d} {os.path.basename(shot)}")


def fire_test(p, fid, label, stage=""):
    a = p.png()
    p.tap(*FIRE, hold=0.15, fid=fid); time.sleep(0.8)
    b = p.png()
    d = diff(a, b, AMMO)
    record(f"fire {label}{stage}", d > 1.0, f"ammo-panel diff {d}")


def battery(p, fid, label):
    log(f"--- battery, finger id {fid} ({label})")
    joystick_test(p, fid, label)
    look_test(p, fid, label)
    fire_test(p, fid, label)
    joystick_test(p, fid, label, stage=" (after look+fire)")


def pause_cycle(p, fid):
    log("--- pause / resume, finger id %s" % fid)
    a = p.png()
    p.tap(*PAUSE, fid=fid); time.sleep(1.0)
    p.shot("pause_open")
    b = p.png()
    record("pause button opens overlay", diff(a, b, (0, 0, 422, 195)) > 8.0, "whole-screen diff after pause tap")
    p.tap(*RESUME, fid=fid); time.sleep(1.0)
    p.shot("pause_closed")


def natural_drag(p, fid=1):
    """Human-like drag (5 css px per move). Documents finding B (touch mode flips off)."""
    log("--- natural drag speed (5 css px per touchmove)")
    joystick_test(p, fid, "natural", step=NORMAL_STEP, expect=True)


def multitouch(p, fa, fb, label):
    log(f"--- multitouch: joystick finger {fa}, look/fire finger {fb} ({label})")
    p.tap(*ARM_TAP, fid=fa); time.sleep(0.6)
    a = p.png()
    p.down(fa, *JOY_START); time.sleep(0.1)
    drag_by(p, fa, JOY_START[0], JOY_START[1], 0, -25, 50)
    p.down(fb, *LOOK_START); time.sleep(0.1)
    for i in range(100):   # keep the joystick finger alive while the second finger drags
        p.move(fb, LOOK_START[0] + 0.5 * (i + 1), LOOK_START[1]); time.sleep(0.02)
    p.hold(1.0, jitter_fid=fa)
    mid = p.png()
    p.shot(f"multi_{label}_during")
    p.up(fb); time.sleep(0.2)
    p.tap(*FIRE, fid=fb, hold=0.15); time.sleep(0.8)
    after_fire = p.png()
    p.shot(f"multi_{label}_fired")
    p.hold(1.5, jitter_fid=fa)
    c = p.png()
    p.shot(f"multi_{label}_after_fire")
    p.up(fa); time.sleep(0.3)
    d1, d2, d3 = diff(a, mid, SCENE), diff(mid, after_fire, AMMO), diff(after_fire, c, SCENE)
    record(f"multitouch {label}: view changed (move+look)", d1 > MOVE_THRESHOLD, f"diff {d1}")
    record(f"multitouch {label}: fire with joystick held", d2 > 1.0, f"ammo diff {d2}")
    record(f"multitouch {label}: joystick still walks after fire", d3 > 3.0, f"diff {d3}")


GROUPS = {
    "g1": lambda p: (battery(p, 1, "id1"), battery(p, 0, "id0")),
    "g2": lambda p: (battery(p, -1, "idm1"), battery(p, 7, "id7")),
    "g3": lambda p: (natural_drag(p), multitouch(p, 1, 2, "ids1-2"), multitouch(p, 7, 1000, "ids7-1000")),
    "g4": lambda p: (joystick_test(p, 1, "order", stage=" (before pause)"), pause_cycle(p, 1),
                     joystick_test(p, 1, "order", stage=" (after pause/resume)"),
                     look_test(p, 1, "order", stage=" (after pause/resume)")),
    # other ids. NOT in the default run: ids above ~100000 are rejected or wedge Chrome's touch emulation
    # (observed: 123456789 and 4e9 -> Internal error, 2147483647 -> dispatch timeout and a dead tab)
    "g5": lambda p: (battery(p, -5, "idm5"), battery(p, 99999, "id99999")),
    # finding B (fixed): a drag faster than ~1.08 css px per touchmove used to flip touch mode off, because the
    # mouse motion Godot emulates from touch reaches the game without DEVICE_ID_EMULATION on Web.
    # Every drag speed must walk now. Only run on request: --groups=g6
    "g6": lambda p: (joystick_test(p, 1, "step1.0", step=1.0), dom_types(p),
                     joystick_test(p, 1, "step1.3", step=1.3), dom_types(p),
                     joystick_test(p, 1, "step12.0", step=12.0)),
}


def dom_types(p):
    evs = p.dom_events(phase="cap")
    log("   DOM event types seen: " + ", ".join(sorted(set(e["type"] for e in evs))))


def main():
    wanted = ["g1", "g2", "g3", "g4", "g5"]
    for a in sys.argv[1:]:
        if a.startswith("--groups="):
            wanted = a.split("=", 1)[1].split(",")
        elif a == "--quick":
            wanted = ["g1", "g2"]
    p = Phone("probe")
    t0 = time.time()
    try:
        p.start()
        for g in wanted:
            log(f"=== group {g} (t+{int(time.time() - t0)}s)")
            try:
                enter_hunt(p)
                GROUPS[g](p)
            except Exception:
                traceback.print_exc()
                record(f"group {g} crashed", False, "exception, see traceback above")
                p.fingers.clear()
    finally:
        log("--- console tail")
        for line in (p.cdp.console[-15:] if p.cdp else []):
            log("   " + line)
        p.stop()
    out = os.path.join(SHOTS_DIR, "probe_results.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(RESULTS, f, indent=1)
    failed = [r for r in RESULTS if not r["ok"]]
    log(f"=== {len(RESULTS) - len(failed)} ok, {len(failed)} failed, {int(time.time() - t0)}s total; results {out}")
    for r in failed:
        log(f"FAILED: {r['test']}: {r['detail']}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
