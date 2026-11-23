extends Node3D
## Preview: the scout_drone prop, three views, rotors spinning; prints the budget and Sfx ids, then quits.

func _ready() -> void:
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var d: Node3D = (load("res://assets/models/props/scout_drone.tscn") as PackedScene).instantiate()
	add_child(d)
	d.position = Vector3(0, 0, 0)
	d.rotation = Vector3(deg_to_rad(18.0), deg_to_rad(-35.0), 0)
	await get_tree().process_frame
	var mis: int = 0
	var mmis: int = 0
	for c: Node in d.get_children():
		if c is MeshInstance3D:
			mis += 1
		if c is MultiMeshInstance3D:
			mmis += 1
	var body: MeshInstance3D = d.get_node("Body")
	var rot: MultiMeshInstance3D = d.get_node("Rotors")
	var body_tris: int = MeshKit.count_triangles(d)
	var rot_tris: int = (rot.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("DRONE aabb=%s body_tris=%d rotor_tris=%d x4 total=%d MeshInstance3D=%d MultiMeshInstance3D=%d" % [body.get_aabb().size, body_tris, rot_tris, body_tris + rot_tris * 4, mis, mmis])
	for id: StringName in [&"bandage_wrap", &"drink_gulp", &"bait_throw"]:
		var s: AudioStreamWAV = Sfx.call(&"_get_stream", id) as AudioStreamWAV
		print("SFX %s has=%s len=%.2fs" % [id, Sfx.has_sound(id), (float(s.data.size()) / 2.0 / float(s.mix_rate)) if s != null else -1.0])
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 0.1, 0.42)
	cam.look_at(Vector3(0, 0.0, 0))
	var shot: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	for i: int in 12:
		await get_tree().process_frame
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
