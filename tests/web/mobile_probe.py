"""Mobile touch probe: drives the real Web build in headless Chrome (phone emulation) with real touch events.

    python tests/web/mobile_probe.py [--quick] [--groups=g1,g2,g3,g4,g5,g7] [--help]

Pipeline exercised: browser touch events -> Godot Web -> InputSetup -> TouchControls -> TouchJoystick /
LookPad -> move_* actions -> Player.  Serves build/web/ (must already be exported) and opens it with
?probe=1&hints=0 (hints=0 keeps the onboarding hint banner out of the pixel diffs, docs/arquitetura.md 8.4);
every assertion reads window.huntProbe (published by src/hud/hud.gd: x, z, yaw_deg, pitch_deg,
touch_mode, ammo_mag, health, joystick_active, sprinting, look_active, run_locked, t_ms, and since 1.3
items, busy_item, binoculars, touch_buttons).
Pixel diffs are used only where the hook has no field (pause overlay, aim zoom).
Stdlib only.  Screenshots + probe_results.json go to SHOTS_DIR (phone.py).  Exit code 0 only if every
expectation holds.  Chrome and the HTTP server are always killed on exit.

Groups (each starts a fresh hunt so the crop timer never ends the run):
  g1 hook, fixed joystick, sensitivity, two-finger pitch stability
  g2 run lock, fire-drag, reload, aim, natural/fast drag speed
  g3 finger ids 0, 1, -1      g4 finger ids 7, -5, 99999      g5 multitouch pairs, pause/resume
  g7 item buttons (1.3): layout from the probe, no overlap, tap the drone (-1), kit at full health (no spend)
Not in the default run (g6): ids above ~100000 are rejected or wedge Chrome's touch emulation.
"""
import json
import math
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imgdiff  # noqa: E402
from phone import Phone, SHOTS_DIR  # noqa: E402

# --- layout (CSS px, 844x390 landscape). The game viewport is 720 tall (stretch aspect=expand), so
# 1 css px = 720/390 viewport px.
VP_PER_CSS = 720.0 / 390.0
K = 1.0 / VP_PER_CSS
JOY = (190 * K, 303.0)                 # fixed stick centre: 190 px from left, 160 px from bottom (viewport px)
JOY_RADIUS_CSS = 90 * K                # 48.8 css px
JOY_ACTIVE_CSS = 90 * 1.7 * K          # 82.9 css px
LOOK_A = (450.0, 200.0)                # free spot (no button within ~60 css px), horizontal / vertical drags
FIRE = ((1558 - 125) * K, (720 - 130) * K)
AIM = ((1558 - 290) * K, (720 - 105) * K)
RELOAD = ((1558 - 100) * K, (720 - 285) * K)
PAUSE = (56 * K, 56 * K)
RESUME = (422.0, 166.0)

# Expected feel (data/game.json player.*)
DEG_PER_VP_PX = 0.115
PITCH_MULT = 0.65
DEG_PER_CSS_PX = DEG_PER_VP_PX * VP_PER_CSS

# Item and dog buttons (docs/arquitetura.md 8.4). Positions are READ from window.huntProbe.touch_buttons; these
# constants only say what the layout must be.  Centre of item i = (width - (380 + 96 i), height - 250).
URL_QUERY = "?probe=1&hints=0"
ITEM_ROW_RIGHT = 380.0
ITEM_ROW_STEP = 96.0
ITEM_ROW_BOTTOM = 250.0
ITEM_RADIUS = 38.0
HIT_PADDING = 8.0                      # TouchControls.HIT_PADDING_PX: a finger within radius + 8 presses the button
MIN_ITEM_TO_LOOK_CSS = 60.0            # LOOK_A must stay at least this far (css px) from every item button
FIRE_FROM_RIGHT, FIRE_FROM_BOTTOM = 125.0, 130.0    # Tiro button offsets (viewport px): gives the viewport size
JOY_FROM_LEFT = 190.0                  # fixed stick centre x (viewport px)
JOY_ACTIVE_VP = 90.0 * 1.7             # joystick radius x active_mult (viewport px)
ITEM_ACTIONS = ("use_medkit", "use_corn_bait", "use_scout_drone", "use_binoculars")
REMOVED_ACTIONS = ("use_item", "item_next")

SCENE = (85, 65, 260, 115)             # half-resolution PNG box (aim zoom)
RESULTS = []


# --- small helpers ---------------------------------------------------------
def log(msg):
    print(msg, flush=True)


def wrap(d):
    return (d + 180.0) % 360.0 - 180.0


def dyaw(a, b):
    return wrap(b["yaw_deg"] - a["yaw_deg"])


def dpitch(a, b):
    return b["pitch_deg"] - a["pitch_deg"]


def dist(a, b):
    return math.hypot(b["x"] - a["x"], b["z"] - a["z"])


def record(name, ok, measured):
    RESULTS.append({"test": name, "ok": bool(ok), "measured": measured})
    log(f"  [{'OK ' if ok else 'FAIL'}] {name}: {measured}")


def st(p, wait=0.4):
    """Settle, then return a fresh probe snapshot."""
    time.sleep(wait)
    s = p.fresh_probe()
    if s is None:
        raise RuntimeError("window.huntProbe is not published (page opened without ?probe=1, or the HUD is gone)")
    return s


def enter_hunt(p, first=False):
    """Reload the page and walk boot -> menu -> maps -> preparation -> hunt by touch; verify via the hook."""
    p.navigate()
    if not p.wait_game_loaded():
        raise RuntimeError("game did not load")
    time.sleep(6 if first else 3)
    p.tap(422, 195); time.sleep(3.0)          # boot: "Toque para comecar"
    p.tap(216, 133); time.sleep(3.0)          # menu: Jogar
    p.tap(400, 95); time.sleep(3.0)           # maps: Mato Grosso
    p.tap(200, 110); time.sleep(1.0)          # contract 1
    p.tap(730, 352); time.sleep(12.0)         # Iniciar cacada
    p.shot("hunt_entered")
    if p.fresh_probe(timeout=6.0) is None:
        raise RuntimeError("did not reach the hunt (no window.huntProbe)")


def drag_by(p, fid, x0, y0, dx, dy, step_css=4.0, dt=0.03):
    """Single-finger drag with ~step_css px per touchMove; returns the final position."""
    n = max(1, int(round(math.hypot(dx, dy) / step_css)))
    for i in range(1, n + 1):
        p.move(fid, x0 + dx * i / n, y0 + dy * i / n)
        time.sleep(dt)
    return (x0 + dx, y0 + dy)


def wiggle(i, base):
    """A real thumb is never still: a few px of jitter per event around `base`."""
    return (base[0] + 3.0 * math.sin(i * 0.9), base[1] + 2.0 * math.cos(i * 1.3))


# --- tests -------------------------------------------------------------------
def t_hook(p):
    a = st(p, 0.1); b = st(p, 0.6)
    record("hook: window.huntProbe publishes and t_ms advances", b["t_ms"] > a["t_ms"],
           f"t_ms {a['t_ms']} -> {b['t_ms']}")
    record("hook: touch_mode is true in the hunt on a touch device", b["touch_mode"], f"touch_mode={b['touch_mode']}")


def joystick_walk(p, fid, label, step=4.0, push_css=45.0, seconds=1.3, min_dist=2.0):
    """Fixed stick: press near the centre, push up, hold, release."""
    a = st(p, 0.2)
    start = (JOY[0] + 10, JOY[1] - 5)
    p.down(fid, *start); time.sleep(0.15)
    mid = st(p, 0.2)
    pos = drag_by(p, fid, start[0], start[1], 0, -push_css, step_css=step)
    for i in range(int(seconds / 0.1)):
        p.move(fid, *wiggle(i, pos)); time.sleep(0.1)
    b = st(p, 0.1)
    p.up(fid)
    c = st(p, 0.5)
    d = dist(a, b)
    ok = mid["joystick_active"] and d >= min_dist and b["touch_mode"] and c["touch_mode"] and not c["joystick_active"]
    record(f"joystick walks, {label}", ok,
           f"active_on_press={mid['joystick_active']} moved={d:.2f} m touch_mode={c['touch_mode']} active_after_up={c['joystick_active']}")
    return b


def look_drag(p, fid, label, dx, dy, start=LOOK_A, step=4.0, min_yaw=5.0):
    a = st(p, 0.2)
    p.down(fid, *start); time.sleep(0.1)
    mid = st(p, 0.15)
    drag_by(p, fid, start[0], start[1], dx, dy, step_css=step)
    b = st(p, 0.4)
    p.up(fid)
    c = st(p, 0.4)
    ok = mid["look_active"] and abs(dyaw(a, b)) >= min_yaw and b["touch_mode"] and not mid["joystick_active"]
    record(f"look drags the camera, {label}", ok,
           f"look_active={mid['look_active']} d_yaw={dyaw(a, b):.2f} deg d_pitch={dpitch(a, b):.2f} touch_mode={b['touch_mode']}")
    return a, b, c


def t_fixed_joystick(p):
    log("--- fixed joystick")
    joystick_walk(p, 1, "press near the centre (+10,-5 css px)")
    # far from the centre in the left half: must LOOK, not move
    far = (100.0, 150.0)
    a = st(p, 0.2)
    p.down(1, *far); time.sleep(0.15)
    m = st(p, 0.15)
    drag_by(p, 1, far[0], far[1], 40, 0)
    b = st(p, 0.4)
    p.up(1); st(p, 0.3)
    record("left half, far from the stick: look, not joystick", (not m["joystick_active"]) and m["look_active"] and abs(dyaw(a, b)) > 3.0,
           f"joystick_active={m['joystick_active']} look_active={m['look_active']} d_yaw={dyaw(a, b):.2f} walked={dist(a, b):.2f} m")
    # just inside / just outside the 1.7x active radius (82.9 css px)
    for name, off, want_joy in (("inside the active radius (75 css px right)", 75.0, True),
                                ("outside the active radius (92 css px right)", 92.0, False)):
        pos = (JOY[0] + off, JOY[1])
        p.down(1, *pos); time.sleep(0.15)
        m = st(p, 0.15)
        p.up(1); st(p, 0.3)
        record(f"touch {name}", m["joystick_active"] == want_joy and m["look_active"] == (not want_joy),
               f"joystick_active={m['joystick_active']} look_active={m['look_active']}")


def t_sensitivity(p):
    log("--- sensitivity (expected %.4f deg/viewport px = %.4f deg/css px, pitch x%.2f)" %
        (DEG_PER_VP_PX, DEG_PER_CSS_PX, PITCH_MULT))
    n_css = 100.0
    a, b, _ = look_drag(p, 1, "horizontal 100 css px", -n_css, 0, start=(520.0, 120.0), step=4.0, min_yaw=5.0)
    per_css = abs(dyaw(a, b)) / n_css
    per_vp = per_css / VP_PER_CSS
    record("sensitivity yaw: 0.115 deg/viewport px +-15%", abs(per_vp - DEG_PER_VP_PX) <= 0.15 * DEG_PER_VP_PX,
           f"{per_css:.4f} deg/css px = {per_vp:.4f} deg/viewport px (d_yaw={dyaw(a, b):.2f}, d_pitch={dpitch(a, b):.2f})")
    m_css = 60.0
    a, b, _ = look_drag(p, 1, "vertical 60 css px", 0, m_css, start=(520.0, 130.0), step=4.0, min_yaw=0.0)
    pitch_per_vp = abs(dpitch(a, b)) / (m_css * VP_PER_CSS)
    ratio = pitch_per_vp / per_vp if per_vp else 0.0
    record("sensitivity pitch: 0.65 x yaw +-15%", abs(ratio - PITCH_MULT) <= 0.15 * PITCH_MULT,
           f"{pitch_per_vp:.4f} deg/viewport px, ratio to yaw {ratio:.3f} (d_pitch={dpitch(a, b):.2f}, d_yaw={dyaw(a, b):.2f})")


def two_fingers(p, ida, idb, axis, same_event, label):
    """Finger A holds the stick forward (jittering like a thumb); finger B drags the look on one axis only."""
    base = (JOY[0], JOY[1] - 45.0)
    n = 20
    p.down(ida, JOY[0] + 2, JOY[1]); time.sleep(0.1)
    for i in range(1, 13):
        p.move(ida, JOY[0] + 2, JOY[1] - 45.0 * i / 12); time.sleep(0.03)
    bstart = LOOK_A if axis == "x" else (LOOK_A[0], LOOK_A[1] - 30.0)
    p.down(idb, *bstart); time.sleep(0.15)
    a = st(p, 0.2)
    total = 80.0 if axis == "x" else 60.0
    for i in range(1, n + 1):
        t = i / n
        bpos = (bstart[0] + total * t, bstart[1]) if axis == "x" else (bstart[0], bstart[1] + total * t)
        apos = wiggle(i, base)
        if same_event:
            p.move_many({ida: apos, idb: bpos})
        else:
            p.move(ida, *apos); time.sleep(0.015); p.move(idb, *bpos)
        time.sleep(0.04)
    for i in range(8):                      # keep walking a little after B stops
        p.move(ida, *wiggle(30 + i, base)); time.sleep(0.1)
    b = st(p, 0.1)
    p.up(idb); p.up(ida)
    st(p, 0.3)
    exp_yaw = total * DEG_PER_CSS_PX
    exp_pitch = total * DEG_PER_CSS_PX * PITCH_MULT
    walked = dist(a, b)
    if axis == "x":
        ok = abs(dpitch(a, b)) < 1.5 and abs(abs(dyaw(a, b)) - exp_yaw) <= 0.2 * exp_yaw and walked >= 1.5
        record(f"two fingers, B horizontal, {label}", ok,
               f"d_pitch={dpitch(a, b):.2f} deg (limit 1.5) d_yaw={dyaw(a, b):.2f} (expected {exp_yaw:.1f}) walked={walked:.2f} m")
    else:
        ok = abs(dyaw(a, b)) < 1.5 and abs(abs(dpitch(a, b)) - exp_pitch) <= 0.25 * exp_pitch and walked >= 1.5
        record(f"two fingers, B vertical, {label}", ok,
               f"d_yaw={dyaw(a, b):.2f} deg (limit 1.5) d_pitch={dpitch(a, b):.2f} (expected {exp_pitch:.1f}) walked={walked:.2f} m")


def t_two_fingers(p):
    log("--- two fingers: stick finger moving + look finger (the reported pitch jump)")
    for axis in ("x", "y"):
        for same in (False, True):
            two_fingers(p, 1, 2, axis, same, "separate touchMove events" if not same else "both fingers in one touchMove")


def t_run_lock(p):
    log("--- run lock")
    start = (JOY[0], JOY[1])
    p.down(1, *start); time.sleep(0.1)
    drag_by(p, 1, start[0], start[1], 0, -105.0, step_css=6.0)   # 105 css = 2.15 x radius, lock at 1.8
    m = st(p, 0.4)
    p.up(1)
    s1 = st(p, 0.5)
    time.sleep(2.0)
    s2 = st(p, 0.1)
    record("run lock engages when pushed far up", m["run_locked"],
           f"run_locked={m['run_locked']} (finger down) sprinting={m['sprinting']}")
    record("run lock keeps running with the finger lifted for 2 s", s1["run_locked"] and s2["sprinting"] and dist(s1, s2) >= 4.0 and not s2["joystick_active"],
           f"run_locked={s1['run_locked']} sprinting={s2['sprinting']} moved={dist(s1, s2):.2f} m in 2 s joystick_active={s2['joystick_active']}")
    p.tap(JOY[0], JOY[1], hold=0.15, fid=1)
    s3 = st(p, 0.6)
    s4 = st(p, 1.0)
    record("touching the stick again unlocks the run and stops", (not s3["run_locked"]) and (not s3["sprinting"]) and dist(s3, s4) < 0.4,
           f"run_locked={s3['run_locked']} sprinting={s3['sprinting']} moved_after={dist(s3, s4):.2f} m")


def t_fire_and_reload(p):
    log("--- fire (tap / drag) and reload")
    a = st(p, 0.2)
    p.tap(*FIRE, hold=0.15, fid=1)
    b = st(p, 0.6)
    record("fire tap: ammo drops, camera does not move", b["ammo_mag"] < a["ammo_mag"] and abs(dyaw(a, b)) < 0.3 and abs(dpitch(a, b)) < 0.3,
           f"ammo {a['ammo_mag']} -> {b['ammo_mag']} d_yaw={dyaw(a, b):.2f} d_pitch={dpitch(a, b):.2f}")
    p.down(1, *FIRE); time.sleep(0.1)
    drag_by(p, 1, FIRE[0], FIRE[1], -40.0, 0, step_css=4.0)
    for i in range(8):
        p.move(1, FIRE[0] - 40.0 + (i % 2), FIRE[1]); time.sleep(0.1)
    c = st(p, 0.2)
    p.up(1)
    c2 = st(p, 0.5)
    record("fire held + drag: ammo drops and the camera turns", c2["ammo_mag"] < b["ammo_mag"] and abs(dyaw(b, c)) > 3.0 and c2["touch_mode"],
           f"ammo {b['ammo_mag']} -> {c2['ammo_mag']} d_yaw={dyaw(b, c):.2f} d_pitch={dpitch(b, c):.2f}")
    before = c2["ammo_mag"]
    p.tap(*RELOAD, hold=0.15, fid=1)
    time.sleep(3.0)
    d = st(p, 0.2)
    if d["ammo_mag"] <= before:
        time.sleep(3.0)
        d = st(p, 0.2)
    record("reload button refills the magazine", d["ammo_mag"] > before, f"ammo {before} -> {d['ammo_mag']}")


def t_aim(p):
    log("--- aim (toggle button; zoom shown by pixel diff, camera by hook)")
    a = st(p, 0.2)
    base = p.png()
    p.down(1, *AIM); time.sleep(0.15)
    drag_by(p, 1, AIM[0], AIM[1], -40.0, 0, step_css=4.0)
    time.sleep(0.2)
    p.up(1)
    b = st(p, 0.8)
    zoomed = p.png()
    p.shot("aim_on")
    d_on = round(imgdiff.region_diff(base, zoomed, SCENE, step=1), 2)
    record("aim button held + drag: view zooms and the camera still turns", d_on > 5.0 and abs(dyaw(a, b)) > 1.0,
           f"scene diff {d_on} d_yaw={dyaw(a, b):.2f} deg")
    p.tap(*AIM, hold=0.15, fid=1)
    time.sleep(1.0)
    off = p.png()
    d_off = round(imgdiff.region_diff(zoomed, off, SCENE, step=1), 2)
    d_back = round(imgdiff.region_diff(base, off, SCENE, step=1), 2)
    record("aim button tapped again: zoom turns off (view back to the un-zoomed one)", d_off > 5.0 and d_back < d_on,
           f"diff zoomed->off {d_off}, diff un-zoomed->off {d_back} (zoomed vs un-zoomed was {d_on})")


def t_drag_speeds(p):
    log("--- drag speed: touch mode must never switch off")
    for label, step in (("natural drag, 5 css px per event", 5.0), ("fast drag, 15 css px per event", 15.0)):
        joystick_walk(p, 1, label, step=step, push_css=48.0)
        look_drag(p, 1, label, 120, 0, start=(300.0, 120.0), step=step, min_yaw=10.0)


def battery(p, fid, label):
    log(f"--- battery, finger id {fid}")
    joystick_walk(p, fid, f"id {fid}")
    look_drag(p, fid, f"id {fid}", -60.0, 0, start=(450.0, 120.0))
    a = st(p, 0.2)
    p.tap(*FIRE, hold=0.15, fid=fid)
    b = st(p, 0.6)
    record(f"fire id {fid}", b["ammo_mag"] < a["ammo_mag"], f"ammo {a['ammo_mag']} -> {b['ammo_mag']}")
    joystick_walk(p, fid, f"id {fid} (after look + fire)")


def multitouch(p, ida, idb):
    log(f"--- multitouch: stick finger {ida}, look/fire finger {idb}")
    base = (JOY[0], JOY[1] - 45.0)
    p.down(ida, JOY[0] + 2, JOY[1]); time.sleep(0.1)
    drag_by(p, ida, JOY[0] + 2, JOY[1], 0, -45.0, step_css=4.0)
    a = st(p, 0.2)
    p.down(idb, *LOOK_A); time.sleep(0.1)
    for i in range(1, 21):
        p.move(ida, *wiggle(i, base)); time.sleep(0.015)
        p.move(idb, LOOK_A[0] + 4.0 * i, LOOK_A[1]); time.sleep(0.04)
    b = st(p, 0.1)
    p.up(idb); time.sleep(0.2)
    p.tap(*FIRE, hold=0.15, fid=idb)
    c = st(p, 0.4)
    for i in range(10):
        p.move(ida, *wiggle(40 + i, base)); time.sleep(0.1)
    d = st(p, 0.1)
    p.up(ida)
    e = st(p, 0.4)
    record(f"multitouch ids {ida}+{idb}: walks and turns, pitch stable", dist(a, b) >= 1.0 and abs(dyaw(a, b)) > 8.0 and abs(dpitch(a, b)) < 1.5,
           f"walked={dist(a, b):.2f} m d_yaw={dyaw(a, b):.2f} d_pitch={dpitch(a, b):.2f}")
    record(f"multitouch ids {ida}+{idb}: fire with the stick held", c["ammo_mag"] < b["ammo_mag"] and c["joystick_active"],
           f"ammo {b['ammo_mag']} -> {c['ammo_mag']} joystick_active={c['joystick_active']}")
    record(f"multitouch ids {ida}+{idb}: still walking after the shot, ends clean", dist(c, d) >= 1.0 and not e["joystick_active"] and not e["look_active"] and e["touch_mode"],
           f"walked={dist(c, d):.2f} m after active={e['joystick_active']}/{e['look_active']} touch_mode={e['touch_mode']}")


def t_pause(p):
    log("--- pause / resume")
    a = p.png()
    p.tap(*PAUSE, hold=0.15, fid=1)
    time.sleep(1.0)
    p.shot("pause_open")
    b = p.png()
    d = round(imgdiff.region_diff(a, b, (0, 0, 422, 195), step=2), 2)
    record("pause button opens the overlay (pixel diff)", d > 8.0, f"whole-screen diff {d}")
    p.tap(*RESUME, hold=0.15, fid=1)
    time.sleep(1.0)
    p.shot("pause_closed")
    s = st(p, 0.2)
    record("after resume: no stuck finger, touch mode on", (not s["joystick_active"]) and (not s["look_active"]) and s["touch_mode"],
           f"joystick_active={s['joystick_active']} look_active={s['look_active']} touch_mode={s['touch_mode']}")
    joystick_walk(p, 1, "after pause/resume")
    look_drag(p, 1, "after pause/resume", -60.0, 0, start=(450.0, 120.0))


def viewport_from_probe(tb):
    """Viewport size (px) derived from the Tiro button, which sits at (w - 125, h - 130)."""
    fire = tb.get("fire")
    if not fire:
        return None
    return fire[0] + FIRE_FROM_RIGHT, fire[1] + FIRE_FROM_BOTTOM


def tap_vp(p, x_vp, y_vp, hold=0.15, fid=1):
    """Tap at a viewport-px position (the probe reports viewport px; Phone.tap takes css px)."""
    p.tap(x_vp * K, y_vp * K, hold=hold, fid=fid)


def t_items(p):
    log("--- item buttons (layout from the probe, no overlap, tap behaviour)")
    s = st(p, 0.3)
    fields = ("items", "busy_item", "binoculars", "touch_buttons")
    missing = [f for f in fields if f not in s]
    record("probe publishes items, busy_item, binoculars, touch_buttons", not missing,
           f"missing={missing}" if missing else f"items={s.get('items')} busy_item={s.get('busy_item')!r} binoculars={s.get('binoculars')}")
    if missing:
        return
    tb = s["touch_buttons"]
    items = s["items"]
    if "hint" in s:
        record("hints=0 in the URL keeps the hint director off", s["hint"] == "", f"hint={s['hint']!r}")
    size = viewport_from_probe(tb)
    if size is None:
        record("touch_buttons has the Tiro button", False, f"touch_buttons={tb}")
        return
    w, h = size

    # --- layout: which buttons exist, and where
    carried = [a for a in ITEM_ACTIONS if a.replace("use_", "", 1) in items]
    present = [a for a in ITEM_ACTIONS if a in tb]
    record("a button for every usable item carried and for none of the others", present == carried,
           f"items={sorted(items)} item buttons={present}")
    record("no button for the removed actions use_item / item_next", not any(a in tb for a in REMOVED_ACTIONS),
           f"present={[a for a in REMOVED_ACTIONS if a in tb]}")
    record("no dog button when the hunt has no dog (default loadout)", "dog_command" not in tb,
           f"dog_command in touch_buttons={'dog_command' in tb}")
    bad = []
    for i, action in enumerate(carried):          # carried keeps ITEM_ACTIONS order = slot order
        want = (w - (ITEM_ROW_RIGHT + ITEM_ROW_STEP * i), h - ITEM_ROW_BOTTOM)
        got = tb.get(action)
        if not got:
            bad.append(f"{action}: no button")
        elif abs(got[0] - want[0]) > 1.0 or abs(got[1] - want[1]) > 1.0 or abs(got[2] - ITEM_RADIUS) > 0.5:
            bad.append(f"{action}: got ({got[0]:.1f}, {got[1]:.1f}, r {got[2]:.1f}) want ({want[0]:.1f}, {want[1]:.1f}, r {ITEM_RADIUS})")
    record("item buttons sit at (w - (380 + 96 i), h - 250), radius 38", not bad and bool(carried),
           "; ".join(bad) if bad else f"viewport {w:.0f}x{h:.0f}, buttons={carried}")

    # --- no overlap: item and dog buttons against every other button (hit circle = radius + padding)
    close = []
    names = list(tb)
    mine = [a for a in names if a in ITEM_ACTIONS or a == "dog_command"]
    for a in mine:
        for b in names:
            if a == b or (b in mine and names.index(b) < names.index(a)):
                continue   # each pair of item/dog buttons is checked once
            ax, ay, ar = tb[a]
            bx, by, br = tb[b]
            gap = math.hypot(ax - bx, ay - by) - (ar + HIT_PADDING) - (br + HIT_PADDING)
            if gap < 0.0:
                close.append(f"{a}/{b} overlap by {-gap:.1f} px")
    record("item and dog buttons do not overlap any other button", not close,
           "; ".join(close) or f"{len(mine)} item/dog buttons against {len(names)} buttons")
    stick_right = JOY_FROM_LEFT + JOY_ACTIVE_VP
    inside = [a for a in carried if a in tb and tb[a][0] - tb[a][2] <= stick_right]
    record("item buttons stay outside the joystick active area", not inside,
           f"stick active area ends at x={stick_right:.0f}; inside: {inside}" if inside else f"stick area ends at x={stick_right:.0f}")
    near_look = []
    for a in carried:
        if a not in tb:
            continue
        d_css = math.hypot(tb[a][0] * K - LOOK_A[0], tb[a][1] * K - LOOK_A[1])
        if d_css < MIN_ITEM_TO_LOOK_CSS:
            near_look.append(f"{a} {d_css:.0f} css px")
    record("free look spot LOOK_A is at least 60 css px from every item button", not near_look,
           "; ".join(near_look) or f"LOOK_A={LOOK_A}")

    # --- tap the kit at full health: nothing is spent and nothing starts
    if "use_medkit" in tb and items.get("medkit", 0) > 0 and s["health"] >= 99.9:
        a = st(p, 0.2)
        tap_vp(p, tb["use_medkit"][0], tb["use_medkit"][1])
        b = st(p, 0.7)
        record("kit tapped at full health: not spent, no use in progress, camera still",
               b["items"].get("medkit") == a["items"].get("medkit") and b["busy_item"] == "" and abs(dyaw(a, b)) < 0.3
               and abs(dpitch(a, b)) < 0.3 and b["touch_mode"],
               f"medkit {a['items'].get('medkit')} -> {b['items'].get('medkit')} busy_item={b['busy_item']!r} "
               f"d_yaw={dyaw(a, b):.2f} d_pitch={dpitch(a, b):.2f} touch_mode={b['touch_mode']}")
    else:
        record("kit tapped at full health (precondition: kit carried, count > 0, full health)", False,
               f"use_medkit in touch_buttons={'use_medkit' in tb} items={items} health={s['health']}")

    # --- tap the drone: -1 per tap down to 0, then it stays at 0 (never negative)
    if "use_scout_drone" in tb and items.get("scout_drone", 0) > 0:
        n0 = int(items["scout_drone"])
        cx, cy = tb["use_scout_drone"][0], tb["use_scout_drone"][1]
        a = st(p, 0.2)
        seen = [n0]
        for _ in range(n0 + 1):
            tap_vp(p, cx, cy)
            seen.append(int(st(p, 0.7)["items"].get("scout_drone", -99)))
            time.sleep(0.2)
        b = st(p, 0.2)
        expected = [max(n0 - k, 0) for k in range(n0 + 2)]
        record("drone tapped: count drops by 1 per tap, stops at 0 and never goes negative", seen == expected,
               f"counts {seen} expected {expected}")
        record("drone taps do not move the camera and keep touch mode",
               abs(dyaw(a, b)) < 0.3 and abs(dpitch(a, b)) < 0.3 and b["touch_mode"],
               f"d_yaw={dyaw(a, b):.2f} d_pitch={dpitch(a, b):.2f} touch_mode={b['touch_mode']}")
    else:
        record("drone tapped (precondition: drone carried with count > 0)", False,
               f"use_scout_drone in touch_buttons={'use_scout_drone' in tb} items={items}")

    # --- Tiro still works with the row present (Mira and Recarregar are covered by g2)
    a = st(p, 0.2)
    p.tap(*FIRE, hold=0.15, fid=1)
    b = st(p, 0.6)
    record("Tiro still fires with the item row present", b["ammo_mag"] < a["ammo_mag"],
           f"ammo {a['ammo_mag']} -> {b['ammo_mag']}")


GROUPS = {
    "g1": lambda p: (t_hook(p), t_fixed_joystick(p), t_sensitivity(p), t_two_fingers(p)),
    "g2": lambda p: (t_run_lock(p), t_fire_and_reload(p), t_aim(p), t_drag_speeds(p)),
    "g3": lambda p: [battery(p, i, str(i)) for i in (0, 1, -1)],
    "g4": lambda p: [battery(p, i, str(i)) for i in (7, -5, 99999)],
    "g5": lambda p: (multitouch(p, 1, 2), multitouch(p, 7, 1000), multitouch(p, -1, 0), t_pause(p)),
    "g6": lambda p: battery(p, 2147483647, "int32 max"),
    "g7": lambda p: t_items(p),
}
DEFAULT = ["g1", "g2", "g3", "g4", "g5", "g7"]


def main():
    wanted = DEFAULT
    for a in sys.argv[1:]:
        if a.startswith("--groups=") and all(g in GROUPS for g in a.split("=", 1)[1].split(",")):
            wanted = a.split("=", 1)[1].split(",")
        elif a == "--quick":
            wanted = ["g1", "g2"]
        else:
            print(__doc__)
            return 0 if a in ("--help", "-h") else 2
    p = Phone("probe", query=URL_QUERY)
    t0 = time.time()
    try:
        p.start()
        for n, g in enumerate(wanted):
            log(f"=== group {g} (t+{int(time.time() - t0)}s)")
            try:
                enter_hunt(p, first=(n == 0))
                GROUPS[g](p)
            except Exception:
                traceback.print_exc()
                record(f"group {g} crashed", False, "exception, see traceback above")
            finally:
                try:
                    for fid in list(p.fingers):
                        p.up(fid)
                except Exception:
                    p.fingers.clear()
    finally:
        p.stop()
    out = os.path.join(SHOTS_DIR, "probe_results.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(RESULTS, f, indent=1)
    failed = [r for r in RESULTS if not r["ok"]]
    log(f"=== {len(RESULTS) - len(failed)} ok, {len(failed)} failed, {int(time.time() - t0)}s total; results {out}")
    for r in failed:
        log(f"FAILED: {r['test']}: {r['measured']}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
