class_name LoadingBoar
extends Control
## Hunt loading widget: a galloping boar silhouette on a progress trail plus a percentage.
## Pure 2D (_draw only): no 3D, no shader, no texture, so it adds no GPU 3D work.

const GALLOP_PERIOD: float = 0.45
const FILL_SMOOTH_SPEED: float = 6.0
const SIDE_MARGIN_FRACTION: float = 0.05
const BOAR_TRACK_FRACTION: float = 1.0 / 5.0
const BOAR_MAX_HEIGHT_FRACTION: float = 0.55
const BOAR_HEIGHT_UNITS: float = 82.0
const BOAR_NOSE_X: float = 77.0
const BOAR_TAIL_X: float = -92.0
const GROUND_Y_FRACTION: float = 0.62
const TICK_SPACING: float = 26.0
const TICK_SPEED: float = 160.0
const DUST_COUNT: int = 5
const BODY_BOB: float = 3.0
const BODY_LIFT: float = 7.0
const BODY_PITCH: float = 0.05
const STRIDE: float = 15.0
const FOOT_LIFT: float = 11.0
const UPPER_LEN: float = 20.0
const LOWER_LEN: float = 20.0

const COL_BODY: Color = Color(0.4, 0.28, 0.19)
const COL_FAR: Color = Color(0.27, 0.185, 0.125)
const COL_HOOF: Color = Color(0.1, 0.07, 0.05)
const COL_MANE: Color = Color(0.23, 0.155, 0.105)
const COL_RIM: Color = Color(0.93, 0.52, 0.2)
const COL_TUSK: Color = Color(0.96, 0.88, 0.7)
const COL_SNOUT: Color = Color(0.5, 0.36, 0.26)
const COL_TRACK: Color = Color(0.3, 0.24, 0.19)
const COL_FILL: Color = Color(0.93, 0.52, 0.2)
const COL_TICK: Color = Color(0.4, 0.31, 0.22)
const COL_DUST: Color = Color(0.72, 0.52, 0.32)
const COL_TEXT: Color = Color(0.957, 0.937, 0.902)

const BODY: PackedVector2Array = [
	Vector2(-48, -38), Vector2(-40, -48), Vector2(-10, -52), Vector2(18, -62), Vector2(28, -58),
	Vector2(40, -49), Vector2(52, -43), Vector2(66, -32), Vector2(72, -27), Vector2(70, -18),
	Vector2(56, -18), Vector2(42, -20), Vector2(30, -20), Vector2(10, -19), Vector2(-20, -21),
	Vector2(-40, -26),
]
const BACK_LINE: PackedVector2Array = [
	Vector2(-48, -38), Vector2(-40, -48), Vector2(-10, -52), Vector2(18, -62), Vector2(28, -58),
	Vector2(40, -49), Vector2(52, -43), Vector2(66, -32),
]
## Dense dark mane tuft: short irregular bristles swept back, tallest at the withers, fading into the back.
const MANE_TOP: PackedVector2Array = [
	Vector2(-12, -52), Vector2(-14, -55.5), Vector2(-9, -54.5), Vector2(-9, -58.5), Vector2(-4, -56.5),
	Vector2(-4, -61), Vector2(1, -58.5), Vector2(1, -64.5), Vector2(6, -60.5), Vector2(6, -67.5),
	Vector2(11, -62.5), Vector2(11, -69.5), Vector2(16, -65), Vector2(15, -71), Vector2(21, -66),
	Vector2(22, -69), Vector2(26, -63), Vector2(27, -66), Vector2(31, -59), Vector2(32, -60),
	Vector2(36, -54),
]
const EAR: PackedVector2Array = [Vector2(37, -50), Vector2(43, -61), Vector2(48, -47)]
const TUSK: PackedVector2Array = [Vector2(58, -18), Vector2(63, -19), Vector2(65, -29), Vector2(61, -24)]
const FRONT_HIP: Vector2 = Vector2(24, -34)
const HIND_HIP: Vector2 = Vector2(-34, -34)

var _mane_quads: Array[PackedVector2Array] = []
var _target: float = 0.0
var _shown: float = 0.0
var _time: float = 0.0
## When >= 0 the animation clock is frozen to this value (used by preview screenshots).
var debug_time: float = -1.0


func _init() -> void:
	custom_minimum_size = Vector2(320, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_mane()


## Sets the loading progress in 0..1. The displayed value never goes backwards.
func set_progress(value: float) -> void:
	_target = maxf(_target, clampf(value, 0.0, 1.0))


func _process(delta: float) -> void:
	_time += delta
	_shown = move_toward(_shown, _target, delta * (0.15 + (_target - _shown) * FILL_SMOOTH_SPEED))
	queue_redraw()


func _clock() -> float:
	return debug_time if debug_time >= 0.0 else _time


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var avail: float = w * (1.0 - 2.0 * SIDE_MARGIN_FRACTION)
	var boar_w: float = minf(avail * BOAR_TRACK_FRACTION, h * BOAR_MAX_HEIGHT_FRACTION * 100.0 / BOAR_HEIGHT_UNITS)
	var s: float = boar_w / 100.0
	# The trail runs from the left margin to where the nose sits at 100%, so the whole boar stays inside.
	var x0: float = w * SIDE_MARGIN_FRACTION
	var x1: float = w - w * SIDE_MARGIN_FRACTION - 3.0
	var track_w: float = maxf(x1 - x0, 1.0)
	var ground_y: float = h * GROUND_Y_FRACTION
	var line_w: float = maxf(4.0, boar_w * 0.06)
	var progress: float = _shown
	var tip_x: float = x0 + track_w * progress
	draw_line(Vector2(x0, ground_y), Vector2(x1, ground_y), COL_TRACK, line_w, true)
	if progress > 0.0:
		draw_line(Vector2(x0, ground_y), Vector2(tip_x, ground_y), COL_FILL, line_w, true)
	# Ground ticks scrolling left under the trail (ground passing by).
	var scroll: float = fposmod(_clock() * TICK_SPEED * (s + 0.3), TICK_SPACING)
	var tick_len: float = line_w * 1.2
	var tx: float = x0 + TICK_SPACING - scroll
	while tx < x1:
		if tx > x0:
			draw_line(Vector2(tx, ground_y + line_w * 1.1), Vector2(tx - tick_len, ground_y + line_w * 1.1 + tick_len * 0.6), COL_TICK, 2.0, true)
		tx += TICK_SPACING
	# Nose on the fill tip; clamped so tail and dust never leave the widget on the left.
	var cx: float = clampf(tip_x - BOAR_NOSE_X * s, x0 - BOAR_TAIL_X * s, x1 - BOAR_NOSE_X * s)
	_draw_boar(Vector2(cx, ground_y - line_w * 0.4), s)
	var font: Font = get_theme_default_font()
	var fsize: int = int(clampf(minf(w * 0.075, h * 0.2), 16.0, 44.0))
	var text: String = "%d%%" % int(floor(progress * 100.0 + 0.0001))
	var tsize: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var ty: float = ground_y + line_w * 1.1 + tick_len + float(fsize) * 0.35 + font.get_ascent(fsize)
	draw_string_outline(font, Vector2((w - tsize.x) * 0.5, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2((w - tsize.x) * 0.5, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COL_TEXT)


func _draw_boar(center: Vector2, s: float) -> void:
	var phase: float = fposmod(_clock() / GALLOP_PERIOD, 1.0) * TAU
	var bob: float = -absf(sin(phase)) * BODY_BOB
	var pitch: float = sin(phase + 0.8) * BODY_PITCH
	var origin: Vector2 = center + Vector2(0, bob * s)
	draw_set_transform(origin, pitch, Vector2(s, s))
	for i: int in DUST_COUNT:
		var t: float = fposmod(_clock() / GALLOP_PERIOD * 1.3 + float(i) / float(DUST_COUNT), 1.0)
		var p: Vector2 = Vector2(-52.0 - t * 38.0, -3.0 - t * 14.0 - sin(float(i) * 2.3) * 3.0)
		draw_circle(p, 2.5 + t * 6.0, Color(COL_DUST, (1.0 - t) * 0.5))
	_draw_leg(FRONT_HIP, phase + 0.45, COL_FAR, -1.0)
	_draw_leg(HIND_HIP, phase + PI + 0.45, COL_FAR, 1.0)
	# Body is lifted above the legs so they read long.
	draw_set_transform(origin + Vector2(0, -BODY_LIFT * s).rotated(pitch), pitch, Vector2(s, s))
	draw_polyline(PackedVector2Array([Vector2(-47, -38), Vector2(-55, -44), Vector2(-58, -52)]), COL_BODY, 3.0, true)
	draw_circle(Vector2(-58, -53), 2.6, COL_MANE)
	draw_colored_polygon(BODY, COL_BODY)
	draw_polyline(BACK_LINE, COL_RIM, 1.6, true)
	for q: PackedVector2Array in _mane_quads:
		draw_colored_polygon(q, COL_MANE)
	draw_polyline(MANE_TOP, COL_RIM, 1.0, true)
	draw_colored_polygon(EAR, COL_BODY)
	draw_polyline(EAR, COL_RIM, 1.0, true)
	draw_circle(Vector2(70, -23), 5.5, COL_SNOUT)
	draw_circle(Vector2(72, -25), 1.2, COL_FAR)
	draw_colored_polygon(TUSK, COL_TUSK)
	draw_circle(Vector2(52, -35), 1.8, COL_RIM)
	draw_set_transform(origin, pitch, Vector2(s, s))
	_draw_leg(FRONT_HIP, phase, COL_BODY, -1.0)
	_draw_leg(HIND_HIP, phase + PI, COL_BODY, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Two-bone leg with the foot driven on a stride path, so the leg never shortens mid-cycle.
## knee_dir: -1 bends the knee forward (front legs), +1 backward (hind hock).
func _draw_leg(hip: Vector2, ph: float, col: Color, knee_dir: float) -> void:
	var fwd: float = cos(ph)
	var foot: Vector2 = Vector2(hip.x + STRIDE * sin(ph), -FOOT_LIFT * maxf(0.0, fwd) * maxf(0.0, fwd))
	var to_foot: Vector2 = foot - hip
	var d: float = clampf(to_foot.length(), 1.0, UPPER_LEN + LOWER_LEN - 0.5)
	var dir: Vector2 = to_foot.normalized()
	var a: float = (UPPER_LEN * UPPER_LEN - LOWER_LEN * LOWER_LEN + d * d) / (2.0 * d)
	var hh: float = sqrt(maxf(UPPER_LEN * UPPER_LEN - a * a, 0.0))
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var knee: Vector2 = hip + dir * a + perp * hh * knee_dir
	draw_circle(hip, 8.5, col)
	_taper(hip, knee, 10.0, 5.0, col)
	draw_circle(knee, 4.6, col)
	_taper(knee, foot, 4.8, 3.2, col)
	var hoof_top: Vector2 = foot + (knee - foot).normalized() * 5.0
	_taper(hoof_top, foot + Vector2(0, 0.8), 3.0, 3.6, COL_HOOF)


func _taper(a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n: Vector2 = (b - a).orthogonal().normalized()
	draw_colored_polygon(PackedVector2Array([a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5]), col)


## Splits the tuft into simple quads (tip edge dropped onto the back line), robust to triangulation.
func _build_mane() -> void:
	for i: int in MANE_TOP.size() - 1:
		var a: Vector2 = MANE_TOP[i]
		var b: Vector2 = MANE_TOP[i + 1]
		_mane_quads.append(PackedVector2Array([a, b, Vector2(b.x, _back_y(b.x) + 1.0), Vector2(a.x, _back_y(a.x) + 1.0)]))


func _back_y(x: float) -> float:
	for i: int in BACK_LINE.size() - 1:
		var p: Vector2 = BACK_LINE[i]
		var q: Vector2 = BACK_LINE[i + 1]
		if x >= p.x and x <= q.x:
			return lerpf(p.y, q.y, (x - p.x) / maxf(q.x - p.x, 0.001))
	return BACK_LINE[0].y
