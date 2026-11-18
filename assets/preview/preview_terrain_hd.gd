extends Node3D
## Preview for the terrain and water shaders: the preview map seen from fixed cameras.
## Screenshot: tools/godot.sh --path . --windowed --resolution 960x540 -s res://tools/screenshot.gd -- \
##   --scene=res://assets/preview/preview_terrain_hd.tscn --out=C:/abs/shot.png -- --cam=eye|road|water|over

func _ready() -> void:
	var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
	map.set("with_boars", false)
	add_child(map)
	for c in map.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh and (c as MeshInstance3D).material_override != null:
			# the game builds the pond as a CylinderMesh disc; match it so the shader UV is the same
			var disc: CylinderMesh = CylinderMesh.new()
			disc.top_radius = 8.0
			disc.bottom_radius = 8.0
			disc.height = 0.02
			disc.radial_segments = 40
			disc.rings = 1
			(c as MeshInstance3D).mesh = disc
			(c as MeshInstance3D).position.y += 0.6 # no dug basin in the preview terrain: lift the pond so it shows
	var mode: String = "eye"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			mode = a.trim_prefix("--cam=")
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	match mode:
		"eye":
			cam.position = Vector3(-18.0, map.call("_h", -18.0, 22.0) + 1.7, 22.0)
			cam.look_at(Vector3(-22.0, 0.6, 0.0))
		"road":
			cam.position = Vector3(-24.0, map.call("_h", -24.0, 19.5) + 1.5, 19.5)
			cam.look_at(Vector3(-24.0, map.call("_h", -24.0, 16.0), 16.0))
		"water":
			cam.position = Vector3(32.0, map.call("_h", 32.0, 35.0) + 1.7, 35.0)
			cam.look_at(Vector3(32.0, map.call("_h", 32.0, 20.0), 20.0))
		_:
			cam.position = Vector3(10.0, 40.0, 50.0)
			cam.look_at(Vector3(0.0, 0.0, -10.0))
			cam.fov = 60.0
	cam.make_current()
