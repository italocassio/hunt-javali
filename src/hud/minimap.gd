class_name Minimap
extends Control
## Player-centred, north-up minimap (docs §8.4). Draws the map image (when the world has one), the crops, the dog,
## baits, marked boars and (only while the drone reveals them) every alive boar. Shapes and colours come from MapMarkers.

const VIEW_RADIUS_M: float = 90.0
const COLOR_BG: Color = Color(0.40, 0.36, 0.22, 0.85)
const COLOR_FRAME: Color = Color(0.96, 0.94, 0.90, 0.8)
const COLOR_OUTSIDE: Color = Color(0.05, 0.05, 0.05, 0.85)
const COLOR_CROP: Color = Color(0.25, 0.55, 0.28, 0.75)
const COLOR_PLAYER: Color = Color("#F4EFE6")
const COLOR_OBJECTIVE: Color = Color("#F2C12E")
const MAP_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.92)
const CROP_OUTLINE_PX: float = 2.0
const MARKER_MARGIN_PX: float = 0.5   # beyond the half width and the outline, so a clamped marker stays inside the frame
const OBJECTIVE_ICON_PX: float = 24.0
const OBJECTIVE_SQUARE_PX: float = 12.0
const ALLY_ARROW_TIP_PX: float = 8.0
const ALLY_ARROW_BACK_PX: float = 5.0
const ALLY_FALLEN_HALF_PX: float = 5.0
const ALLY_FALLEN_WIDTH_PX: float = 3.0
const ALLY_FALLEN_ALPHA: float = 0.7
const ALLY_EDGE_MARGIN_PX: float = 9.0
const ALLY_EDGE_ARROW_PX: float = 8.0
const ALLY_EDGE_OUTLINE_PX: float = 2.0
## Half width (radius) of each kind on the minimap (docs §8.4, table "Marcadores").
const HALF_PX: Dictionary = {
	&"crop": 5.0, &"bait": 5.0, &"revealed": 3.5, &"boar": 6.0, &"dog_target": 8.0, &"dog": 4.5,
}

var map_rect: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0):
	set(value):
		map_rect = value
		_update_region()
		queue_redraw()
## Image of the whole map (north up, covering map_rect); null = the plain background of before.
var map_texture: Texture2D = null:
	set(value):
		map_texture = value
		_update_region()
		queue_redraw()
var crop_rects: Array[Rect2] = []
var dog_position: Vector3 = Vector3.INF
## What the dog is after (docs §8.4): a ring in the dog colour; Vector3.INF = nothing (the dog follows).
var dog_target: Vector3 = Vector3.INF
var marked: PackedVector3Array = PackedVector3Array()
var revealed: PackedVector3Array = PackedVector3Array()
var baits: PackedVector3Array = PackedVector3Array()
## Horde objective (the barn): Vector3.INF = none. Drawn with the icon, or a filled square without it.
var objective: Vector3 = Vector3.INF
var objective_icon: Texture2D = null
## Allies (docs/multiplayer.md 6.7): four parallel arrays, one entry per hunter other than the one in the centre.
var allies: PackedVector3Array = PackedVector3Array()
var ally_colors: PackedColorArray = PackedColorArray()
var ally_yaws: PackedFloat32Array = PackedFloat32Array()   # world yaw in radians, same convention as update_player
var ally_down: PackedByteArray = PackedByteArray()          # 1 = fallen
## Colour of the centre arrow: the hunter's own colour in a networked hunt, the neutral one otherwise.
var center_color: Color = COLOR_PLAYER

var _origin: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _src_rect: Rect2 = Rect2()   # slice of map_texture, in texels
var _dst_rect: Rect2 = Rect2()   # where that slice is drawn, in control px


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180.0, 180.0)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(_update_region)


func update_player(origin: Vector3, yaw_rad: float) -> void:
	_origin = origin
	_yaw = yaw_rad
	_update_region()
	queue_redraw()


## Slice of map_texture (texels) that is on screen; Rect2() without texture or when the view is off the map.
func get_map_src_rect() -> Rect2:
	return _src_rect


## Where get_map_src_rect() is drawn, in control px; Rect2() without texture or when the view is off the map.
func get_map_dst_rect() -> Rect2:
	return _dst_rect


func _update_region() -> void:
	_src_rect = Rect2()
	_dst_rect = Rect2()
	var side: float = minf(size.x, size.y)
	if map_texture == null or side <= 0.0:
		return
	var scale_px: float = side * 0.5 / VIEW_RADIUS_M
	var view: Rect2 = Rect2(Vector2(_origin.x, _origin.z) - size * 0.5 / scale_px, size / scale_px)
	var vis: Rect2 = view.intersection(map_rect)
	if not vis.has_area():
		return
	var k: float = float(map_texture.get_width()) / map_rect.size.x
	_dst_rect = Rect2(_to_map(vis.position.x, vis.position.y), vis.size * scale_px)
	_src_rect = Rect2((vis.position - map_rect.position) * k, vis.size * k)


func _to_map(world_x: float, world_z: float) -> Vector2:
	var scale_px: float = minf(size.x, size.y) * 0.5 / VIEW_RADIUS_M
	return size * 0.5 + Vector2(world_x - _origin.x, world_z - _origin.z) * scale_px


func _draw() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(bounds, COLOR_OUTSIDE)
	if map_texture != null:
		if _dst_rect.has_area():
			draw_texture_rect_region(map_texture, _dst_rect, _src_rect, MAP_MODULATE)
	else:
		var top_left: Vector2 = _to_map(map_rect.position.x, map_rect.position.y)
		var bottom_right: Vector2 = _to_map(map_rect.end.x, map_rect.end.y)
		var ground: Rect2 = Rect2(top_left, bottom_right - top_left).intersection(bounds)
		if ground.has_area():
			draw_rect(ground, COLOR_BG)
	for rect: Rect2 in crop_rects:
		var a: Vector2 = _to_map(rect.position.x, rect.position.y)
		var b: Vector2 = _to_map(rect.end.x, rect.end.y)
		if map_texture != null:
			draw_rect(Rect2(a, b - a), MapMarkers.COLOR_CROP, false, CROP_OUTLINE_PX)   # clip_contents trims the overflow
		else:
			var clipped: Rect2 = Rect2(a, b - a).intersection(bounds)
			if clipped.has_area():
				draw_rect(clipped, COLOR_CROP)
	if objective.is_finite():
		_draw_objective()
	for kind: StringName in MapMarkers.DRAW_ORDER:
		match kind:
			MapMarkers.KIND_CROP:
				_draw_off_view_crops()
			MapMarkers.KIND_BAIT:
				for p: Vector3 in baits:
					_marker(p, kind)
			MapMarkers.KIND_REVEALED:
				for p: Vector3 in revealed:
					_marker(p, kind)
			MapMarkers.KIND_BOAR:
				for p: Vector3 in marked:
					_marker(p, kind)
			MapMarkers.KIND_DOG_TARGET:
				if dog_target.is_finite():
					_marker(dog_target, kind)
			MapMarkers.KIND_DOG:
				if dog_position.is_finite():
					_marker(dog_position, kind)
			MapMarkers.KIND_ALLY:
				for i: int in allies.size():
					_draw_ally(i)
	_draw_player()
	draw_rect(bounds, COLOR_FRAME, false, 2.0)


## With the map image, a plot entirely out of view becomes a square stuck to the frame (in view it has its outline).
func _draw_off_view_crops() -> void:
	if map_texture == null:
		return
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	for rect: Rect2 in crop_rects:
		var a: Vector2 = _to_map(rect.position.x, rect.position.y)
		var b: Vector2 = _to_map(rect.end.x, rect.end.y)
		if not Rect2(a, b - a).intersects(bounds):
			var center: Vector2 = rect.get_center()
			_marker(Vector3(center.x, 0.0, center.y), MapMarkers.KIND_CROP)


## The barn sticks to the frame when out of view, like the other markers.
func _draw_objective() -> void:
	var p: Vector2 = _to_map(objective.x, objective.z)
	var half: float = (OBJECTIVE_ICON_PX if objective_icon != null else OBJECTIVE_SQUARE_PX) * 0.5
	p = Vector2(clampf(p.x, half + 2.0, size.x - half - 2.0), clampf(p.y, half + 2.0, size.y - half - 2.0))
	if objective_icon != null:
		draw_texture_rect(objective_icon, Rect2(p - Vector2.ONE * half, Vector2.ONE * half * 2.0), false)
	else:
		draw_rect(Rect2(p - Vector2.ONE * (half + 1.5), Vector2.ONE * (half + 1.5) * 2.0), Color.BLACK)
		draw_rect(Rect2(p - Vector2.ONE * half, Vector2.ONE * half * 2.0), COLOR_OBJECTIVE)


## One marker of MapMarkers. Out-of-view markers stick to the frame so the hunter still knows the direction.
func _marker(world: Vector3, kind: StringName) -> void:
	var half: float = float(HALF_PX.get(kind, 4.5))
	var margin: float = half + MapMarkers.OUTLINE_PX + MARKER_MARGIN_PX
	var p: Vector2 = _to_map(world.x, world.z)
	p = Vector2(clampf(p.x, margin, size.x - margin), clampf(p.y, margin, size.y - margin))
	MapMarkers.draw(self, kind, p, MapMarkers.color_of(kind), half)


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
