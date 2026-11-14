class_name Minimap
extends Control
## Player-centred, north-up minimap (docs §8.4). Shows the map edge, crops, dog, baits, marked
## boars and (only while the drone reveals them) every alive boar.

const VIEW_RADIUS_M: float = 90.0
const COLOR_BG: Color = Color(0.40, 0.36, 0.22, 0.85)
const COLOR_FRAME: Color = Color(0.96, 0.94, 0.90, 0.8)
const COLOR_OUTSIDE: Color = Color(0.05, 0.05, 0.05, 0.85)
const COLOR_CROP: Color = Color(0.25, 0.55, 0.28, 0.75)
const COLOR_PLAYER: Color = Color("#F4EFE6")
const COLOR_DOG: Color = Color("#F2C12E")
const COLOR_BOAR: Color = Color("#D9452B")
const COLOR_BAIT: Color = Color("#E8B923")
const ALLY_ARROW_TIP_PX: float = 8.0
const ALLY_ARROW_BACK_PX: float = 5.0
const ALLY_FALLEN_HALF_PX: float = 5.0
const ALLY_FALLEN_WIDTH_PX: float = 3.0
const ALLY_FALLEN_ALPHA: float = 0.7
const ALLY_EDGE_MARGIN_PX: float = 9.0
const ALLY_EDGE_ARROW_PX: float = 8.0
const ALLY_EDGE_OUTLINE_PX: float = 2.0

var map_rect: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)
var crop_rects: Array[Rect2] = []
var dog_position: Vector3 = Vector3.INF
var marked: PackedVector3Array = PackedVector3Array()
var revealed: PackedVector3Array = PackedVector3Array()
var baits: PackedVector3Array = PackedVector3Array()
## Allies (docs/multiplayer.md 6.7): four parallel arrays, one entry per hunter other than the one in the centre.
var allies: PackedVector3Array = PackedVector3Array()
var ally_colors: PackedColorArray = PackedColorArray()
var ally_yaws: PackedFloat32Array = PackedFloat32Array()   # world yaw in radians, same convention as update_player
var ally_down: PackedByteArray = PackedByteArray()          # 1 = fallen
## Colour of the centre arrow: the hunter's own colour in a networked hunt, the neutral one otherwise.
var center_color: Color = COLOR_PLAYER

var _origin: Vector3 = Vector3.ZERO
var _yaw: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180.0, 180.0)
	clip_contents = true


func update_player(origin: Vector3, yaw_rad: float) -> void:
	_origin = origin
	_yaw = yaw_rad
	queue_redraw()


func _to_map(world_x: float, world_z: float) -> Vector2:
	var scale_px: float = minf(size.x, size.y) * 0.5 / VIEW_RADIUS_M
	return size * 0.5 + Vector2(world_x - _origin.x, world_z - _origin.z) * scale_px


func _draw() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(bounds, COLOR_OUTSIDE)
	var top_left: Vector2 = _to_map(map_rect.position.x, map_rect.position.y)
	var bottom_right: Vector2 = _to_map(map_rect.end.x, map_rect.end.y)
	var ground: Rect2 = Rect2(top_left, bottom_right - top_left).intersection(bounds)
	if ground.has_area():
		draw_rect(ground, COLOR_BG)
	for rect: Rect2 in crop_rects:
		var a: Vector2 = _to_map(rect.position.x, rect.position.y)
		var b: Vector2 = _to_map(rect.end.x, rect.end.y)
		var clipped: Rect2 = Rect2(a, b - a).intersection(bounds)
		if clipped.has_area():
			draw_rect(clipped, COLOR_CROP)
	for p: Vector3 in baits:
		_dot(p, COLOR_BAIT, 4.0)
	for p: Vector3 in marked:
		_dot(p, COLOR_BOAR, 4.5)
	for p: Vector3 in revealed:
		_dot(p, COLOR_BOAR, 4.5)
	if dog_position.is_finite():
		_dot(dog_position, COLOR_DOG, 4.5)
	for i: int in allies.size():
		_draw_ally(i)
	_draw_player()
	draw_rect(bounds, COLOR_FRAME, false, 2.0)


func _dot(world: Vector3, color: Color, radius: float) -> void:
	var p: Vector2 = _to_map(world.x, world.z)
	var margin: float = radius + 2.0
	# Out-of-view markers stick to the frame so the hunter still knows the direction.
	p = Vector2(clampf(p.x, margin, size.x - margin), clampf(p.y, margin, size.y - margin))
	draw_circle(p, radius + 1.5, Color.BLACK)
	draw_circle(p, radius, color)


## True when the world point falls inside the frame (outside it an ally is drawn as an edge arrow).
func is_in_view(world: Vector3) -> bool:
	var p: Vector2 = _to_map(world.x, world.z)
	return p.x >= ALLY_EDGE_MARGIN_PX and p.y >= ALLY_EDGE_MARGIN_PX \
		and p.x <= size.x - ALLY_EDGE_MARGIN_PX and p.y <= size.y - ALLY_EDGE_MARGIN_PX


func _draw_ally(index: int) -> void:
	var world: Vector3 = allies[index]
	var color: Color = ally_colors[index] if index < ally_colors.size() else COLOR_PLAYER
	var down: bool = index < ally_down.size() and ally_down[index] != 0
	var yaw: float = ally_yaws[index] if index < ally_yaws.size() else 0.0
	var p: Vector2 = _to_map(world.x, world.z)
	if not is_in_view(world):
		_draw_edge_arrow(p, color, down)
	elif down:
		_draw_fallen(p, color)
	else:
		_draw_arrow(p, yaw, color, ALLY_ARROW_TIP_PX, ALLY_ARROW_BACK_PX)


## Arrow pointing along a world yaw (the same shape as the player's, smaller).
func _draw_arrow(center: Vector2, yaw: float, color: Color, tip_px: float, back_px: float) -> void:
	var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = center + fwd * tip_px
	var left: Vector2 = center - fwd * back_px + side * back_px
	var right: Vector2 = center - fwd * back_px - side * back_px
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.BLACK, 1.5)


## Fallen hunter: a cross (a fallen hunter has no heading) in the slot colour, dimmed, over a dark outline.
func _draw_fallen(center: Vector2, color: Color) -> void:
	var r: float = ALLY_FALLEN_HALF_PX
	var a: Vector2 = Vector2(r, r)
	var b: Vector2 = Vector2(r, -r)
	var dim: Color = Color(color.r, color.g, color.b, ALLY_FALLEN_ALPHA)
	draw_line(center - a, center + a, Color.BLACK, ALLY_FALLEN_WIDTH_PX + 2.5)
	draw_line(center - b, center + b, Color.BLACK, ALLY_FALLEN_WIDTH_PX + 2.5)
	draw_line(center - a, center + a, dim, ALLY_FALLEN_WIDTH_PX)
	draw_line(center - b, center + b, dim, ALLY_FALLEN_WIDTH_PX)


## Out-of-view ally: a triangle on the frame, on the line from the centre towards the ally, pointing outwards.
## A fallen one is drawn hollow so the two states stay apart at the edge too.
func _draw_edge_arrow(far_point: Vector2, color: Color, down: bool) -> void:
	var c: Vector2 = size * 0.5
	var dir: Vector2 = far_point - c
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var reach: Vector2 = c - Vector2.ONE * ALLY_EDGE_MARGIN_PX
	var t: float = minf(reach.x / maxf(absf(dir.x), 0.0001), reach.y / maxf(absf(dir.y), 0.0001))
	var at: Vector2 = c + dir * t
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = at + dir * ALLY_EDGE_ARROW_PX
	var left: Vector2 = at - dir * ALLY_EDGE_ARROW_PX * 0.5 + side * ALLY_EDGE_ARROW_PX * 0.8
	var right: Vector2 = at - dir * ALLY_EDGE_ARROW_PX * 0.5 - side * ALLY_EDGE_ARROW_PX * 0.8
	var tri: PackedVector2Array = PackedVector2Array([tip, left, right])
	if down:
		draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.BLACK, ALLY_EDGE_OUTLINE_PX + 2.0)
		draw_polyline(PackedVector2Array([tip, left, right, tip]), Color(color.r, color.g, color.b, ALLY_FALLEN_ALPHA),
			ALLY_EDGE_OUTLINE_PX)
	else:
		draw_colored_polygon(tri, color)
		draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.BLACK, 1.5)


func _draw_player() -> void:
	var c: Vector2 = size * 0.5
	var fwd: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = c + fwd * 10.0
	var left: Vector2 = c - fwd * 6.0 + side * 6.0
	var right: Vector2 = c - fwd * 6.0 - side * 6.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), center_color)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.BLACK, 1.5)
