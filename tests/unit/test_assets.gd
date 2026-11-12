extends "res://tests/lib/test_case.gd"
## Asset contract (docs/arquitetura.md section 7): paths, base classes, required children, API calls,
## triangle/mesh budgets, root transform ownership, dimensions, flora, env, vfx, audio ids, UI theme/icons.

const WEAPON_IDS: Array[StringName] = [&"carbine_22", &"shotgun_12", &"rifle_308", &"rifle_3006", &"rifle_338"]
const BOAR_TYPES: Array[StringName] = [&"piglet", &"sow", &"boar", &"alpha"]
const BREEDS: Array[StringName] = [&"caramelo", &"foxhound", &"dogo"]

## prop id -> [size X, Y, Z, max triangles]
const PROPS: Dictionary = {
	&"farmhouse": [12.0, 6.0, 8.0, 900],
	&"barn": [16.0, 7.0, 10.0, 700],
	&"water_tank": [3.0, 8.0, 3.0, 300],
	&"fence_segment": [4.0, 1.3, 0.15, 80],
	&"gate": [4.0, 1.4, 0.2, 120],
	&"corn_bait": [1.0, 0.3, 1.0, 150],
	&"feed_trough": [3.0, 0.6, 0.8, 80],
}
const PROP_SIZE_TOLERANCE: float = 0.10
const PROP_SIZE_SLACK_M: float = 0.05

## flora id -> max triangles
const FLORA: Dictionary = {
	&"grass_tuft": 8, &"shrub": 60, &"cerrado_tree": 200, &"ipe": 250, &"buriti": 250, &"termite_mound": 60,
	&"soy_patch": 24, &"soy_eaten": 16, &"corn_patch": 36, &"corn_eaten": 20,
}

const SFX_IDS: Array[StringName] = [
	&"shot_22", &"shot_12", &"shot_308", &"shot_3006", &"shot_338", &"dry_fire", &"reload_start", &"reload_end",
	&"bolt_cycle", &"pump_cycle", &"weapon_swap", &"scope_in", &"scope_out",
	&"impact_dirt", &"impact_wood", &"impact_flesh",
	&"step_grass", &"step_dirt", &"player_hurt", &"player_heal", &"player_death", &"heartbeat", &"binocular_in",
	&"hit_marker", &"kill_confirm", &"crop_alarm", &"drone_buzz",
	&"boar_grunt", &"boar_squeal", &"boar_snort_alert", &"boar_scrape", &"boar_charge_roar", &"boar_eat", &"boar_death",
	&"dog_bark", &"dog_growl", &"dog_yelp", &"dog_whine",
	&"bait_drop", &"amb_cerrado_loop", &"amb_wind_loop", &"victory_sting", &"defeat_sting",
	&"ui_click", &"ui_buy", &"ui_error", &"ui_coin",
]

const THEME_VARIATIONS: Dictionary = {
	&"TitleLabel": "Label", &"HeaderLabel": "Label", &"MoneyLabel": "Label", &"GoldLabel": "Label",
	&"PrimaryButton": "Button", &"SecondaryButton": "Button", &"DangerButton": "Button",
	&"CardPanel": "PanelContainer", &"HudPanel": "PanelContainer", &"HudLabel": "Label", &"HudBigLabel": "Label",
	&"CropBar": "ProgressBar", &"HealthBar": "ProgressBar",
}

const EXTRA_ICONS: Array[String] = ["money", "gold", "boar", "crop", "health", "ammo", "lock", "dog_paw", "app_icon",
	"map_mato_grosso", "map_pantanal", "map_campanha_gaucha", "map_triangulo_mineiro",
	"btn_fire", "btn_aim", "btn_reload", "btn_swap", "btn_dog", "btn_item", "btn_crouch", "btn_pause",
	"joystick_base", "joystick_knob"]


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _meshes(root: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for c: Node in root.get_children():
		_meshes(c, out)
	return out


func _count_type(root: Node, type_name: String) -> int:
	var n: int = 1 if root.is_class(type_name) else 0
	for c: Node in root.get_children():
		n += _count_type(c, type_name)
	return n


func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	return mesh.get_faces().size() / 3


func _tree_tris(root: Node) -> int:
	var total: int = 0
	for mi: MeshInstance3D in _meshes(root):
		total += _tris(mi.mesh)
	return total


func _forbidden(root: Node, label: String) -> void:
	for t: String in ["PhysicsBody3D", "Area3D", "CollisionShape3D", "Skeleton3D", "AnimationPlayer", "OmniLight3D", "SpotLight3D"]:
		eq(_count_type(root, t), 0, "%s: no proibido em assets (%s)" % [label, t])


func _aabb_in_root(root: Node3D) -> AABB:
	var inv: Transform3D = root.global_transform.affine_inverse()
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(root):
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _spawn(path: String) -> Node3D:
	var scene: PackedScene = need_scene(path)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is Node3D:
		fail("%s: raiz nao e Node3D (%s)" % [path, node.get_class() if node != null else "null"])
		if node != null:
			node.free()
		return null
	return track(node) as Node3D


func _root_transform_snapshot(n: Node3D) -> Array:
	return [n.position, n.rotation, n.scale]


# --------------------------------------------------------------------------------------------
# Boar
# --------------------------------------------------------------------------------------------

func test_boar_visual_contract() -> void:
	var path: String = ScenePaths.BOAR_VISUAL
	var root: Node3D = _spawn(path)
	if root == null:
		return
	ok(root is BoarVisualBase, "raiz estende BoarVisualBase")
	if not root is BoarVisualBase:
		return
	var boar: BoarVisualBase = root as BoarVisualBase
	ok(boar.get_node_or_null("Head") is Node3D, "filho obrigatorio Head (Node3D)")
	_forbidden(boar, "boar_visual")
	var snap: Array = _root_transform_snapshot(boar)
	var materials: Dictionary = {}
	for type_id: StringName in BOAR_TYPES:
		var inst: Node3D = _spawn(path)
		var b: BoarVisualBase = inst as BoarVisualBase
		var weight: float = (float(Data.get_boar_type(type_id)["weight_min_kg"]) + float(Data.get_boar_type(type_id)["weight_max_kg"])) * 0.5
		b.setup(type_id, weight)
		var meshes: Array[MeshInstance3D] = _meshes(b)
		ok(meshes.size() <= 6, "%s: %d MeshInstance3D (<= 6)" % [type_id, meshes.size()])
		ok(_tree_tris(b) <= 600, "%s: %d triangulos (<= 600)" % [type_id, _tree_tris(b)])
		for mi: MeshInstance3D in meshes:
			var m: Material = mi.material_override
			if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				m = mi.mesh.surface_get_material(0)
			if m != null:
				materials[m.get_instance_id()] = true
	# Materials are shared between instances: not one per spawned boar.
	ok(materials.size() <= 4 + 1, "materiais distintos nos 4 tipos: %d (<= 4 + realce)" % materials.size())
	# Every API call, with plausible and extreme arguments.
	boar.setup(Ids.ALPHA, 220.0)
	for speed: float in [0.0, 1.5, 4.0, 5.5, 9.0, 1000.0, -3.0]:
		boar.set_locomotion(speed)
	boar.set_eating(true)
	boar.set_eating(false)
	boar.set_wounded(true)
	boar.set_wounded(false)
	boar.set_highlight(true)
	boar.set_highlight(false)
	boar.play_alert()
	boar.play_scrape()
	boar.play_attack()
	for zone: StringName in [Ids.ZONE_HEAD, Ids.ZONE_VITAL, Ids.ZONE_BODY, Ids.ZONE_REAR, &"zona_inventada"]:
		boar.play_hit(zone)
	boar.set_locomotion(4.0)
	await frames(30)
	boar.play_death()
	await frames(60)
	# A dead boar ignores everything and does not raise errors.
	boar.set_locomotion(8.0)
	boar.play_alert()
	boar.play_attack()
	boar.set_eating(true)
	boar.set_highlight(true)
	await frames(5)
	eq(_root_transform_snapshot(boar), snap, "o asset nao altera position/rotation/scale da raiz")


func test_boar_visual_fits_hit_zones_and_reference_size() -> void:
	var root: Node3D = _spawn(ScenePaths.BOAR_VISUAL)
	if root == null or not root is BoarVisualBase:
		return
	(root as BoarVisualBase).setup(Ids.BOAR, 100.0)
	await frames(2)
	var box: AABB = _aabb_in_root(root)
	var tol: float = 0.05
	var z_min: float = INF
	var z_max: float = -INF
	var y_max: float = 0.0
	var half_w: float = 0.0
	for zone: StringName in BoarVisualBase.HIT_ZONES:
		var spec: Array = BoarVisualBase.HIT_ZONES[zone]
		var c: Vector3 = spec[0]
		var s: Vector3 = spec[1]
		z_min = minf(z_min, c.z - s.z * 0.5)
		z_max = maxf(z_max, c.z + s.z * 0.5)
		y_max = maxf(y_max, c.y + s.y * 0.5)
		half_w = maxf(half_w, s.x * 0.5)
	print("INFO boar AABB @100kg: pos=%s size=%s (zonas: z %.2f..%.2f, y_max %.2f, meia largura %.2f)" % [box.position, box.size, z_min, z_max, y_max, half_w])
	ok(box.position.z >= z_min - tol - 0.2 and box.end.z <= z_max + tol + 0.2, "comprimento cabe no conjunto das zonas (+- 5 cm, +20 cm de focinho/cauda): z %.2f..%.2f" % [box.position.z, box.end.z])
	ok(box.end.y <= y_max + tol + 0.2, "altura cabe nas zonas (y max %.2f)" % box.end.y)
	ok(box.position.y >= -0.05, "pernas no chao: y min %.2f" % box.position.y)
	ok(box.size.x <= half_w * 2.0 + tol * 2.0 + 0.3, "largura %.2f razoavel" % box.size.x)
	ok(box.size.z >= 1.0 and box.size.z <= 1.8, "comprimento ~1,5 m (%.2f)" % box.size.z)


# --------------------------------------------------------------------------------------------
# Dog
# --------------------------------------------------------------------------------------------

func test_dog_visual_contract() -> void:
	var root: Node3D = _spawn(ScenePaths.DOG_VISUAL)
	if root == null:
		return
	ok(root is DogVisualBase, "raiz estende DogVisualBase")
	if not root is DogVisualBase:
		return
	var dog: DogVisualBase = root as DogVisualBase
	ok(dog.get_node_or_null("Mouth") is Marker3D, "filho obrigatorio Mouth (Marker3D)")
	_forbidden(dog, "dog_visual")
	var snap: Array = _root_transform_snapshot(dog)
	for breed: StringName in BREEDS:
		var inst: DogVisualBase = _spawn(ScenePaths.DOG_VISUAL) as DogVisualBase
		inst.setup(breed)
		ok(_meshes(inst).size() <= 6, "%s: %d MeshInstance3D (<= 6)" % [breed, _meshes(inst).size()])
		ok(_tree_tris(inst) <= 500, "%s: %d triangulos (<= 500)" % [breed, _tree_tris(inst)])
		ok(inst.get_node_or_null("Mouth") != null, "%s: Mouth presente apos setup" % breed)
	dog.setup(Ids.D_FOXHOUND)
	for speed: float in [0.0, 2.0, 6.0, -1.0, 500.0]:
		dog.set_locomotion(speed)
	dog.set_retreating(true)
	dog.set_retreating(false)
	dog.play_bark()
	dog.play_bite(true)
	dog.play_bite(false)
	dog.play_hurt()
	dog.play_point()
	await frames(30)
	dog.set_locomotion(3.0)
	await frames(10)
	dog.setup(&"raca_inventada")   # must not crash
	await frames(3)
	eq(_root_transform_snapshot(dog), snap, "o asset nao altera position/rotation/scale da raiz")


# --------------------------------------------------------------------------------------------
# Weapons
# --------------------------------------------------------------------------------------------

func test_weapon_views_contract() -> void:
	for id: StringName in WEAPON_IDS:
		var path: String = ScenePaths.weapon_view(id)
		var root: Node3D = _spawn(path)
		if root == null:
			continue
		if not root is WeaponViewBase:
			fail("%s: raiz nao estende WeaponViewBase" % path)
			continue
		var view: WeaponViewBase = root as WeaponViewBase
		view.setup(id)
		ok(view.get_node_or_null("Muzzle") is Marker3D, "%s: Muzzle (Marker3D)" % id)
		ok(view.get_node_or_null("AdsAnchor") is Marker3D, "%s: AdsAnchor (Marker3D)" % id)
		ok(view.get_muzzle() != null, "%s: get_muzzle()" % id)
		ok(view.get_ads_anchor() != null, "%s: get_ads_anchor()" % id)
		_forbidden(view, "weapon_view/%s" % id)
		var meshes: Array[MeshInstance3D] = _meshes(view)
		ok(meshes.size() <= 4, "%s: %d MeshInstance3D (<= 4)" % [id, meshes.size()])
		ok(_tree_tris(view) <= 1500, "%s: %d triangulos (<= 1500)" % [id, _tree_tris(view)])
		for mi: MeshInstance3D in meshes:
			eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s sem sombra" % [id, mi.name])
		var snap: Array = _root_transform_snapshot(view)
		view.play_draw(0.4)
		await frames(5)
		view.play_fire()
		view.play_cycle(0.5)
		await frames(5)
		view.play_reload(1.5)
		await frames(20)
		view.play_fire()
		view.play_cycle(0.0)
		view.play_reload(0.0)
		view.play_draw(0.0)
		await frames(5)
		# Strict about the root: the aim logic of the player owns it, the view must never move it by itself
		# beyond animating children. (Recoil animates children only.)
		eq(view.get_node("Muzzle").is_inside_tree(), true, "%s: Muzzle continua na arvore" % id)
		eq(_root_transform_snapshot(view)[2], snap[2], "%s: escala da raiz intacta" % id)
		var muzzle_pos: Vector3 = (view.get_muzzle() as Node3D).position
		ok(muzzle_pos.z < 0.0, "%s: Muzzle a frente da origem da camera (z=%.2f)" % [id, muzzle_pos.z])


func test_scoped_weapons_have_scope_data() -> void:
	for id: StringName in WEAPON_IDS:
		var w: Dictionary = Data.get_weapon(id)
		if bool(w.get("scoped", false)):
			ok(ResourceLoader.exists(ScenePaths.SCOPE_SHADER), "%s e luneta: shader de luneta existe" % id)


# --------------------------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------------------------

func test_props_contract() -> void:
	for id: StringName in PROPS:
		var path: String = ScenePaths.prop(id)
		var root: Node3D = _spawn(path)
		if root == null:
			continue
		var spec: Array = PROPS[id]
		_forbidden(root, "prop/%s" % id)
		var tris: int = _tree_tris(root)
		ok(tris <= int(spec[3]), "%s: %d triangulos (<= %d)" % [id, tris, int(spec[3])])
		var box: AABB = _aabb_in_root(root)
		var want: Vector3 = Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		print("INFO prop %s: AABB size %s (esperado %s), y min %.2f, tris %d" % [id, box.size, want, box.position.y, tris])
		for axis: int in 3:
			var allowed: float = want[axis] * PROP_SIZE_TOLERANCE + PROP_SIZE_SLACK_M
			ok(absf(box.size[axis] - want[axis]) <= allowed, "%s: dimensao %s = %.2f, esperado %.2f +- %.2f" % [id, "XYZ"[axis], box.size[axis], want[axis], allowed])
		ok(absf(box.position.y) <= 0.1, "%s: base no chao (y min %.2f)" % [id, box.position.y])
		ok(absf(box.get_center().x) <= want.x * 0.1 + 0.1 and absf(box.get_center().z) <= want.z * 0.1 + 0.1, "%s: centrado na pegada (centro %s)" % [id, box.get_center()])


# --------------------------------------------------------------------------------------------
# Flora
# --------------------------------------------------------------------------------------------

func test_flora_library() -> void:
	var lib: Script = AssetLoader.load_resource(ScenePaths.FLORA_LIBRARY) as Script
	if lib == null:
		skip_or_fail("flora_library.gd nao carrega")
		return
	for line: String in FileAccess.get_file_as_string(ScenePaths.FLORA_LIBRARY).split("\n"):
		ok(not line.strip_edges().begins_with("class_name"), "flora_library nao pode ter class_name")
	for id: StringName in FLORA:
		var mesh: Mesh = lib.call(&"build_mesh", id) as Mesh
		ok(mesh != null, "build_mesh(%s) != null" % id)
		if mesh == null:
			continue
		ok(mesh.get_surface_count() >= 1, "%s: tem superficie" % id)
		for s: int in mesh.get_surface_count():
			ok(mesh.surface_get_material(s) != null, "%s: superficie %d com material" % [id, s])
		var tris: int = _tris(mesh)
		ok(tris <= int(FLORA[id]), "%s: %d triangulos (<= %d)" % [id, tris, int(FLORA[id])])
		ok(tris > 0, "%s: nao vazio" % id)
		var box: AABB = mesh.get_aabb()
		ok(box.position.y >= -0.05, "%s: base na origem (y min %.2f)" % [id, box.position.y])
		ok(lib.call(&"build_mesh", id) == mesh, "%s: cache devolve a mesma malha" % id)
	var heights: Dictionary = {&"grass_tuft": 0.4, &"shrub": 1.0, &"cerrado_tree": 4.5, &"ipe": 7.0, &"buriti": 12.0,
		&"termite_mound": 1.2, &"soy_patch": 0.6, &"soy_eaten": 0.15, &"corn_patch": 2.0, &"corn_eaten": 0.5}
	for id: StringName in heights:
		var m: Mesh = lib.call(&"build_mesh", id) as Mesh
		if m != null:
			var h: float = m.get_aabb().end.y
			ok(absf(h - float(heights[id])) <= float(heights[id]) * 0.35 + 0.1, "%s: altura %.2f perto de %.2f" % [id, h, float(heights[id])])
	ok(lib.call(&"build_mesh", &"id_inexistente") == null, "id desconhecido devolve null")
	ok(lib.call(&"build_mesh", &"") == null, "id vazio devolve null")


# --------------------------------------------------------------------------------------------
# Environment, VFX
# --------------------------------------------------------------------------------------------

func test_environment_contract() -> void:
	var root: Node3D = _spawn(ScenePaths.environment(&"mato_grosso"))
	if root == null:
		return
	ok(root is MapEnvironmentBase, "raiz estende MapEnvironmentBase")
	var we: WorldEnvironment = root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun: DirectionalLight3D = root.get_node_or_null("Sun") as DirectionalLight3D
	ok(we != null and we.environment != null, "WorldEnvironment com Environment")
	ok(sun != null, "Sun (DirectionalLight3D)")
	if not root is MapEnvironmentBase or sun == null:
		return
	var env: MapEnvironmentBase = root as MapEnvironmentBase
	var presets: Dictionary = Data.get_game()["quality_presets"]
	for q: StringName in [Ids.Q_LOW, Ids.Q_MEDIUM, Ids.Q_HIGH, Ids.Q_LOW]:
		env.apply_quality(q)
		var p: Dictionary = presets[String(q)]
		eq(sun.shadow_enabled, bool(p["shadows"]), "Sun.shadow_enabled na qualidade %s" % q)
		if bool(p["shadows"]):
			near(sun.directional_shadow_max_distance, float(p["shadow_distance_m"]), 0.01, "distancia de sombra (%s)" % q)
	expect_errors()
	env.apply_quality(&"qualidade_inventada")   # must not crash; an engine error is acceptable
	await frames(2)
	eq(_count_type(root, "OmniLight3D") + _count_type(root, "SpotLight3D"), 0, "so o Sun ilumina")


func test_vfx_contract() -> void:
	for id: StringName in [&"impact_dust", &"impact_blood", &"impact_wood"]:
		var root: Node3D = _spawn(ScenePaths.vfx(id))
		if root == null:
			continue
		var p: CPUParticles3D = root as CPUParticles3D
		ok(p != null, "%s: raiz CPUParticles3D" % id)
		if p == null:
			continue
		ok(p.one_shot, "%s: one_shot" % id)
		ok(not p.emitting, "%s: emitting = false de inicio" % id)
		ok(p.amount <= 24, "%s: %d particulas (<= 24)" % [id, p.amount])
		ok(p.lifetime <= 0.8, "%s: lifetime %.2f (<= 0.8)" % [id, p.lifetime])
		p.emitting = true
		await frames(3)


# --------------------------------------------------------------------------------------------
# Audio
# --------------------------------------------------------------------------------------------

func test_sfx_library() -> void:
	for id: StringName in SFX_IDS:
		ok(Sfx.has_sound(id), "Sfx.has_sound(%s)" % id)
	ok(not Sfx.has_sound(&"som_inexistente"), "id inexistente nao existe")
	for bus_name: String in ["SFX", "Ambience", "UI"]:
		var idx: int = AudioServer.get_bus_index(bus_name)
		ok(idx >= 0, "barramento %s existe" % bus_name)
		if idx >= 0:
			eq(AudioServer.get_bus_send(idx), &"Master", "%s envia para Master" % bus_name)
			eq(AudioServer.get_bus_effect_count(idx), 0, "%s sem efeitos de barramento (Web)" % bus_name)


func test_sfx_calls_do_not_error() -> void:
	expect_errors()   # the unknown id is allowed to warn once
	var mark: int = error_mark()
	for id: StringName in SFX_IDS:
		if String(id).ends_with("_loop"):
			Sfx.play_loop(id)
			Sfx.stop_loop(id)
		else:
			Sfx.play(id)
			Sfx.play_3d(id, Vector3(3.0, 1.0, -5.0), -6.0, 1.2)
	Sfx.play(&"som_inexistente")
	Sfx.stop_loop(&"loop_inexistente")
	Sfx.stop_all_loops()
	Sfx.set_bus_volume(&"SFX", 0.5)
	Sfx.set_bus_volume(&"SFX", 1.0)
	Sfx.set_bus_volume(&"Master", 1.0)
	Sfx.unlock_audio()
	await frames(3)
	eq(errors_since(mark).size(), 0, "Sfx nao gera erros: %s" % str(errors_since(mark)))


# --------------------------------------------------------------------------------------------
# UI assets
# --------------------------------------------------------------------------------------------

func test_ui_theme_variations() -> void:
	var theme: Theme = need_scene_or_theme()
	if theme == null:
		return
	for variation: StringName in THEME_VARIATIONS:
		var base: String = THEME_VARIATIONS[variation]
		eq(String(theme.get_type_variation_base(variation)), base, "variacao %s deriva de %s" % [variation, base])
	ok(theme.default_font_size >= 18, "fonte base >= 18 (%d)" % theme.default_font_size)


func need_scene_or_theme() -> Theme:
	if not ResourceLoader.exists(ScenePaths.UI_THEME):
		skip_or_fail("theme.tres ainda nao entregue")
		return null
	var theme: Theme = load(ScenePaths.UI_THEME) as Theme
	if theme == null:
		fail("theme.tres nao carrega como Theme")
	return theme


func test_ui_icons_exist() -> void:
	var ids: Array[String] = []
	for id: StringName in Data.get_weapon_ids() + Data.get_equipment_ids() + Data.get_dog_ids():
		ids.append(String(id))
	ids.append_array(EXTRA_ICONS)
	var missing: Array[String] = []
	for id: String in ids:
		var path: String = ScenePaths.icon(StringName(id))
		if not FileAccess.file_exists(path):
			missing.append(id)
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			fail("icone %s existe mas nao carrega como Texture2D" % id)
	if not missing.is_empty():
		fail("icones ausentes (%d): %s" % [missing.size(), ", ".join(missing)])


func test_scope_shader_uniforms() -> void:
	if not ResourceLoader.exists(ScenePaths.SCOPE_SHADER):
		skip_or_fail("scope_overlay.gdshader nao existe")
		return
	var shader: Shader = load(ScenePaths.SCOPE_SHADER) as Shader
	ok(shader != null, "shader carrega")
	if shader == null:
		return
	ok(shader.get_mode() == Shader.MODE_CANVAS_ITEM, "shader_type canvas_item")
	var names: Array[String] = []
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(str(u["name"]))
	for want: String in ["reticle_kind", "vignette_radius", "reticle_color"]:
		ok(names.has(want), "uniform %s" % want)


func test_terrain_and_water_materials() -> void:
	for path: String in [ScenePaths.TERRAIN_MATERIAL, ScenePaths.WATER_MATERIAL]:
		if not ResourceLoader.exists(path):
			skip_or_fail("material ainda nao entregue: %s" % path)
			continue
		var m: ShaderMaterial = load(path) as ShaderMaterial
		ok(m != null and m.shader != null, "%s: ShaderMaterial com shader" % path)


func test_asset_loader_fallback_contract() -> void:
	AssetLoader.clear_missing()
	ok(AssetLoader.instantiate("res://assets/nao_existe.tscn") == null, "instantiate de ausente devolve null")
	ok(AssetLoader.load_resource("res://assets/nao_existe.tres") == null, "load_resource de ausente devolve null")
	ok(AssetLoader.get_missing().size() == 2, "dois caminhos ausentes registrados (%d)" % AssetLoader.get_missing().size())
	AssetLoader.instantiate("res://assets/nao_existe.tscn")
	ok(AssetLoader.get_missing().size() == 2, "mesmo caminho registrado uma vez")
	AssetLoader.clear_missing()
	eq(AssetLoader.get_missing().size(), 0, "clear_missing")
	ok(BoarVisualBase.create_fallback() != null, "BoarVisualBase.create_fallback")
	ok(DogVisualBase.create_fallback() != null, "DogVisualBase.create_fallback")
	ok(WeaponViewBase.create_fallback() != null, "WeaponViewBase.create_fallback")
	ok(MapEnvironmentBase.create_fallback() != null, "MapEnvironmentBase.create_fallback")
