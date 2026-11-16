extends Control
## Preview: the five first-person weapons, each in its own SubViewport (own world).
## User args (after --): --pose=hip|ads|fire|cycle|reload|draw   --weapon=<id> (single, full screen)
##   --phase=<0..1>: jump the animation to that share of its length and freeze it there (for screenshots)

const GAME_FOV: float = 75.0
## ADS zoom of the open-sight guns (weapons.json ads_zoom_min of the .22); the scoped ones hide the view in game.
const ADS_ZOOM: float = 1.5
const IDS: Array[StringName] = [&"carbine_22", &"shotgun_12", &"rifle_308", &"rifle_3006", &"rifle_338"]

var _pose: String = "hip"
var _views: Array[WeaponViewBase] = []
var _t: float = 0.0
var _fired: bool = false
var _phase: float = -1.0


func _ready() -> void:
	var single: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose="):
			_pose = a.trim_prefix("--pose=")
		elif a.begins_with("--weapon="):
			single = a.trim_prefix("--weapon=")
		elif a.begins_with("--phase="):
			_phase = clampf(float(a.trim_prefix("--phase=")), 0.0, 1.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grid: GridContainer = GridContainer.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	var list: Array[StringName] = IDS
	if single != "":
		list = [StringName(single)]
		grid.columns = 1
	else:
		grid.columns = 3
	for id in list:
		grid.add_child(_cell(id))
	if single == "":
		grid.add_child(_cell(&"rifle_308", "ads" if _pose == "hip" else "hip"))


func _cell(id: StringName, pose: String = "") -> Control:
	if pose == "":
		pose = _pose
	var c: SubViewportContainer = SubViewportContainer.new()
	c.stretch = true
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	c.add_child(vp)
	var world: Node3D = Node3D.new()
	vp.add_child(world)
	world.add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.70, 0.60, 0.30)
	ground.material_override = gm
	world.add_child(ground)
	var lib: Script = load("res://assets/models/flora/flora_library.gd")
	for i in 5:
		var tree: MeshInstance3D = MeshInstance3D.new()
		tree.mesh = lib.call(&"build_mesh", &"cerrado_tree" if i != 2 else &"ipe")
		tree.position = Vector3(-16.0 + i * 8.0, 0, -30.0 - (i % 2) * 8.0)
		world.add_child(tree)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0, 1.65, 0)
	cam.fov = GAME_FOV   # same lens as player.tscn
	cam.near = 0.05
	world.add_child(cam)
	var view: WeaponViewBase = (load("res://assets/models/weapons/%s_view.tscn" % id) as PackedScene).instantiate()
	cam.add_child(view)
	view.setup(id)
	if pose == "ads":
		var a: Vector3 = view.get_ads_anchor().position
		view.position = Vector3(-a.x, -a.y, 0.0)
		cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(GAME_FOV) * 0.5) / ADS_ZOOM))
	view.set_meta("pose", pose)
	_views.append(view)
	var lbl: Label = Label.new()
	lbl.text = "%s  [%s]" % [id, pose]
	lbl.position = Vector2(8, 4)
	c.add_child(lbl)
	return c


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	if _fired:
		# "fire" repeats a shot every 0.25 s so a screenshot at any time catches the flash
		if (_pose == "fire" and fmod(_t, 0.25) < delta) or _pose == "fire_hold":
			for v in _views:
				v.play_fire()
		return
	_fired = true
	for v in _views:
		var length: float = 0.0
		match String(v.get_meta("pose")):
			"fire", "fire_hold":
				v.play_fire()
				length = 0.2
			"cycle":
				v.play_cycle(1.2)
				length = 1.2
			"reload":
				v.play_reload(2.4)
				length = 2.4
			"draw":
				v.play_draw(1.2)
				length = 1.2
		if _phase >= 0.0 and length > 0.0:
			v.call(&"_process", _phase * length)
			v.set_process(false)
