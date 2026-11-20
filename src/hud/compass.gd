class_name Compass
extends Control
## Horizontal compass strip (docs §8.4): a tick every 5 degrees, a label every 15 (N/NE/L/SE/S/SO/O/NO on the
## multiples of 45, numbers in between), the heading in degrees in a box at the centre and the markers of MapMarkers.
## North is -Z, bearings grow clockwise.

const BAND_H_PX: float = 34.0
const VISIBLE_SPAN_DEG: float = 180.0
const MINOR_TICK_STEP_DEG: float = 5.0
const TICK_STEP_DEG: float = 15.0
const INTERCARDINAL_STEP_DEG: int = 45
const MINOR_TICK_PX: float = 4.0
const TICK_PX: float = 7.0
const MAJOR_TICK_PX: float = 10.0
const TICK_WIDTH_PX: float = 2.0
const LABEL_CENTER_Y_PX: float = 13.0
const CARDINAL_FONT_PX: int = 20
const CARDINAL_OUTLINE_PX: int = 4
const INTERCARDINAL_FONT_PX: int = 16
const INTERCARDINAL_OUTLINE_PX: int = 3
const NUMBER_FONT_PX: int = 13
const NUMBER_ALPHA: float = 0.85
const MARKER_OFFSET_PX: float = 9.0           # marker centre above the base of the band
const EDGE_ALPHA: float = 0.6
const READOUT_W_PX: float = 56.0
const READOUT_H_PX: float = 18.0
const READOUT_FONT_PX: int = 15
const NOTCH_BASE_PX: float = 10.0
const NOTCH_H_PX: float = 6.0
const COLOR_BG: Color = Color(0.12, 0.10, 0.09, 0.55)
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_NORTH: Color = Color("#D9452B")
const COLOR_TICK: Color = Color(0.96, 0.94, 0.90, 0.55)
const COLOR_OBJECTIVE: Color = Color("#F2C12E")
const OBJECTIVE_PX: float = 20.0
const ALLY_HALF_PX: float = 6.0
const ALLY_FALLEN_WIDTH_PX: float = 3.0
const ALLY_FALLEN_ALPHA: float = 0.85
## Half width (radius) of each kind on the strip (docs §8.4, table "Marcadores").
const HALF_PX: Dictionary = {
	&"crop": 6.0, &"bait": 6.0, &"revealed": 4.5, &"boar": 7.0, &"dog_target": 10.0, &"dog": 4.5,
}
const CARDINAL_LABELS: Array[String] = ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]

## Horde objective (the barn): Vector3.INF = none. Always on the strip, at the edge when behind the hunter.
var objective: Vector3 = Vector3.INF
var objective_icon: Texture2D = null

var _yaw: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _marks: Array[Dictionary] = []   # {pos: Vector3, kind: StringName}; kind &"ally" also has color: Color, down: bool


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(480.0, BAND_H_PX + READOUT_H_PX + 2.0)


## Clockwise bearing from north, in radians, of a world-space direction (x, z).
static func bearing_of(dx: float, dz: float) -> float:
	return atan2(dx, -dz)


## Whole-degree heading (0..359) of a player yaw; the number in the readout box.
static func heading_deg_of(yaw_rad: float) -> int:
	return posmod(roundi(rad_to_deg(-yaw_rad)), 360)


## Text of a strip label: N/NE/L/SE/S/SO/O/NO on the multiples of 45, the number on the other multiples of 15,
## "" for the rest.
static func label_for(deg: int) -> String:
	var d: int = posmod(deg, 360)
	if d % INTERCARDINAL_STEP_DEG == 0:
		@warning_ignore("integer_division")
		return CARDINAL_LABELS[d / INTERCARDINAL_STEP_DEG]
	if d % int(TICK_STEP_DEG) == 0:
		return str(d)
	return ""


func get_heading_deg() -> int:
	return heading_deg_of(_yaw)


func get_heading_text() -> String:
	return "%d°" % get_heading_deg()


func update_state(origin: Vector3, yaw_rad: float, marks: Array[Dictionary]) -> void:
	_origin = origin
	_yaw = yaw_rad
	_marks = marks
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	draw_rect(Rect2(0.0, 0.0, w, BAND_H_PX), COLOR_BG)
	var heading_deg: float = rad_to_deg(-_yaw)
	var half_span: float = VISIBLE_SPAN_DEG * 0.5
	var font: Font = get_theme_default_font()
	var first: int = int(floor((heading_deg - half_span) / MINOR_TICK_STEP_DEG))
	var last: int = int(ceil((heading_deg + half_span) / MINOR_TICK_STEP_DEG))
	for i: int in range(first, last + 1):
		var deg: int = i * int(MINOR_TICK_STEP_DEG)
		var x: float = w * 0.5 + (float(deg) - heading_deg) / VISIBLE_SPAN_DEG * w
		if x < 0.0 or x > w:
			continue
		var wrapped: int = posmod(deg, 360)
		var tick_h: float = MINOR_TICK_PX
		if wrapped % INTERCARDINAL_STEP_DEG == 0:
			tick_h = MAJOR_TICK_PX
		elif wrapped % int(TICK_STEP_DEG) == 0:
			tick_h = TICK_PX
		draw_line(Vector2(x, BAND_H_PX - tick_h), Vector2(x, BAND_H_PX), COLOR_TICK, TICK_WIDTH_PX)
		var label: String = label_for(wrapped)
		if label != "":
			_draw_label(font, label, wrapped, x)
	if objective.is_finite():
		_draw_objective(heading_deg, w)
	for mark: Dictionary in _marks:
		_draw_marker(mark, heading_deg, w)
	_draw_readout(font, w)


func _draw_label(font: Font, label: String, wrapped: int, x: float) -> void:
	var cardinal: bool = wrapped % 90 == 0
	var intercardinal: bool = not cardinal and wrapped % INTERCARDINAL_STEP_DEG == 0
	var font_px: int = CARDINAL_FONT_PX if cardinal else (INTERCARDINAL_FONT_PX if intercardinal else NUMBER_FONT_PX)
	var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	if x - text_w * 0.5 < 0.0 or x + text_w * 0.5 > size.x:
		return   # a label that does not fit whole inside the strip is skipped (its tick stays)
	var baseline: float = LABEL_CENTER_Y_PX + (font.get_ascent(font_px) - font.get_descent(font_px)) * 0.5
	var at: Vector2 = Vector2(x - text_w * 0.5, baseline)
	if cardinal or intercardinal:
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px,
			CARDINAL_OUTLINE_PX if cardinal else INTERCARDINAL_OUTLINE_PX, Color.BLACK)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, COLOR_NORTH if wrapped == 0 else COLOR_TEXT)
	else:
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px,
			Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, NUMBER_ALPHA))


## Heading box under the centre of the strip, with a notch rising to the band.
func _draw_readout(font: Font, w: float) -> void:
	var cx: float = w * 0.5
	var top: float = BAND_H_PX + 2.0
	draw_rect(Rect2(cx - READOUT_W_PX * 0.5, top, READOUT_W_PX, READOUT_H_PX), COLOR_BG)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - NOTCH_BASE_PX * 0.5, top), Vector2(cx + NOTCH_BASE_PX * 0.5, top),
		Vector2(cx, top - NOTCH_H_PX)]), COLOR_TEXT)
	var text: String = get_heading_text()
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_PX).x
	var baseline: float = top + READOUT_H_PX * 0.5 + (font.get_ascent(READOUT_FONT_PX) - font.get_descent(READOUT_FONT_PX)) * 0.5
	draw_string(font, Vector2(cx - text_w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_PX, COLOR_TEXT)


func _draw_objective(heading_deg: float, w: float) -> void:
	var bearing_deg: float = rad_to_deg(bearing_of(objective.x - _origin.x, objective.z - _origin.z))
	var rel: float = clampf(wrapf(bearing_deg - heading_deg, -180.0, 180.0), -VISIBLE_SPAN_DEG * 0.5, VISIBLE_SPAN_DEG * 0.5)
	var half: float = OBJECTIVE_PX * 0.5
	var x: float = clampf(w * 0.5 + rel / VISIBLE_SPAN_DEG * w, half, w - half)
	var y: float = BAND_H_PX - half - 2.0
	if objective_icon != null:
		draw_texture_rect(objective_icon, Rect2(Vector2(x - half, y - half), Vector2.ONE * OBJECTIVE_PX), false)
	else:
		draw_rect(Rect2(Vector2(x - half - 1.5, y - half - 1.5), Vector2.ONE * (OBJECTIVE_PX + 3.0)), Color.BLACK)
		draw_rect(Rect2(Vector2(x - half, y - half), Vector2.ONE * OBJECTIVE_PX), COLOR_OBJECTIVE)


func _draw_marker(mark: Dictionary, heading_deg: float, w: float) -> void:
	var p: Vector3 = mark["pos"]
	var bearing_deg: float = rad_to_deg(bearing_of(p.x - _origin.x, p.z - _origin.z))
	var rel: float = wrapf(bearing_deg - heading_deg, -180.0, 180.0)
	var at_edge: bool = absf(rel) > VISIBLE_SPAN_DEG * 0.5
	rel = clampf(rel, -VISIBLE_SPAN_DEG * 0.5, VISIBLE_SPAN_DEG * 0.5)
	var at: Vector2 = Vector2(w * 0.5 + rel / VISIBLE_SPAN_DEG * w, BAND_H_PX - MARKER_OFFSET_PX)
	var kind: StringName = mark["kind"]
	var color: Color = mark.get("color", COLOR_TEXT) if kind == MapMarkers.KIND_ALLY else MapMarkers.color_of(kind)
	if at_edge:
		color.a = EDGE_ALPHA
	if kind == MapMarkers.KIND_ALLY:
		_draw_ally_marker(at, color, bool(mark.get("down", false)))
	else:
		MapMarkers.draw(self, kind, at, color, float(HALF_PX.get(kind, 6.0)))


## Ally in the slot colour: a diamond (boars are triangles, the dog a dot, the dog's target a ring). A fallen one is hollow and dimmed.
func _draw_ally_marker(at: Vector2, color: Color, down: bool) -> void:
	var outer: PackedVector2Array = PackedVector2Array([at + Vector2(0.0, -ALLY_HALF_PX - 2.0),
		at + Vector2(ALLY_HALF_PX + 2.0, 0.0), at + Vector2(0.0, ALLY_HALF_PX + 2.0), at + Vector2(-ALLY_HALF_PX - 2.0, 0.0)])
	var inner: PackedVector2Array = PackedVector2Array([at + Vector2(0.0, -ALLY_HALF_PX),
		at + Vector2(ALLY_HALF_PX, 0.0), at + Vector2(0.0, ALLY_HALF_PX), at + Vector2(-ALLY_HALF_PX, 0.0)])
	if down:
		var dim: Color = Color(color.r, color.g, color.b, color.a * ALLY_FALLEN_ALPHA)
		draw_polyline(inner + PackedVector2Array([inner[0]]), Color.BLACK, ALLY_FALLEN_WIDTH_PX + 2.0)
		draw_polyline(inner + PackedVector2Array([inner[0]]), dim, ALLY_FALLEN_WIDTH_PX)
		return
	draw_colored_polygon(outer, Color.BLACK)
	draw_colored_polygon(inner, color)
