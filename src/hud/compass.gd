class_name Compass
extends Control
## Horizontal compass strip (docs §8.4): N/L/S/O, a tick every 15 degrees and markers for the dog
## and for marked boars. North is -Z, bearings grow clockwise.

const VISIBLE_SPAN_DEG: float = 180.0
const TICK_STEP_DEG: float = 15.0
const COLOR_BG: Color = Color(0.12, 0.10, 0.09, 0.55)
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_NORTH: Color = Color("#D9452B")
const COLOR_TICK: Color = Color(0.96, 0.94, 0.90, 0.55)
const COLOR_DOG: Color = Color("#F2C12E")
const COLOR_BOAR: Color = Color("#D9452B")
const FONT_SIZE: int = 20
const CARDINALS: Dictionary = {0: "N", 90: "L", 180: "S", 270: "O"}

var _yaw: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _marks: Array[Dictionary] = []   # {pos: Vector3, kind: StringName}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(480.0, 44.0)


## Clockwise bearing from north, in radians, of a world-space direction (x, z).
static func bearing_of(dx: float, dz: float) -> float:
	return atan2(dx, -dz)


func update_state(origin: Vector3, yaw_rad: float, marks: Array[Dictionary]) -> void:
	_origin = origin
	_yaw = yaw_rad
	_marks = marks
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	var heading_deg: float = rad_to_deg(-_yaw)
	var half_span: float = VISIBLE_SPAN_DEG * 0.5
	var font: Font = get_theme_default_font()
	var first: int = int(floor((heading_deg - half_span) / TICK_STEP_DEG))
	var last: int = int(ceil((heading_deg + half_span) / TICK_STEP_DEG))
	for i: int in range(first, last + 1):
		var deg: float = float(i) * TICK_STEP_DEG
		var x: float = w * 0.5 + (deg - heading_deg) / VISIBLE_SPAN_DEG * w
		if x < 0.0 or x > w:
			continue
		var wrapped: int = int(posmod(roundi(deg), 360))
		if CARDINALS.has(wrapped):
			var label: String = CARDINALS[wrapped]
			var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var color: Color = COLOR_NORTH if wrapped == 0 else COLOR_TEXT
			draw_string_outline(font, Vector2(x - text_w * 0.5, h * 0.5 + FONT_SIZE * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color.BLACK)
			draw_string(font, Vector2(x - text_w * 0.5, h * 0.5 + FONT_SIZE * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		else:
			var tick_h: float = h * 0.28 if wrapped % 45 == 0 else h * 0.16
			draw_line(Vector2(x, h - tick_h), Vector2(x, h), COLOR_TICK, 2.0)
	for mark: Dictionary in _marks:
		_draw_marker(mark, heading_deg, w, h)
	# Centre pointer.
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 6.0, 0.0), Vector2(w * 0.5 + 6.0, 0.0),
		Vector2(w * 0.5, 9.0)]), COLOR_TEXT)


func _draw_marker(mark: Dictionary, heading_deg: float, w: float, h: float) -> void:
	var p: Vector3 = mark["pos"]
	var bearing_deg: float = rad_to_deg(bearing_of(p.x - _origin.x, p.z - _origin.z))
	var rel: float = wrapf(bearing_deg - heading_deg, -180.0, 180.0)
	var at_edge: bool = absf(rel) > VISIBLE_SPAN_DEG * 0.5
	rel = clampf(rel, -VISIBLE_SPAN_DEG * 0.5, VISIBLE_SPAN_DEG * 0.5)
	var x: float = w * 0.5 + rel / VISIBLE_SPAN_DEG * w
	var color: Color = COLOR_DOG if mark["kind"] == &"dog" else COLOR_BOAR
	if at_edge:
		color.a = 0.6
	var cy: float = h - 10.0
	if mark["kind"] == &"dog":
		draw_circle(Vector2(x, cy), 6.0, Color.BLACK)
		draw_circle(Vector2(x, cy), 4.5, color)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(x - 8.0, cy + 7.0), Vector2(x + 8.0, cy + 7.0),
			Vector2(x, cy - 8.0)]), Color.BLACK)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 6.0, cy + 5.0), Vector2(x + 6.0, cy + 5.0),
			Vector2(x, cy - 5.5)]), color)
