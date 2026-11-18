extends Node3D
## Preview: the real Mato Grosso map (dug pond, game water mesh, game terrain, game environment).
## Screenshot: tools/godot.sh --path . --windowed --resolution 960x540 -s res://tools/screenshot.gd -- \
##   --scene=res://assets/preview/preview_pond_real.tscn --out=C:/abs/shot.png --frames=40 -- --cam=eye|sun

const POND: Vector2 = Vector2(-70.0, -55.0)
const POND_RADIUS: float = 18.0
const SHORE_DISTANCE: float = 15.0


func _ready() -> void:
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var map: Node = (load("res://src/world/maps/mato_grosso/mato_grosso_map.tscn") as PackedScene).instantiate()
	add_child(map)
	map.call(&"build_heightmap")
	map.call(&"build_terrain")
	map.call(&"build_props_and_water")
	var mode: String = "eye"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			mode = a.trim_prefix("--cam=")
	var dir: Vector2 = _clearest_direction(map)
	if mode == "sun":
		dir = Vector2(0.47, 0.88).normalized() # camera on the sun-opposite side, looking toward the low sun
	var cam_xz: Vector2 = POND + dir * (POND_RADIUS + SHORE_DISTANCE)
	if mode == "sun":
		cam_xz = POND - dir * (POND_RADIUS + SHORE_DISTANCE)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	cam.position = Vector3(cam_xz.x, _h(map, cam_xz.x, cam_xz.y) + 1.7, cam_xz.y)
	var look: Vector2 = POND
	var look_y: float = cam.position.y - 0.5
	if mode == "sun":
		look_y = cam.position.y + 2.0
	cam.look_at(Vector3(look.x, look_y, look.y))
	cam.make_current()


## Direction (from the pond centre) whose line of sight to the pond is least blocked by terrain.
func _clearest_direction(map: Node) -> Vector2:
	var best: Vector2 = Vector2(0.0, 1.0)
	var best_block: float = INF
	for k in 24:
		var d: Vector2 = Vector2.from_angle(TAU * float(k) / 24.0)
		var cam_xz: Vector2 = POND + d * (POND_RADIUS + SHORE_DISTANCE)
		var eye: float = _h(map, cam_xz.x, cam_xz.y) + 1.7
		var block: float = -INF
		for i in range(1, 16):
			var q: Vector2 = cam_xz.lerp(POND, float(i) / 16.0)
			block = maxf(block, _h(map, q.x, q.y) - eye)
		if block < best_block:
			best_block = block
			best = d
	return best


func _h(map: Node, x: float, z: float) -> float:
	return (map.get(&"heightmap") as RefCounted).call(&"get_height", x, z)
