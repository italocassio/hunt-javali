class_name HudCrosshair
extends Control
## Dynamic crosshair (four ticks that open with the weapon spread) plus the hitmarker X.
## Pure view: the Hud feeds it numbers every frame.

const GAP_MIN_PX: float = 6.0
const TICK_LEN_PX: float = 10.0
const TICK_WIDTH_PX: float = 3.0
const OUTLINE_PX: float = 2.0
const COLOR_MAIN: Color = Color("#F4EFE6")
const COLOR_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.7)
const COLOR_HIT: Color = Color("#F4EFE6")
const COLOR_KILL: Color = Color("#D9452B")
const HIT_TIME_S: float = 0.18
const KILL_TIME_S: float = 0.35
const HIT_SIZE_PX: float = 16.0
const HIT_INNER_PX: float = 7.0

## Ticks gap from the centre in pixels (already converted from the spread angle).
var gap_px: float = GAP_MIN_PX
## 0 hides the crosshair (scope overlay brings its own reticle), 1 fully visible.
var visibility_t: float = 1.0

var _hit_left: float = 0.0
var _hit_total: float = HIT_TIME_S
var _hit_kill: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func flash_hit(kill: bool) -> void:
	_hit_kill = kill
	_hit_total = KILL_TIME_S if kill else HIT_TIME_S
	_hit_left = _hit_total
	queue_redraw()


func set_gap(px: float) -> void:
	var clamped: float = maxf(px, GAP_MIN_PX)
	if absf(clamped - gap_px) > 0.4:
		gap_px = clamped
		queue_redraw()


func set_visibility_t(t: float) -> void:
	if absf(t - visibility_t) > 0.01:
		visibility_t = t
		queue_redraw()


func _process(delta: float) -> void:
	if _hit_left > 0.0:
		_hit_left = maxf(_hit_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	if visibility_t > 0.01:
		var main: Color = Color(COLOR_MAIN, visibility_t)
		var outline: Color = Color(COLOR_OUTLINE, COLOR_OUTLINE.a * visibility_t)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = c + dir * gap_px
			var b: Vector2 = c + dir * (gap_px + TICK_LEN_PX)
			draw_line(a, b, outline, TICK_WIDTH_PX + OUTLINE_PX * 2.0)
			draw_line(a, b, main, TICK_WIDTH_PX)
		draw_circle(c, 2.0, main)
	if _hit_left > 0.0:
		var t: float = _hit_left / _hit_total
		var color: Color = COLOR_KILL if _hit_kill else COLOR_HIT
		color.a = clampf(t * 2.0, 0.0, 1.0)
		var grow: float = (1.0 - t) * 5.0
		var outer: float = HIT_SIZE_PX + grow + (6.0 if _hit_kill else 0.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var a: Vector2 = c + dir * HIT_INNER_PX
			var b: Vector2 = c + dir * outer
			draw_line(a, b, Color(0.0, 0.0, 0.0, color.a * 0.7), 6.0)
			draw_line(a, b, color, 3.0)
