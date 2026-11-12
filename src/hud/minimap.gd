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

var map_rect: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)
var crop_rects: Array[Rect2] = []
var dog_position: Vector3 = Vector3.INF
var marked: PackedVector3Array = PackedVector3Array()
var revealed: PackedVector3Array = PackedVector3Array()
var baits: PackedVector3Array = PackedVector3Array()

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
	_draw_player()
	draw_rect(bounds, COLOR_FRAME, false, 2.0)


func _dot(world: Vector3, color: Color, radius: float) -> void:
	var p: Vector2 = _to_map(world.x, world.z)
	var margin: float = radius + 2.0
	# Out-of-view markers stick to the frame so the hunter still knows the direction.
	p = Vector2(clampf(p.x, margin, size.x - margin), clampf(p.y, margin, size.y - margin))
	draw_circle(p, radius + 1.5, Color.BLACK)
	draw_circle(p, radius, color)


func _draw_player() -> void:
	var c: Vector2 = size * 0.5
	var fwd: Vector2 = Vector2(-sin(_yaw), -cos(_yaw))
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = c + fwd * 10.0
	var left: Vector2 = c - fwd * 6.0 + side * 6.0
	var right: Vector2 = c - fwd * 6.0 - side * 6.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), COLOR_PLAYER)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), Color.BLACK, 1.5)
