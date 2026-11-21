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
  g7 Cura / Accessories buttons, tab and list, weapon cards, two Tiro buttons (HF7, was the item row of 1.3): layout
     from the probe, no overlap, pick and tap the drone (-1), kit at full health (no spend), card swap, both Tiro buttons
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
JOY = (242 * K, (720 - 220) * K)       # fixed stick centre: 242 px from left, 220 px from bottom (viewport px)
JOY_RADIUS_CSS = 90 * K                # 48.8 css px
JOY_ACTIVE_CSS = 90 * 1.7 * K          # 82.9 css px
LOOK_A = (450.0, 200.0)                # free spot (no button within ~60 css px), horizontal / vertical drags
FIRE = ((1558 - 245) * K, (720 - 181) * K)         # right Tiro, d 120
FIRE_LEFT = (69 * K, (720 - 355) * K)              # left Tiro, d 100 (same action)
AIM = ((1558 - 108) * K, (720 - 342) * K)
RELOAD = ((1558 - 359) * K, (720 - 47) * K)
PAUSE = (56 * K, 56 * K)
RESUME = (422.0, 166.0)

# Expected feel (data/game.json player.*)
DEG_PER_VP_PX = 0.115
PITCH_MULT = 0.65
DEG_PER_CSS_PX = DEG_PER_VP_PX * VP_PER_CSS

# Item, dog and weapon-card controls (docs/arquitetura.md 8.4, HF7 PUBG-style layout). Positions are READ from
# window.huntProbe.touch_buttons; these constants only say what the layout must be.  The kit is the Cura button and the
# other items share ONE Accessories button (named by the action of the current accessory) with a tab and an upward list;
# both sit on the line 50 px above the bottom edge.
URL_QUERY = "?probe=1&hints=0"
CURA_RADIUS, ACC_RADIUS = 32.0, 35.0
BLOCK_BOTTOM = 50.0
HIT_PADDING = 8.0                      # TouchControls.HIT_PADDING_PX: a finger within radius + 8 presses the button
MIN_ITEM_TO_LOOK_CSS = 60.0            # LOOK_A must stay at least this far (css px) from every item button
FIRE_FROM_RIGHT, FIRE_FROM_BOTTOM = 245.0, 181.0    # right Tiro button offsets (viewport px): gives the viewport size
JOY_FROM_LEFT = 242.0                  # fixed stick centre x (viewport px)
JOY_FROM_BOTTOM = 220.0
JOY_ACTIVE_VP = 90.0 * 1.7             # joystick radius x active_mult (viewport px)
ACCESSORY_ACTIONS = ("use_corn_bait", "use_scout_drone", "use_binoculars")   # InputSetup.ITEM_ACTIONS without the kit
ITEM_ACTIONS = ("use_medkit",) + ACCESSORY_ACTIONS
REMOVED_ACTIONS = ("use_item", "item_next", "weapon_swap")
NON_CIRCLES = ("accessory_menu",)      # touch_buttons entries that are a tab, a list row or a card, not a round button

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
    p.tap(150, 197); time.sleep(3.0)          # menu (poster style, 0.7.3+): JOGAR, opens the map list directly
    p.tap(400, 110); time.sleep(3.0)          # maps: Mato Grosso card
    p.tap(200, 110); time.sleep(1.0)          # preparation: contract 1 (already selected)
    p.tap(730, 352); time.sleep(12.0)         # Iniciar cacada
    p.shot("hunt_entered")
    if p.fresh_probe(timeout=6.0) is None:
        raise RuntimeError("did not reach the hunt (no window.huntProbe)")
    settle_frames(p)


def settle_frames(p, timeout=40.0):
    """The first seconds of a hunt stall the (software-rendered) page: publishes arrive seconds apart, so a read
    right after a touch can predate it.  Wait until 3 consecutive publishes are < 400 ms apart."""
    end = time.time() + timeout
    last_t, smooth = None, 0
    while time.time() < end and smooth < 3:
        s = p.fresh_probe(timeout=5.0)
        if s is None:
            continue
        smooth = smooth + 1 if last_t is not None and 0 < s["t_ms"] - last_t < 400 else 0
        last_t = s["t_ms"]
        time.sleep(0.05)


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
    """Viewport size (px) derived from the right Tiro button, which sits at (w - 245, h - 181)."""
    fire = tb.get("fire")
    if not fire:
        return None
    return fire[0] + FIRE_FROM_RIGHT, fire[1] + FIRE_FROM_BOTTOM


def tap_vp(p, x_vp, y_vp, hold=0.15, fid=1):
    """Tap at a viewport-px position (the probe reports viewport px; Phone.tap takes css px)."""
    p.tap(x_vp * K, y_vp * K, hold=hold, fid=fid)


def is_round_button(name):
    return name not in NON_CIRCLES and not name.startswith("accessory_item_") and not name.startswith("weapon_card_")


def t_items(p):
    log("--- Cura / Accessories buttons, tab and list, weapon cards, two Tiro buttons (layout from the probe, taps)")
    s = st(p, 0.3)
    fields = ("items", "busy_item", "binoculars", "touch_buttons", "weapon_slot", "accessory", "accessory_menu_open")
    missing = [f for f in fields if f not in s]
    record("probe publishes items, busy_item, binoculars, touch_buttons, weapon_slot, accessory, accessory_menu_open", not missing,
           f"missing={missing}" if missing else f"items={s.get('items')} busy_item={s.get('busy_item')!r} accessory={s.get('accessory')!r}")
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
    carried_acc = [a for a in ACCESSORY_ACTIONS if a.replace("use_", "", 1) in items]
    present_acc = [a for a in ACCESSORY_ACTIONS if a in tb]
    record("one Accessories button (the current accessory) when any accessory is carried, none otherwise",
           len(present_acc) == (1 if carried_acc else 0) and (not present_acc or present_acc[0] in carried_acc),
           f"items={sorted(items)} accessory buttons={present_acc} current={s['accessory']!r}")
    record("Cura button exists only with the kit", ("use_medkit" in tb) == ("medkit" in items),
           f"medkit in items={'medkit' in items} use_medkit in touch_buttons={'use_medkit' in tb}")
    record("no button for the removed actions use_item / item_next / weapon_swap", not any(a in tb for a in REMOVED_ACTIONS),
           f"present={[a for a in REMOVED_ACTIONS if a in tb]}")
    record("no dog button when the hunt has no dog (default loadout)", "dog_command" not in tb,
           f"dog_command in touch_buttons={'dog_command' in tb}")
    bad = []
    for name, want in (("fire_left", (69.0, h - 355.0, 50.0)), ("fire", (w - 245.0, h - 181.0, 60.0)),
                       ("aim", (w - 108.0, h - 342.0, 38.0)), ("reload", (w - 359.0, h - 47.0, 32.0)),
                       ("crouch", (w - 253.0, h - 53.0, 36.0))):
        got = tb.get(name)
        if not got:
            bad.append(f"{name}: no button")
        elif abs(got[0] - want[0]) > 1.0 or abs(got[1] - want[1]) > 1.0 or abs(got[2] - want[2]) > 0.5:
            bad.append(f"{name}: got ({got[0]:.1f}, {got[1]:.1f}, r {got[2]:.1f}) want ({want[0]:.1f}, {want[1]:.1f}, r {want[2]})")
    for name, radius in [("use_medkit", CURA_RADIUS)] + [(a, ACC_RADIUS) for a in present_acc]:
        got = tb.get(name)
        if got and (abs(got[1] - (h - BLOCK_BOTTOM)) > 1.0 or abs(got[2] - radius) > 0.5):
            bad.append(f"{name}: got ({got[0]:.1f}, {got[1]:.1f}, r {got[2]:.1f}) want y {h - BLOCK_BOTTOM:.1f} r {radius}")
    record("fixed buttons, Cura and Accessories sit where the layout table says", not bad,
           "; ".join(bad) if bad else f"viewport {w:.0f}x{h:.0f}")
    cards = sorted(a for a in tb if a.startswith("weapon_card_"))
    record("weapon cards are published (one per weapon carried, at most 2)", 1 <= len(cards) <= 2, f"cards={cards}")

    # --- tab: only with two or more accessories
    record("the tab (accessory_menu) exists only with 2+ accessories", ("accessory_menu" in tb) == (len(carried_acc) >= 2),
           f"accessories carried={carried_acc} accessory_menu in touch_buttons={'accessory_menu' in tb}")

    # --- no overlap: every round button against every other (hit circle = radius + padding)
    close = []
    names = [n for n in tb if is_round_button(n)]
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ax, ay, ar = tb[a]
            bx, by, br = tb[b]
            gap = math.hypot(ax - bx, ay - by) - (ar + HIT_PADDING) - (br + HIT_PADDING)
            if gap < 0.0:
                close.append(f"{a}/{b} overlap by {-gap:.1f} px")
    record("no round button overlaps another (radius + hit padding)", not close,
           "; ".join(close) or f"{len(names)} round buttons")
    stick = (JOY_FROM_LEFT, h - JOY_FROM_BOTTOM)
    inside = [a for a in ("use_medkit",) + tuple(present_acc) if a in tb
              and math.hypot(tb[a][0] - stick[0], tb[a][1] - stick[1]) - tb[a][2] <= JOY_ACTIVE_VP]
    record("Cura and Accessories stay outside the joystick active area", not inside,
           f"stick active radius {JOY_ACTIVE_VP:.0f} px; inside: {inside}" if inside else f"stick active radius {JOY_ACTIVE_VP:.0f} px")
    near_look = []
    for a in ("use_medkit",) + tuple(present_acc):
        if a not in tb:
            continue
        d_css = math.hypot(tb[a][0] * K - LOOK_A[0], tb[a][1] * K - LOOK_A[1])
        if d_css < MIN_ITEM_TO_LOOK_CSS:
            near_look.append(f"{a} {d_css:.0f} css px")
    record("free look spot LOOK_A is at least 60 css px from Cura and Accessories", not near_look,
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

    # --- the drone: when it is not the current accessory, open the list from the tab and pick it (it must NOT be used),
    #     then tap the main button: -1 per tap down to 0, then it stays at 0 (never negative).  The default profile
    #     carries a single accessory (the drone), so the list flow only runs with a bigger loadout.
    if "scout_drone" in items and items.get("scout_drone", 0) > 0 and (s["accessory"] == "scout_drone" or "accessory_menu" in tb):
        n0 = int(items["scout_drone"])
        a = st(p, 0.2)
        if s["accessory"] != "scout_drone":
            tap_vp(p, tb["accessory_menu"][0], tb["accessory_menu"][1])
            m = st(p, 0.8)
            row = m["touch_buttons"].get("accessory_item_scout_drone")
            record("tab tapped: the list opens upward with a row for the drone", bool(m["accessory_menu_open"]) and bool(row)
                   and row[1] < tb[present_acc[0]][1] - 60.0, f"open={m['accessory_menu_open']} row={row}")
            if row:
                tap_vp(p, row[0], row[1])
            c = st(p, 0.8)
            record("picking the drone in the list closes it, makes it current and does not use it",
                   c["accessory"] == "scout_drone" and not c["accessory_menu_open"] and c["items"].get("scout_drone") == n0,
                   f"accessory={c['accessory']!r} open={c['accessory_menu_open']} drone {n0} -> {c['items'].get('scout_drone')}")
            tb = c["touch_buttons"]
        if "use_scout_drone" in tb:
            cx, cy = tb["use_scout_drone"][0], tb["use_scout_drone"][1]
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
            record("drone button after picking it from the list", False, f"touch_buttons={sorted(tb)}")
    else:
        record("drone tapped (precondition: drone carried with count > 0, current or reachable from the tab)", False,
               f"items={items} accessory={s['accessory']!r} accessory_menu in touch_buttons={'accessory_menu' in tb}")

    # --- tapping outside the open list closes it (only with 2+ accessories: the default loadout has none to pick)
    s2 = st(p, 0.3)
    if "accessory_menu" not in s2["touch_buttons"]:
        record("tab and list: not exercised (the default loadout carries a single accessory; unit tests cover them)", True,
               f"accessory={s2['accessory']!r}")
    else:
        t = s2["touch_buttons"]["accessory_menu"]
        tap_vp(p, t[0], t[1])
        o = st(p, 0.8)
        p.tap(*LOOK_A, hold=0.15, fid=1)
        c2 = st(p, 0.8)
        record("tap on the tab opens the list, a tap elsewhere closes it", bool(o["accessory_menu_open"]) and not c2["accessory_menu_open"],
               f"open={o['accessory_menu_open']} after outside tap={c2['accessory_menu_open']}")

    # --- weapon card: tapping the card of the other weapon takes it (and back)
    s3 = st(p, 0.3)
    cards3 = sorted(a for a in s3["touch_buttons"] if a.startswith("weapon_card_"))
    if len(cards3) == 2:
        slot0 = s3["weapon_slot"]
        other = cards3[1] if slot0 == 0 else cards3[0]
        tap_vp(p, s3["touch_buttons"][other][0], s3["touch_buttons"][other][1])
        w1 = st(p, 0.9)
        record("tap on the card of the other weapon takes that weapon", w1["weapon_slot"] != slot0,
               f"weapon_slot {slot0} -> {w1['weapon_slot']} (tapped {other})")
        back = sorted(a for a in w1["touch_buttons"] if a.startswith("weapon_card_"))
        back_card = back[0] if w1["weapon_slot"] != 0 else back[1]
        tap_vp(p, w1["touch_buttons"][back_card][0], w1["touch_buttons"][back_card][1])
        w2 = st(p, 0.9)
        record("and back again", w2["weapon_slot"] == slot0, f"weapon_slot {w1['weapon_slot']} -> {w2['weapon_slot']}")
    else:
        record("weapon card swap: not exercised (the default loadout carries one weapon; unit tests cover the taps)", True,
               f"cards={cards3}")

    # --- both Tiro buttons fire (the second one is new)
    for label, pos in (("right", FIRE), ("left", FIRE_LEFT)):
        a = st(p, 0.2)
        p.tap(*pos, hold=0.15, fid=1)
        b = st(p, 0.6)
        record(f"{label} Tiro button fires", b["ammo_mag"] < a["ammo_mag"], f"ammo {a['ammo_mag']} -> {b['ammo_mag']}")


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
