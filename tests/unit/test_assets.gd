extends "res://tests/lib/test_case.gd"
## Asset contract (docs/arquitetura.md section 7): paths, base classes, required children, API calls,
## triangle/mesh budgets, root transform ownership, dimensions, flora, env, vfx, audio ids, UI theme/icons.

const WEAPON_IDS: Array[StringName] = [&"carbine_22", &"shotgun_12", &"rifle_308", &"rifle_3006", &"rifle_338"]
## First-person weapon budget (docs/arquitetura.md section 7.3): triangles with arms, mesh nodes, unique materials.
const WEAPON_MAX_TRIS: int = 12000
const WEAPON_MAX_MESHES: int = 4
const WEAPON_MAX_MATERIALS: int = 4
const BOAR_TYPES: Array[StringName] = [&"piglet", &"sow", &"boar", &"alpha"]
## Boar LOD contract (docs/arquitetura.md section 7.1): bands by visibility_range at rest (base FOV, no zoom).
const BOAR_NEAR_END_M: float = 25.0
const BOAR_MID_END_M: float = 60.0
const BOAR_MAX_MATERIALS_PER_TYPE: int = 1
const BOAR_LODS: Array[Dictionary] = [
	{"name": "near", "max_tris": 3000, "max_meshes": 7, "samples": [0.5, 10.0, BOAR_NEAR_END_M - 0.01]},
	{"name": "mid", "max_tris": 900, "max_meshes": 7, "samples": [BOAR_NEAR_END_M + 0.01, 40.0, BOAR_MID_END_M - 0.01]},
	{"name": "far", "max_tris": 300, "max_meshes": 2, "samples": [BOAR_MID_END_M + 0.01, 100.0, 500.0]},
]
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
	"barn", "map_mato_grosso", "map_pantanal", "map_campanha_gaucha", "map_triangulo_mineiro",
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

## True when `mi` is drawn at camera distance `d` (visibility_range_end == 0 means no upper limit).
## Margins (hysteresis) are ignored on purpose: the contract is about the rest ranges at the base FOV.
func _visible_at(mi: MeshInstance3D, d: float) -> bool:
	if d < mi.visibility_range_begin:
		return false
	return mi.visibility_range_end <= 0.0 or d < mi.visibility_range_end


## Checks one boar against the three LOD budgets of docs/arquitetura.md section 7.1.
## Samples distances inside each band (and just inside its edges) and takes the worst case.
func _check_boar_lods(boar: Node3D, meshes: Array[MeshInstance3D], label: String) -> void:
	for lod: Dictionary in BOAR_LODS:
		var worst_tris: int = 0
		var worst_count: int = 0
		for d: float in lod["samples"]:
			var tris: int = 0
			var count: int = 0
			for mi: MeshInstance3D in meshes:
				if _visible_at(mi, d):
					count += 1
					tris += _tris(mi.mesh)
			worst_tris = maxi(worst_tris, tris)
			worst_count = maxi(worst_count, count)
			ok(count > 0, "%s: nenhuma malha visivel a %.1f m (buraco entre LODs)" % [label, d])
		print("INFO boar LOD %-4s %-16s tris=%4d (<= %4d)  malhas=%d (<= %d)" % [lod["name"], label, worst_tris, lod["max_tris"], worst_count, lod["max_meshes"]])
		ok(worst_tris <= int(lod["max_tris"]), "%s: LOD %s: %d triangulos (<= %d)" % [label, lod["name"], worst_tris, lod["max_tris"]])
		ok(worst_count <= int(lod["max_meshes"]), "%s: LOD %s: %d MeshInstance3D visiveis (<= %d)" % [label, lod["name"], worst_count, lod["max_meshes"]])


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
		var spec: Dictionary = Data.get_boar_type(type_id)
		var w_min: float = float(spec["weight_min_kg"])
		var w_max: float = float(spec["weight_max_kg"])
		# Min, mean and max weight: the tusk bucket (and so the head mesh) changes with the weight.
		for weight: float in [w_min, (w_min + w_max) * 0.5, w_max]:
			var b: BoarVisualBase = _spawn(path) as BoarVisualBase
			b.setup(type_id, weight)
			var label: String = "%s @%.0fkg" % [type_id, weight]
			var type_materials: Dictionary = {}
			var meshes: Array[MeshInstance3D] = _meshes(b)
			_check_boar_lods(b, meshes, label)
			for mi: MeshInstance3D in meshes:
				var shadow_on: bool = mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ok(shadow_on == (mi.get_parent().name == &"Rig"), "%s: %s sombra so no corpo (cast_shadow=%d)" % [label, mi.get_path(), mi.cast_shadow])
				ok(mi.mesh != null, "%s: %s tem malha" % [label, mi.get_path()])
				if mi.mesh == null:
					continue
				for s: int in mi.mesh.get_surface_count():
					var m: Material = mi.mesh.surface_get_material(s)
					ok(m != null, "%s: %s superficie %d tem material" % [label, mi.get_path(), s])
					if m != null:
						type_materials[m.get_instance_id()] = true
						materials[m.get_instance_id()] = true
			ok(type_materials.size() <= BOAR_MAX_MATERIALS_PER_TYPE, "%s: %d materiais (<= %d)" % [label, type_materials.size(), BOAR_MAX_MATERIALS_PER_TYPE])
	# Materials are shared between instances: not one per spawned boar.
	ok(materials.size() <= BOAR_TYPES.size() + 1, "materiais distintos nos 4 tipos: %d (<= 4 + realce)" % materials.size())
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
		ok(meshes.size() <= WEAPON_MAX_MESHES, "%s: %d MeshInstance3D (<= %d)" % [id, meshes.size(), WEAPON_MAX_MESHES])
		var weapon_tris: int = _tree_tris(view)
		ok(weapon_tris <= WEAPON_MAX_TRIS, "%s: %d triangulos (<= %d)" % [id, weapon_tris, WEAPON_MAX_TRIS])
		var weapon_materials: int = _unique_materials(meshes).size()
		print("INFO weapon %s: %d MeshInstance3D, %d triangulos, %d materiais" % [id, meshes.size(), weapon_tris, weapon_materials])
		ok(weapon_materials <= WEAPON_MAX_MATERIALS, "%s: %d materiais unicos (<= %d)" % [id, weapon_materials, WEAPON_MAX_MATERIALS])
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


## Distinct materials (by instance id) used by the given meshes: material_override, per-surface overrides and
## the materials baked into the mesh surfaces.
func _unique_materials(meshes: Array[MeshInstance3D]) -> Dictionary:
	var found: Dictionary = {}
	for mi: MeshInstance3D in meshes:
		if mi.material_override != null:
			found[mi.material_override.get_instance_id()] = true
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m != null:
				found[m.get_instance_id()] = true
	return found


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


## Corn stock of the barn (docs/horda.md section 11.1): budget, geometry and API. The stage checks run off-tree,
## where the asset applies a stage instantly (the tween only exists inside the tree).
func _visible_volume(root: Node3D) -> float:
	var total: float = 0.0
	for mi: MeshInstance3D in _meshes(root):
		if mi.visible and mi.mesh != null:
			var b: AABB = mi.transform * mi.get_aabb()
			total += b.size.x * b.size.y * b.size.z
	return total


func _visible_meshes(root: Node3D) -> int:
	var n: int = 0
	for mi: MeshInstance3D in _meshes(root):
		if mi.visible and mi.scale.y > 0.05:
			n += 1
	return n


func test_barn_corn_contract() -> void:
	var path: String = ScenePaths.BARN_CORN
	var scene: PackedScene = need_scene(path)
	if scene == null:
		return
	var root: Node3D = scene.instantiate() as Node3D
	if root == null:
		fail("%s: raiz nao e Node3D" % path)
		return
	ok(root is CornStockVisualBase, "raiz estende CornStockVisualBase")
	if not root is CornStockVisualBase:
		root.free()
		return
	var stock: CornStockVisualBase = root as CornStockVisualBase
	eq(stock.name, &"BarnCorn", "nome do no raiz")
	_forbidden(stock, "barn_corn")
	var meshes: Array[MeshInstance3D] = _meshes(stock)
	var tris: int = _tree_tris(stock)
	print("INFO barn_corn: %d MeshInstance3D, %d triangulos" % [meshes.size(), tris])
	ok(meshes.size() <= 8, "%d MeshInstance3D (<= 8)" % meshes.size())
	ok(tris <= 900, "%d triangulos (<= 900)" % tris)
	var materials: Dictionary = {}
	for mi: MeshInstance3D in meshes:
		var m: Material = mi.material_override
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		if m != null:
			materials[m.get_instance_id()] = true
	ok(materials.size() >= 1 and materials.size() <= 2, "%d materiais (1 a 2)" % materials.size())
	var shadow_casters: int = 0
	for mi: MeshInstance3D in meshes:
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
	ok(shadow_casters <= 1, "so o monte de dentro projeta sombra (%d)" % shadow_casters)
	# API, off-tree: setup exactly once before add_child, then every stage.
	var ring: float = float(Data.get_horde().get("eat_ring_m", 10.0))
	stock.setup(ring)
	var volumes: Array[float] = []
	for pct: float in [100.0, 90.0, 60.0, 30.0, 10.0]:
		stock.set_stock_pct(pct)
		volumes.append(_visible_volume(stock))
	ok(not stock.is_inside_tree(), "off-tree")
	ok(volumes[0] > 0.0, "cheio mostra milho")
	for i: int in range(1, volumes.size()):
		ok(volumes[i] <= volumes[i - 1] + 0.001, "volume visivel nao cresce quando o estoque cai (%.1f -> %.1f)" % [volumes[i - 1], volumes[i]])
	ok(volumes[volumes.size() - 1] < volumes[0] * 0.5, "10%% mostra bem menos que cheio (%.1f vs %.1f)" % [volumes[volumes.size() - 1], volumes[0]])
	stock.set_stock_pct(100.0)
	eq(_visible_meshes(stock), 7, "cheio: monte de dentro + 6 de fora visiveis")
	var gnawed_visible: bool = false
	stock.set_stock_pct(0.0)
	var heaps_shown: int = 0
	for mi: MeshInstance3D in _meshes(stock):
		if mi.name.begins_with("Outer") or mi.name == "InnerPile":
			if mi.visible and mi.scale.y > 0.05:
				heaps_shown += 1
		elif mi.visible:
			gnawed_visible = true
	ok(gnawed_visible, "vazio (0%) mostra a palha/espigas roidas no chao")
	eq(heaps_shown, 0, "vazio (0%) nao mostra monte nenhum")
	stock.set_stock_pct(100.0)
	# Geometry at full stock: inner pile fits the barn (14 x 8 m, <= 3 m); the outer heaps sit on the ring.
	var on_ring: int = 0
	var first_is_north: bool = false
	for mi: MeshInstance3D in _meshes(stock):
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.get_aabb()
		var c: Vector3 = b.get_center()
		var dist: float = Vector2(mi.position.x, mi.position.z).length()
		if mi.name == "InnerPile":
			ok(b.size.x <= 14.0 + 0.01 and b.size.z <= 8.0 + 0.01, "monte de dentro cabe em 14 x 8 m (%.1f x %.1f)" % [b.size.x, b.size.z])
			ok(b.end.y <= 3.0 + 0.01, "monte de dentro <= 3 m de altura (%.2f)" % b.end.y)
			ok(absf(c.x) <= 7.0 and c.z >= -5.0 and c.z <= 5.0, "monte de dentro dentro do galpao (centro %s)" % c)
		elif mi.name.begins_with("Outer"):
			if absf(dist - ring) <= 0.01:
				on_ring += 1
			if mi.name == "Outer_0" and mi.position.z < -ring + 0.01 and absf(mi.position.x) < 0.01:
				first_is_north = true
	ok(on_ring >= 6, "ao menos 6 montes no anel de %.1f m (%d)" % [ring, on_ring])
	ok(first_is_north, "o primeiro monte fica em -Z")
	# In the tree: stage changes animate (<= 0.5 s), under_attack shakes only children, root untouched.
	track(stock)
	var snap: Array = _root_transform_snapshot(stock)
	stock.set_stock_pct(60.0)
	stock.set_stock_pct(30.0)
	stock.set_under_attack(true)
	await frames(10)
	stock.set_stock_pct(10.0)
	stock.set_stock_pct(0.0)
	stock.set_under_attack(false)
	await wait_s(0.6)
	var after_volume: float = _visible_volume(stock)
	ok(after_volume < volumes[0] * 0.5, "depois da transicao (0,6 s) o estoque vazio esta pequeno (%.1f)" % after_volume)
	stock.set_stock_pct(100.0)
	await wait_s(0.6)
	near(_visible_volume(stock), volumes[0], volumes[0] * 0.05, "voltar a 100% restaura o visual cheio")
	eq(_root_transform_snapshot(stock), snap, "o asset nao altera position/rotation/scale da raiz")
	stock.set_stock_pct(100.0)   # idempotent
	stock.set_under_attack(true)
	stock.set_under_attack(true)
	stock.set_under_attack(false)
	await frames(2)


func test_barn_corn_odd_percentages_and_attack_without_errors() -> void:
	var scene: PackedScene = need_scene(ScenePaths.BARN_CORN)
	if scene == null:
		return
	var stock: CornStockVisualBase = scene.instantiate() as CornStockVisualBase
	if stock == null:
		fail("barn_corn nao instancia como CornStockVisualBase")
		return
	stock.setup(10.0)
	track(stock)
	stock.set_stock_pct(100.0)
	var mark: int = error_mark()
	for pct: float in [0.0, 10.0, 30.0, 60.0, 90.0, 100.0, -5.0, 0.0001, 25.0, 25.001, 250.0]:
		stock.set_stock_pct(pct)
		stock.set_under_attack(int(pct) % 2 == 0)
		await frames(2)
	stock.set_under_attack(false)
	await frames(2)
	eq(errors_since(mark).size(), 0, "barn_corn sem erros com percentuais fora do normal: %s" % str(errors_since(mark)))


func test_horde_sounds_exist_and_play() -> void:
	for id: StringName in [&"horde_wave_start", &"horde_wave_clear"]:
		ok(Sfx.has_sound(id), "Sfx.has_sound(%s)" % id)
	var mark: int = error_mark()
	Sfx.play(&"horde_wave_start")
	Sfx.play(&"horde_wave_clear")
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar os sons de horda nao gera erros: %s" % str(errors_since(mark)))
	# no recorded files: the synthesis fallback still has both
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	for id: StringName in [&"horde_wave_start", &"horde_wave_clear"]:
		ok(fb.call(&"has_sound", id), "fallback: has_sound(%s)" % id)
		var stream: AudioStreamWAV = fb.call(&"_get_stream", id) as AudioStreamWAV
		ok(stream != null, "fallback: %s sintetizado" % id)
		if stream != null:
			var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
			var channels: float = 2.0 if stream.stereo else 1.0
			var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
			ok(seconds > 0.3 and seconds < 3.0, "%s dura %.2f s (esperado ~1 a 1,5 s)" % [id, seconds])
	await frames(2)


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


func test_sfx_uses_recorded_files_and_falls_back_to_synthesis() -> void:
	# Every id has a recorded file: the autoload uses it and does not run the synthesis at startup.
	for id: StringName in SFX_IDS:
		var path: String = "res://assets/audio/sfx/%s.mp3" % id
		ok(ResourceLoader.exists(path), "arquivo gravado existe: %s" % path)
		ok(Sfx.get(&"_streams").get(id) is AudioStreamMP3, "%s usa o MP3 gravado" % id)
	ok(Sfx.synth_ms < 5.0, "sintese nao roda no _ready quando todos os arquivos existem (%.1f ms)" % Sfx.synth_ms)
	# No recorded files (folder that does not exist): every id still has a sound, synthesized.
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	for id: StringName in SFX_IDS:
		ok(fb.call(&"has_sound", id), "fallback: has_sound(%s)" % id)
		ok(fb.call(&"_get_stream", id) is AudioStreamWAV, "fallback: %s sintetizado" % id)
	await frames(2)


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


func test_sfx_music() -> void:
	expect_errors()   # the missing music id warns once
	var mark: int = error_mark()
	ok(ResourceLoader.exists("res://assets/audio/music/music_menu.mp3"), "music_menu.mp3 existe")
	ok(not Sfx.has_sound(&"music_menu"), "has_sound nao inclui ids de musica")
	ok(not Sfx.is_music_playing(), "sem musica no inicio")
	Sfx.play_music(&"music_menu", -6.0, 0.0)
	ok(Sfx.is_music_playing(&"music_menu"), "play_music toca music_menu")
	ok(Sfx.is_music_playing(), "is_music_playing() sem id")
	ok(not Sfx.is_music_playing(&"outra"), "outro id nao toca")
	var player: AudioStreamPlayer = Sfx.get(&"_music_player")
	ok(player != null and player.playing, "player de musica esta tocando")
	eq(player.bus, &"Ambience", "musica usa o barramento Ambience")
	var stream: AudioStreamMP3 = player.stream as AudioStreamMP3
	ok(stream != null and stream.loop, "musica em loop")
	var pool_ok: bool = true
	for p: Node in Sfx.get(&"_pool_2d"):
		pool_ok = pool_ok and p != player
	ok(pool_ok, "musica fora do pool de efeitos")
	# Idempotent: same id does not restart the stream; only the volume changes.
	await frames(3)
	var pos: float = player.get_playback_position()
	Sfx.play_music(&"music_menu", -3.0, 0.0)
	ok(player.playing and player.get_playback_position() >= pos, "mesmo id nao reinicia")
	near(player.volume_db, -3.0, 0.01, "mesmo id ajusta o volume")
	Sfx.stop_all_loops()
	ok(Sfx.is_music_playing(&"music_menu") and player.playing, "stop_all_loops nao para a musica")
	# Missing id: no error beyond the warning, current music is untouched.
	Sfx.play_music(&"musica_inexistente")
	Sfx.play_music(&"musica_inexistente")
	ok(Sfx.is_music_playing(&"music_menu"), "id inexistente nao troca a musica")
	# Fade out then stop.
	Sfx.stop_music(0.1)
	ok(not Sfx.is_music_playing(), "stop_music limpa o estado na hora")
	await frames(20)
	ok(not player.playing, "stop_music para o player depois do fade")
	Sfx.play_music(&"music_menu", 0.0, 0.0)
	Sfx.stop_music(0.0)
	ok(not player.playing and not Sfx.is_music_playing(), "stop_music sem fade para na hora")
	Sfx.stop_music()
	eq(errors_since(mark).size(), 0, "musica nao gera erros: %s" % str(errors_since(mark)))


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
