extends Node3D
## Preview of the HD boar prototype (assets/models/boar/boar_visual.gd). Prints budgets, build times and the hit-zone
## check, then renders the requested shots to PNG and quits (stats only with --headless).
##   tools/godot.sh --path . --fixed-fps 60 --resolution 960x540 res://assets/preview/preview_boar_hd.tscn -- \
##       --out=C:/abs/dir [--shots=types_studio,poses_move,poses_combat,poses_extra,map_scale,lod,lod_scope,custom]
##       [--type=boar] [--pose=idle|walk|trot|gallop|scrape|attack|dead|eat|alert|wounded|hit|highlight]
##       [--dist=4] [--scene=studio|map] [--yaw=120] [--frames=40]

const BoarHD := preload("res://assets/models/boar/boar_visual.gd")
const Model := preload("res://assets/models/boar/boar_hd_model.gd")
const HUNTER_SCENE: String = "res://assets/models/hunter/hunter_visual.tscn"
const MAP_SCENE: String = "res://assets/preview/preview_map.tscn"
const DEFAULT_SHOTS: String = "types_studio,poses_move,poses_combat,map_scale,lod"
const TYPES: Array[StringName] = [&"piglet", &"sow", &"boar", &"alpha", &"boss"]
const TYPE_KG: Dictionary = {&"piglet": 30.0, &"sow": 80.0, &"boar": 100.0, &"alpha": 220.0, &"boss": 600.0}
const HARD_TIMEOUT_S: float = 150.0
const GAME_FOV: float = 75.0
const LEG_ZONE_MIN_Y: float = 0.26

var _out_dir: String = "user://boar_hd"
var _frames: int = 40
var _type: StringName = &"boar"
var _pose: String = "idle"
var _dist: float = 4.0
var _scene: String = "studio"
var _yaw: float = 125.0
var _world: Node3D
var _map: Node3D
var _debug: String = ""


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
		elif a.begins_with("--type="):
			_type = StringName(a.trim_prefix("--type="))
		elif a.begins_with("--pose="):
			_pose = a.trim_prefix("--pose=")
		elif a.begins_with("--dist="):
			_dist = float(a.trim_prefix("--dist="))
		elif a.begins_with("--scene="):
			_scene = a.trim_prefix("--scene=")
		elif a.begins_with("--debug="):
			_debug = a.trim_prefix("--debug=")
		elif a.begins_with("--yaw="):
			_yaw = float(a.trim_prefix("--yaw="))
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	if DisplayServer.get_name() == "headless":
		_print_stats()
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _on_timeout() -> void:
	printerr("preview_boar_hd: timed out")
	get_tree().quit(1)


# --- stats -------------------------------------------------------------------------------------------------

func _print_stats() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var t0: int = Time.get_ticks_usec()
	Model.noise_texture()
	lines.append("shared noise texture (already warm in the hunt: 1st-person gun): %.1f ms" % _ms(t0))
	# cold / cached setup per type
	for t: StringName in TYPES:
		var b: BoarVisualBase = BoarHD.new()
		var ts: int = Time.get_ticks_usec()
		b.setup(t, TYPE_KG[t])
		var cold: float = _ms(ts)
		var b2: BoarVisualBase = BoarHD.new()
		ts = Time.get_ticks_usec()
		b2.setup(t, TYPE_KG[t])
		var cached: float = _ms(ts)
		ts = Time.get_ticks_usec()
		var b3: BoarVisualBase = BoarHD.new()
		b3.setup(t, TYPE_KG[t])
		var inst: float = _ms(ts)
		lines.append("setup(%s, %.0f kg): cold %.2f ms, cached %.3f ms, new instance + setup (cached) %.3f ms" % [t, TYPE_KG[t], cold, cached, inst])
		b.free()
		b2.free()
		b3.free()
	# budget per type and LOD
	lines.append("type    | LOD  | tris | visible MeshInstance3D | materials")
	var mats_all: Dictionary = {}
	for t: StringName in TYPES:
		var bucket: int = Model.tusk_bucket(t, TYPE_KG[t])
		var near: int = 0
		var mid: int = 0
		for part: String in ["body", "head", "tail"]:
			near += Model.triangles(t, Model.LOD_NEAR, part, bucket)
			mid += Model.triangles(t, Model.LOD_MID, part, bucket)
		near += 2 * (Model.triangles(t, Model.LOD_NEAR, "leg_f", 0) + Model.triangles(t, Model.LOD_NEAR, "leg_h", 0))
		mid += 2 * (Model.triangles(t, Model.LOD_MID, "leg_f", 0) + Model.triangles(t, Model.LOD_MID, "leg_h", 0))
		var far: int = Model.triangles(t, Model.LOD_FAR, "far", bucket)
		var b: BoarVisualBase = BoarHD.new()
		b.setup(t, TYPE_KG[t])
		var vis: Array[int] = [0, 0, 0]
		var mats: Dictionary = {}
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			var lod: int = 2 if mi.name == "Far" else (0 if mi.name.ends_with("Near") else 1)
			vis[lod] += 1
			for s in mi.mesh.get_surface_count():
				mats[mi.mesh.surface_get_material(s).get_instance_id()] = true
				mats_all[mi.mesh.surface_get_material(s).get_instance_id()] = true
		lines.append("%-7s | near | %4d | %d | %d" % [t, near, vis[0], mats.size()])
		lines.append("%-7s | mid  | %4d | %d | %d" % [t, mid, vis[1], mats.size()])
		lines.append("%-7s | far  | %4d | %d | %d" % [t, far, vis[2], mats.size()])
		var shadow: Array[String] = []
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow.append(str(mi.name))
		if t == &"boar":
			lines.append("shadow casters: %s" % ", ".join(shadow))
		b.free()
	lines.append("distinct materials over the 4 types: %d (+1 shared highlight)" % mats_all.size())
	var near_t: int = 0
	var mid_t: int = 0
	for part: String in ["body", "head", "tail", "leg_f", "leg_f", "leg_h", "leg_h"]:
		near_t += Model.triangles(&"alpha", Model.LOD_NEAR, part, 0)
		mid_t += Model.triangles(&"alpha", Model.LOD_MID, part, 0)
	var far_t: int = Model.triangles(&"alpha", Model.LOD_FAR, "far", 0)
	lines.append("26 boars all within 25 m: %d tris; 4 near + 10 mid + 12 far: %d tris" % [26 * near_t, 4 * near_t + 10 * mid_t + 12 * far_t])
	for l in lines:
		print("preview_boar_hd: " + l)
	_hit_zone_check()
	_zoom_lod_check()


## The LOD ranges follow the camera zoom: a boar at 62 m seen through a 6x scope keeps the near meshes.
func _zoom_lod_check() -> void:
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var b: Node3D = BoarHD.new()
	add_child(b)
	b.position = Vector3(0.0, 0.0, -62.0)
	for fov: float in [GAME_FOV, GAME_FOV / 6.0]:
		cam.fov = fov
		b.call(&"_process", 0.016)
		var near: MeshInstance3D = b.get_node("Rig/BodyNear")
		var far: MeshInstance3D = b.get_node("Rig/Far")
		print("preview_boar_hd: camera fov %.1f: near LOD up to %.0f m, far LOD from %.0f m -> boar at 62 m drawn %s" % [fov,
			near.visibility_range_end, far.visibility_range_begin, "NEAR" if 62.0 < near.visibility_range_end else ("FAR" if 62.0 > far.visibility_range_begin else "MID")])
	b.free()
	cam.free()


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


## Rest-pose vertices of trunk, head and upper legs (no mane, ears, tusks, tail) against BoarVisualBase.HIT_ZONES, macho 100 kg.
func _hit_zone_check() -> void:
	var b: Node3D = BoarHD.new()
	b.setup(Ids.BOAR, 100.0)
	var pts: PackedVector3Array = PackedVector3Array()
	var extras: PackedVector3Array = PackedVector3Array()
	var all_pts: PackedVector3Array = PackedVector3Array()
	for node_path: String in ["Rig/BodyNear", "Head/Near", "LegFL/Near", "LegFR/Near", "LegRL/Near", "LegRR/Near", "Rig/Tail/Near"]:
		var mi: MeshInstance3D = b.get_node(node_path)
		var xf: Transform3D = Transform3D(Basis.IDENTITY, Model.HEAD_REST) if node_path.begins_with("Head") else Transform3D.IDENTITY
		if node_path.begins_with("Leg"):
			xf = Transform3D(Basis.IDENTITY, Model.LEG_HIPS[["LegFL", "LegFR", "LegRL", "LegRR"].find(node_path.get_slice("/", 0))])
		elif node_path.contains("Tail"):
			xf = Transform3D(Basis.IDENTITY, Model.TAIL_ROOT)
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in v.size():
			var p: Vector3 = xf * v[i]
			all_pts.push_back(p)
			var code: float = c2[i].x
			var core: bool = (node_path == "Rig/BodyNear" and absf(code - 0.25) < 0.01) or (node_path == "Head/Near" and (absf(code - 0.1) < 0.01 or absf(code - 2.2) < 0.01 or absf(code - 5.0) < 0.01))
			# the upper legs (shoulder, ham) belong to the zones too; the lower legs are outside every zone
			if node_path.begins_with("Leg") and p.y >= LEG_ZONE_MIN_Y:
				core = true
			if core:
				pts.push_back(p)
			elif not node_path.begins_with("Leg"):
				extras.push_back(p)
	print("preview_boar_hd: hit zones (macho 100 kg, rest pose; trunk + head surface vs box, tolerance 5 cm)")
	print("preview_boar_hd: zone   | axis | mesh min..max     | box min..max      | overflow | gap  | ok")
	var all_ok: bool = true
	for zone: StringName in BoarVisualBase.HIT_ZONES:
		var spec: Array = BoarVisualBase.HIT_ZONES[zone]
		var c: Vector3 = spec[0]
		var s: Vector3 = spec[1]
		var lo: Vector3 = c - s * 0.5
		var hi: Vector3 = c + s * 0.5
		var mn: Vector3 = Vector3.INF
		var mx: Vector3 = -Vector3.INF
		for p in pts:
			if p.z < lo.z or p.z > hi.z:
				continue
			mn = mn.min(p)
			mx = mx.max(p)
		# length: the trunk + head must cover the union of the zones
		for ax: int in [0, 1]:
			var over: float = maxf(maxf(lo[ax] - mn[ax], mx[ax] - hi[ax]), 0.0)
			var gap: float = maxf(maxf(mn[ax] - lo[ax], hi[ax] - mx[ax]), 0.0)
			var ok: bool = over <= 0.05 and gap <= 0.05
			all_ok = all_ok and ok
			print("preview_boar_hd: %-6s | %s    | %+.3f..%+.3f | %+.3f..%+.3f | %.3f    | %.3f | %s" % [zone, "xy"[ax], mn[ax], mx[ax], lo[ax], hi[ax], over, gap, "ok" if ok else "FORA"])
	var tmn: Vector3 = Vector3.INF
	var tmx: Vector3 = -Vector3.INF
	for p in pts:
		tmn = tmn.min(p)
		tmx = tmx.max(p)
	var amn: Vector3 = Vector3.INF
	var amx: Vector3 = -Vector3.INF
	for p in all_pts:
		amn = amn.min(p)
		amx = amx.max(p)
	var withers: float = 0.0
	for p in extras:
		if p.z > -0.45 and p.z < -0.05:
			withers = maxf(withers, p.y)
	print("preview_boar_hd: trunk+head z %.3f..%.3f (zones %.2f..%.2f), half width %.3f, top %.3f, bottom %.3f" % [tmn.z, tmx.z, -0.82, 0.67, maxf(-tmn.x, tmx.x), tmx.y, tmn.y])
	print("preview_boar_hd: whole model: snout z %.3f, tail z %.3f, length %.3f, width %.3f, top %.3f (withers with mane %.3f), floor %.3f" % [amn.z, amx.z, amx.z - amn.z, amx.x - amn.x, amx.y, withers, amn.y])
	print("preview_boar_hd: hit zones %s" % ("OK" if all_ok else "FORA DA TOLERANCIA"))
	b.free()


# --- shots -------------------------------------------------------------------------------------------------

func _run(shots: PackedStringArray) -> void:
	for shot in shots:
		_clear()
		var cam: Camera3D
		var boars: Array = []      # [boar, pose]
		match shot:
			"types_studio":
				cam = _studio()
				var xs: Array[float] = [-3.6, -2.35, -1.2, 0.2, 2.6]
				for i in TYPES.size():
					var t: StringName = TYPES[i]
					boars.append([_boar(t, TYPE_KG[t], Vector3(xs[i], 0.0, 0.0), 122.0), "idle"])
				_look(cam, Vector3(-0.3, 0.7, 0.0), Vector3(-0.3, 1.6, 8.6), 36.0)
			"poses_move":
				cam = _studio()
				var poses: Array[String] = ["walk", "gallop", "scrape"]
				for i in 3:
					boars.append([_boar(&"boar", 100.0, Vector3((float(i) - 1.0) * 1.75, 0.0, 0.0), 105.0), poses[i]])
				_look(cam, Vector3(0.0, 0.42, 0.0), Vector3(0.0, 1.35, 5.4), 36.0)
			"poses_combat":
				cam = _studio()
				boars.append([_boar(&"boar", 100.0, Vector3(-0.9, 0.0, 0.0), 120.0), "attack"])
				boars.append([_boar(&"boar", 100.0, Vector3(0.95, 0.0, 0.2), 70.0), "dead"])
				_look(cam, Vector3(0.1, 0.35, 0.0), Vector3(0.0, 1.4, 4.1), 36.0)
			"poses_extra":
				cam = _studio()
				var extra: Array[String] = ["eat", "alert", "wounded", "highlight"]
				for i in 4:
					boars.append([_boar(&"boar", 100.0, Vector3((float(i) - 1.5) * 1.4, 0.0, 0.0), 115.0), extra[i]])
				_look(cam, Vector3(0.0, 0.42, 0.0), Vector3(0.0, 1.5, 6.2), 36.0)
			"map_scale":
				cam = _map_scene()
				var base: Vector3 = _ground(Vector3(-10.0, 0.0, 20.0))
				var hunter: Node3D = (load(HUNTER_SCENE) as PackedScene).instantiate()
				hunter.call(&"setup", 0, &"rifle_308")
				_world.add_child(hunter)
				hunter.position = base
				hunter.rotation.y = deg_to_rad(200.0)
				boars.append([_boar(&"boar", 100.0, _ground(base + Vector3(1.25, 0.0, 0.1)), 100.0), "idle"])
				boars.append([_boar(&"sow", 80.0, _ground(base + Vector3(-1.35, 0.0, 0.3)), 75.0), "eat"])
				_look(cam, base + Vector3(0.0, 0.8, 0.0), base + Vector3(-0.6, 1.55, 5.6), 40.0)
			"lod", "lod_scope":
				# game sun, sky and haze over a flat cerrado-coloured ground (the map slice has hills, trees and crops in the way)
				cam = _game_light_flat()
				var eye: Vector3 = Vector3(0.0, 1.7, 0.0)
				var dists: Array[float] = [10.0, 30.0, 62.0]
				var lat: Array[float] = [-1.6, 2.4, -1.2]
				for i in 3:
					boars.append([_boar(&"boar", 100.0, Vector3(lat[i], 0.0, -dists[i]), 90.0 if i != 1 else 270.0), "idle"])
				var target: Vector3 = (boars[2][0] as Node3D).position + Vector3(0, 0.45, 0) if shot == "lod_scope" else Vector3(0.0, 0.9, -20.0)
				_look(cam, target, eye, GAME_FOV if shot == "lod" else GAME_FOV / 6.0)
			"eyes_close", "eyes_close_back", "eyes_close_mid":
				# the four types with their heads in a row, ~2 m from the camera, game sun and sky (back: against the sun;
				# mid: the 25-60 m meshes forced, to inspect the painted eye)
				cam = _game_light_flat()
				var back: bool = shot == "eyes_close_back"
				var yaw_c: float = -45.0 if back else 135.0
				for i in 4:
					var t: StringName = TYPES[i]
					var s: float = BoarVisualBase.scale_for_weight(TYPE_KG[t])
					var head: Vector3 = Vector3((float(i) - 1.5) * (-0.62 if back else 0.62), 0.0, 0.0)
					var off: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw_c)) * (Model.HEAD_REST * s)
					boars.append([_boar(t, TYPE_KG[t], Vector3(head.x - off.x, 0.0, head.z - off.z), yaw_c),
						"lod_mid" if shot == "eyes_close_mid" else "idle"])
				_look(cam, Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.85, -2.0 if back else 2.0), 40.0)
			"eyes_10", "eyes_20", "eyes_40", "eyes_20_scope":
				# the four types in profile at game distance, game FOV (scope: 4x), seen from standing eye height
				cam = _game_light_flat()
				var d: float = float(shot.get_slice("_", 1))
				for i in 4:
					var t2: StringName = TYPES[i]
					boars.append([_boar(t2, TYPE_KG[t2], Vector3((float(i) - 1.5) * 1.7, 0.0, -d), 90.0), "idle"])
				_look(cam, Vector3(0.0, 0.45, -d), Vector3(0.0, 1.7, 0.0), GAME_FOV / 4.0 if shot.ends_with("scope") else GAME_FOV)
			"custom":
				cam = _studio() if _scene == "studio" else _map_scene()
				var at: Vector3 = Vector3.ZERO if _scene == "studio" else _ground(Vector3(-10.0, 0.0, 20.0))
				boars.append([_boar(_type, TYPE_KG.get(_type, 100.0), at, _yaw), _pose])
				_look(cam, at + Vector3(0.0, 0.42, 0.0), at + Vector3(0.0, 1.0, _dist), 36.0)
			_:
				printerr("preview_boar_hd: unknown shot '%s'" % shot)
				continue
		for e: Array in boars:
			_start_pose(e[0], e[1])
		for f in _frames:
			for e: Array in boars:
				if e[1] == "attack" and f == _frames - 15:
					(e[0] as BoarVisualBase).play_attack()
				if e[1] == "hit" and f == _frames - 3:
					(e[0] as BoarVisualBase).play_hit(Ids.ZONE_BODY)
				_keep_pose(e[0], e[1])
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_boar_hd: %s %s" % ["saved" if err == OK else "FAILED", path])
		if shot in ["eyes_10", "eyes_20", "eyes_40"]:
			_save_crop(image, cam, boars, _out_dir.path_join("%s_crop.png" % shot))
	get_tree().quit(0)


## Pixel-exact enlargement (nearest) of the screen box around the boars: what the player really gets at that distance.
func _save_crop(image: Image, cam: Camera3D, boars: Array, path: String) -> void:
	# unproject works in the stretched viewport size (1280x720 base), the image is the window size
	var k_px: Vector2 = Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var r: Rect2 = Rect2()
	for i in boars.size():
		var b: Node3D = boars[i][0]
		for off: Vector3 in [Vector3(0, 0, 0), Vector3(0, 1.0, 0), Vector3(-0.9, 0.5, 0), Vector3(0.9, 0.5, 0)]:
			var sp: Vector2 = cam.unproject_position(b.global_position + off) * k_px
			r = Rect2(sp, Vector2.ZERO) if i == 0 and off == Vector3.ZERO else r.expand(sp)
	var sz: Vector2i = image.get_size()
	var w: int = clampi(int(r.size.x * 1.15), 16, sz.x)
	var h: int = clampi(int(w * 9.0 / 16.0), 9, sz.y)
	@warning_ignore("integer_division")
	var cx: int = clampi(int(r.get_center().x) - w / 2, 0, sz.x - w)
	@warning_ignore("integer_division")
	var cy: int = clampi(int(r.get_center().y) - h / 2, 0, sz.y - h)
	var crop: Image = image.get_region(Rect2i(cx, cy, w, h))
	@warning_ignore("integer_division")
	var k: int = maxi(sz.x / w, 1)
	crop.resize(w * k, h * k, Image.INTERPOLATE_NEAREST)
	var err: Error = crop.save_png(path)
	print("preview_boar_hd: %s %s (%dx%d px enlarged %dx)" % ["saved" if err == OK else "FAILED", path, w, h, k])


func _start_pose(b: BoarVisualBase, pose: String) -> void:
	match pose:
		"walk": b.set_locomotion(1.3)
		"trot": b.set_locomotion(3.2)
		"gallop": b.set_locomotion(9.0)
		"scrape": b.play_scrape()
		"dead": b.play_death()
		"eat": b.set_eating(true)
		"alert": pass
		"wounded":
			b.set_wounded(true)
			b.set_locomotion(1.2)
		"highlight": b.set_highlight(true)


func _keep_pose(b: BoarVisualBase, pose: String) -> void:
	match pose:
		"walk": b.set_locomotion(1.3)
		"trot": b.set_locomotion(3.2)
		"gallop": b.set_locomotion(9.0)
		"wounded": b.set_locomotion(1.2)
		"lod_mid":
			# after the boar's own range update: mid meshes at every distance, near and far hidden
			for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
				mi.visible = mi.name.ends_with("Mid")
				mi.visibility_range_begin = 0.0
				mi.visibility_range_end = 0.0
		"alert":
			if b.get(&"_alert_t") == 0.0 or float(b.get(&"_alert_t")) < 0.45:
				b.play_alert()


func _boar(type_id: StringName, kg: float, pos: Vector3, yaw_deg: float) -> BoarVisualBase:
	var b: BoarVisualBase = BoarHD.new()
	b.setup(type_id, kg)
	_world.add_child(b)
	b.scale = Vector3.ONE * BoarVisualBase.scale_for_weight(kg)
	b.position = pos
	b.rotation.y = deg_to_rad(yaw_deg)
	if _debug == "vcol":
		# plain lit vertex colour: checks normals and winding independently of the fur shader
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = m
	return b


func _look(cam: Camera3D, target: Vector3, from: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, target, Vector3.UP)
	cam.make_current()


func _clear() -> void:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	add_child(_world)
	_map = null


func _ground(p: Vector3) -> Vector3:
	if _map == null:
		return Vector3(p.x, 0.0, p.z)
	return Vector3(p.x, float(_map.call(&"_h", p.x, p.z)), p.z)


func _studio() -> Camera3D:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.37, 0.39)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_light(Vector3(-40.0, 35.0, 0.0), Color(1.0, 0.96, 0.9), 1.3, true)
	_light(Vector3(-15.0, -140.0, 0.0), Color(0.8, 0.88, 1.0), 0.45, false)
	_light(Vector3(-25.0, 165.0, 0.0), Color(1.0, 1.0, 1.0), 0.9, false)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.19, 0.18)
	gm.roughness = 0.95
	ground.material_override = gm
	_world.add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	_world.add_child(cam)
	return cam


func _light(rot_deg: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var l: DirectionalLight3D = DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = shadows
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	l.directional_shadow_max_distance = 15.0
	l.shadow_blur = 1.5
	_world.add_child(l)


func _game_light_flat() -> Camera3D:
	var env: Node3D = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	_world.add_child(env)
	(env.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.40, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	_world.add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	return cam


## The art-director map slice (same sky, sun, terrain shader and flora as the hunt), no old boars.
func _map_scene() -> Camera3D:
	var packed: PackedScene = load(MAP_SCENE)
	_map = packed.instantiate()
	_map.set(&"with_boars", false)
	_world.add_child(_map)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	return cam
