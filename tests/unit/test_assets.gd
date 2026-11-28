extends "res://tests/lib/test_case.gd"
## Asset contract (docs/arquitetura.md section 7): paths, base classes, required children, API calls,
## triangle/mesh budgets, root transform ownership, dimensions, flora, env, vfx, audio ids, UI theme/icons.

const WEAPON_IDS: Array[StringName] = [&"carbine_22", &"shotgun_12", &"rifle_308", &"rifle_3006", &"rifle_338"]
## First-person weapon budget (docs/arquitetura.md section 7.3): triangles with arms, mesh nodes, unique materials.
const WEAPON_MAX_TRIS: int = 12000
const WEAPON_MAX_MESHES: int = 4
const WEAPON_MAX_MATERIALS: int = 4
## The first-person knife with the arm (docs/plano_faca_mochila_folego.md 1.7): tighter than the guns.
const KNIFE_MAX_TRIS: int = 4000
const KNIFE_MAX_MESHES: int = 3
const KNIFE_MAX_MATERIALS: int = 3
const BOAR_TYPES: Array[StringName] = [&"piglet", &"sow", &"boar", &"alpha", &"boss"]
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
## Dog LOD contract (docs/arquitetura.md section 7.2): bands by visibility_range at rest (base FOV, no zoom).
const DOG_NEAR_END_M: float = 20.0
const DOG_MID_END_M: float = 50.0
const DOG_LODS: Array[Dictionary] = [
	{"name": "near", "max_tris": 2500, "max_meshes": 8, "samples": [0.5, 10.0, DOG_NEAR_END_M - 0.01]},
	{"name": "mid", "max_tris": 800, "max_meshes": 8, "samples": [DOG_NEAR_END_M + 0.01, 35.0, DOG_MID_END_M - 0.01]},
	{"name": "far", "max_tris": 250, "max_meshes": 2, "samples": [DOG_MID_END_M + 0.01, 100.0, 500.0]},
]

## prop id -> [size X, Y, Z, max triangles] (docs/arquitetura.md section 7.4). Y is the height above the ground.
const PROPS: Dictionary = {
	&"farmhouse": [12.0, 6.0, 8.0, 3000],
	&"barn": [16.0, 7.0, 10.0, 2400],
	&"water_tank": [3.0, 8.0, 3.0, 1000],
	&"fence_segment": [4.0, 1.3, 0.15, 240],
	&"gate": [4.0, 1.4, 0.2, 400],
	&"corn_bait": [1.0, 0.3, 1.0, 500],
	&"feed_trough": [3.0, 0.6, 0.8, 300],
}
const PROP_SIZE_TOLERANCE: float = 0.10
const PROP_SIZE_SLACK_M: float = 0.05
const PROP_MAX_MESHES: int = 4
## Posts may be buried up to this depth below Y=0 (section 7.4); table heights count only the part above ground.
const PROP_MAX_BURIAL_M: float = 0.15
const PROP_BURIAL_EPS_M: float = 0.001
## Informative only (never asserted: it varies with the machine): cold build time of all props together.
const PROP_BUILD_BUDGET_MS: float = 150.0
## docs/plano_horda_nivel2.md section 7: the wooden grain bin (tulha) is one more mesh (the 9th).
const BARN_CORN_MAX_TRIS: int = 1000
const BARN_CORN_MAX_MESHES: int = 9
## docs/plano_horda_nivel2.md section 7: ammo_crate.tscn
const AMMO_CRATE_MAX_TRIS: int = 300
## Bin footprint in the barn frame (x [-6, 6], z [1.6, 4.7]); walls 1.2 m.
const BIN_RECT: Rect2 = Rect2(-6.0, 1.6, 12.0, 3.1)
const BIN_WALL_H: float = 1.2

## flora id -> max triangles
const FLORA: Dictionary = {
	&"grass_tuft": 8, &"shrub": 150, &"cerrado_tree": 600, &"ipe": 750, &"buriti": 600, &"termite_mound": 200,
	&"soy_patch": 24, &"soy_eaten": 16, &"corn_patch": 36, &"corn_eaten": 20,
}
## Contract 7.5: lowest allowed Y of a flora mesh (the base may sink this far below the origin).
const FLORA_BASE_SINK_M: float = 0.15
const FLORA_TREE_IDS: Array[StringName] = [&"cerrado_tree", &"ipe", &"buriti"]
## Contract 7.5: trees of the whole map <= 1.5 x the 0.6.0 sum (46 408 tris) = 69 612, rounded to 70 000.
const FLORA_TREE_TRIS_MAX: int = 70000
const FLORA_BUILD_INFO_MS: float = 200.0
const FLORA_MAP_ID: StringName = &"mato_grosso"

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
	"btn_fire", "btn_aim", "btn_reload", "btn_swap", "btn_dog", "btn_item", "btn_crouch", "btn_pause", "btn_knife",
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
	ok(materials.size() <= BOAR_TYPES.size() + 1, "materiais distintos nos %d tipos: %d (<= tipos + realce)" % [BOAR_TYPES.size(), materials.size()])
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

## Checks one dog against the three LOD budgets of docs/arquitetura.md section 7.2 (same sampling as the boar).
func _check_dog_lods(meshes: Array[MeshInstance3D], label: String) -> void:
	for lod: Dictionary in DOG_LODS:
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
		print("INFO dog LOD %-4s %-9s tris=%4d (<= %4d)  malhas=%d (<= %d)" % [lod["name"], label, worst_tris, lod["max_tris"], worst_count, lod["max_meshes"]])
		ok(worst_tris <= int(lod["max_tris"]), "%s: LOD %s: %d triangulos (<= %d)" % [label, lod["name"], worst_tris, lod["max_tris"]])
		ok(worst_count <= int(lod["max_meshes"]), "%s: LOD %s: %d MeshInstance3D visiveis (<= %d)" % [label, lod["name"], worst_count, lod["max_meshes"]])


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
	var dog_materials: Dictionary = {}
	for breed: StringName in BREEDS:
		var inst: DogVisualBase = _spawn(ScenePaths.DOG_VISUAL) as DogVisualBase
		var t0: int = Time.get_ticks_usec()
		inst.setup(breed)
		print("INFO dog %-9s setup (montagem): %.2f ms (informativo, sem limite)" % [breed, float(Time.get_ticks_usec() - t0) / 1000.0])
		var dog_meshes: Array[MeshInstance3D] = _meshes(inst)
		_check_dog_lods(dog_meshes, str(breed))
		for mi: MeshInstance3D in dog_meshes:
			ok(mi.mesh != null, "%s: %s tem malha" % [breed, mi.get_path()])
			var is_body: bool = mi.name in [&"BodyNear", &"BodyMid", &"Far"]
			if not is_body:
				eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s sem sombra (so o corpo projeta)" % [breed, mi.get_path()])
		var breed_materials: Dictionary = _unique_materials(dog_meshes)
		ok(breed_materials.size() == 1, "%s: %d material(is) distinto(s) (== 1)" % [breed, breed_materials.size()])
		for id: int in breed_materials:
			dog_materials[id] = true
		ok(inst.get_node_or_null("Mouth") is Marker3D, "%s: Mouth (Marker3D) presente apos setup" % breed)
	ok(dog_materials.size() == 1, "material unico compartilhado entre as %d racas: %d (== 1)" % [BREEDS.size(), dog_materials.size()])
	ok(dog.get_node_or_null("Mouth") is Marker3D, "Mouth (Marker3D) presente na raiz depois dos setups")
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


## docs/plano_faca_mochila_folego.md 1.7 and 2.10 (ART4, F4): the first-person knife view. Tighter than the guns:
## 4000 triangles with the arm, 3 MeshInstance3D, 3 materials, no shadows, Muzzle + AdsAnchor.
func test_knife_view_contract() -> void:
	var path: String = ScenePaths.weapon_view(Ids.KNIFE)
	eq(path, "res://assets/models/weapons/knife_view.tscn", "caminho da view da faca")
	var root: Node3D = _spawn(path)
	if root == null:
		return
	if not root is WeaponViewBase:
		fail("%s: raiz nao estende WeaponViewBase" % path)
		return
	var view: WeaponViewBase = root as WeaponViewBase
	view.setup(Ids.KNIFE)
	ok(view.get_node_or_null("Muzzle") is Marker3D, "knife: Muzzle (Marker3D)")
	ok(view.get_node_or_null("AdsAnchor") is Marker3D, "knife: AdsAnchor (Marker3D)")
	ok(view.get_muzzle() != null and view.get_ads_anchor() != null, "knife: get_muzzle() e get_ads_anchor()")
	_forbidden(view, "weapon_view/knife")
	var meshes: Array[MeshInstance3D] = _meshes(view)
	ok(meshes.size() >= 1, "knife: tem malha (%d)" % meshes.size())
	ok(meshes.size() <= KNIFE_MAX_MESHES, "knife: %d MeshInstance3D (<= %d)" % [meshes.size(), KNIFE_MAX_MESHES])
	var tris: int = _tree_tris(view)
	ok(tris > 0, "knife: triangulos > 0")
	ok(tris <= KNIFE_MAX_TRIS, "knife: %d triangulos (<= %d)" % [tris, KNIFE_MAX_TRIS])
	var materials: int = _unique_materials(meshes).size()
	print("INFO knife view: %d MeshInstance3D, %d triangulos, %d materiais" % [meshes.size(), tris, materials])
	ok(materials >= 1 and materials <= KNIFE_MAX_MATERIALS, "knife: %d materiais unicos (<= %d)" % [materials, KNIFE_MAX_MATERIALS])
	for mi: MeshInstance3D in meshes:
		eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "knife: %s sem sombra" % mi.name)
	# the gun hooks are harmless no-ops on the knife
	var snap: Array = _root_transform_snapshot(view)
	var rest_tip: Vector3 = (view.get_muzzle() as Node3D).position
	view.play_draw(0.4)
	view.play_fire()
	view.play_cycle(0.5)
	view.play_reload(1.5)
	await frames(3)
	eq((view.get_muzzle() as Node3D).position, rest_tip, "knife: play_fire/cycle/reload/draw nao mexem a faca")
	# the swing: the blade tip leaves the rest pose and, after swing_s, comes back to it
	view.play_melee(0.45)
	var moved: bool = false
	for i: int in 12:
		await frames(1)
		if (view.get_muzzle() as Node3D).position.distance_to(rest_tip) > 0.01:
			moved = true
	ok(moved, "knife: play_melee move a ponta da lamina")
	await wait_s(0.6)
	near((view.get_muzzle() as Node3D).position.distance_to(rest_tip), 0.0, 0.001, "knife: a faca volta ao repouso no fim do golpe")
	view.play_melee(0.0)   # a zero duration must not divide by zero or hang
	await wait_s(0.2)
	near((view.get_muzzle() as Node3D).position.distance_to(rest_tip), 0.0, 0.001, "knife: play_melee(0) tambem volta ao repouso")
	eq(_root_transform_snapshot(view)[2], snap[2], "knife: escala da raiz intacta")
	ok(rest_tip.z < 0.0, "knife: a ponta em repouso fica a frente da camera (z=%.2f)" % rest_tip.z)
	if view.has_method(&"get_tip_at"):
		# the contract (2.10): the tip passes the centre of the screen at ~30% of the swing (x goes from the right
		# of the screen to its left; it crosses again on the way back, which is not what is checked here)
		var start_x: float = (view.call(&"get_tip_at", 0.0) as Vector3).x
		ok(start_x > 0.0, "knife: em repouso a ponta fica a direita do centro (x=%.3f)" % start_x)
		var cross_u: float = -1.0
		for step: int in range(0, 101):
			var u: float = float(step) / 100.0
			if (view.call(&"get_tip_at", u) as Vector3).x <= 0.0:
				cross_u = u
				break
		print("INFO knife view: a ponta cruza o centro (x = 0) pela 1a vez em u=%.2f" % cross_u)
		ok(cross_u >= 0.25 and cross_u <= 0.40, "knife: a ponta cruza o centro da tela perto de 30%% do golpe (em %.2f)" % cross_u)
		var at_strike: Vector3 = view.call(&"get_tip_at", 0.30)
		ok(absf(at_strike.x) <= 0.05, "knife: a 30%% do golpe a ponta passa a menos de 5 cm do centro (x=%.3f m)" % at_strike.x)
		ok(at_strike.z < -0.4, "knife: a 30%% do golpe a ponta esta bem a frente da camera (z=%.2f)" % at_strike.z)


## The knife swing hook exists on every gun view and is harmless there (guns ignore it).
func test_gun_views_ignore_play_melee() -> void:
	for id: StringName in WEAPON_IDS:
		var root: Node3D = _spawn(ScenePaths.weapon_view(id))
		if root == null or not root is WeaponViewBase:
			continue
		var view: WeaponViewBase = root as WeaponViewBase
		view.setup(id)
		var nodes_before: int = _count_type(view, "Node")
		var mark: int = error_mark()
		view.play_melee(0.45)
		view.play_melee(0.0)
		await frames(3)
		eq(errors_since(mark).size(), 0, "%s: play_melee nao gera erros: %s" % [id, str(errors_since(mark))])
		eq(_count_type(view, "Node"), nodes_before, "%s: play_melee nao cria nem remove nos" % id)
		ok(is_instance_valid(view.get_muzzle()), "%s: Muzzle continua valido depois do play_melee" % id)


func test_knife_art_and_icons_exist() -> void:
	## docs/plano_faca_mochila_folego.md 2.10 (ART4): portrait 1024x512, the two SVGs 128x128.
	var art_path: String = ScenePaths.weapon_art(Ids.KNIFE)
	eq(art_path, "res://assets/ui/weapons/knife.png", "caminho do retrato da faca")
	ok(FileAccess.file_exists(art_path), "retrato %s existe" % art_path)
	var art: Texture2D = load(art_path) as Texture2D
	ok(art != null, "o retrato carrega como Texture2D")
	if art != null:
		eq(art.get_size(), Vector2(1024.0, 512.0), "knife.png tem 1024x512")
		var img: Image = art.get_image()
		if img != null:
			ok(img.detect_alpha() != Image.ALPHA_NONE, "knife.png tem transparencia (retrato recortado)")
	ok(UiKit.weapon_art(Ids.KNIFE) != null, "UiKit.weapon_art(knife) nao e nulo")
	ok(UiKit.weapon_art_rect(Ids.KNIFE, 160.0) != null, "UiKit.weapon_art_rect(knife) nao e nulo")
	for icon_id: StringName in [&"knife", &"btn_knife"]:
		var icon_path: String = ScenePaths.icon(icon_id)
		ok(FileAccess.file_exists(icon_path), "icone %s existe" % icon_path)
		var tex: Texture2D = load(icon_path) as Texture2D
		ok(tex != null, "%s carrega como Texture2D" % icon_id)
		if tex != null:
			eq(tex.get_size(), Vector2(128.0, 128.0), "%s tem 128x128" % icon_id)
		ok(UiKit.icon(icon_id) != null, "UiKit.icon(%s) nao e nulo" % icon_id)
		ok(UiKit.icon_rect(icon_id, 48.0) != null, "UiKit.icon_rect(%s) nao e nulo" % icon_id)


func test_knife_swing_sound_exists_and_plays() -> void:
	## docs/plano_faca_mochila_folego.md 2.10 (ART4): knife_swing (~0.25 s), synthesized on demand (SynthWeapons.LAZY_IDS).
	ok(Sfx.has_sound(&"knife_swing"), "Sfx.has_sound(knife_swing)")
	ok(SynthWeapons.LAZY_IDS.has(&"knife_swing"), "knife_swing esta em SynthWeapons.LAZY_IDS")
	var mark: int = error_mark()
	Sfx.play(&"knife_swing")
	Sfx.play_3d(&"knife_swing", Vector3(1.0, 1.0, 1.0))
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar knife_swing nao gera erros: %s" % str(errors_since(mark)))
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	ok(fb.call(&"has_sound", &"knife_swing"), "fallback: has_sound(knife_swing)")
	var stream: AudioStreamWAV = fb.call(&"_get_stream", &"knife_swing") as AudioStreamWAV
	ok(stream != null, "fallback: knife_swing sintetizado")
	if stream != null:
		var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
		var channels: float = 2.0 if stream.stereo else 1.0
		var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
		ok(seconds >= 0.1 and seconds <= 0.6, "knife_swing dura %.2f s (esperado ~0,25 s)" % seconds)
		ok(stream.loop_mode != AudioStreamWAV.LOOP_FORWARD, "knife_swing nao e loop")
		var peak: int = 0
		if stream.format == AudioStreamWAV.FORMAT_16_BITS:
			var i: int = 0
			while i + 1 < stream.data.size():
				peak = maxi(peak, absi(stream.data.decode_s16(i)))
				i += 2 * 16
		ok(stream.format != AudioStreamWAV.FORMAT_16_BITS or peak > 500, "knife_swing nao e silencio (pico %d)" % peak)
	var live: Variant = (Sfx.get(&"_streams") as Dictionary).get(&"knife_swing")
	ok(live is AudioStreamWAV or live is AudioStreamMP3, "knife_swing no Sfx: WAV sintetizado ou MP3 gravado")
	var prompts_text: String = FileAccess.get_file_as_string("res://assets/audio/sfx_prompts.json")
	ok(prompts_text.contains("\"id\": \"knife_swing\""), "sfx_prompts.json tem a entrada knife_swing")
	ok(JSON.parse_string(prompts_text) != null, "sfx_prompts.json continua JSON valido")
	# the hit reuses the existing sounds (no new ones for the impact)
	ok(Sfx.has_sound(&"impact_flesh"), "o acerto reutiliza impact_flesh")
	await frames(2)


func test_scoped_weapons_have_scope_data() -> void:
	for id: StringName in WEAPON_IDS:
		var w: Dictionary = Data.get_weapon(id)
		if bool(w.get("scoped", false)):
			ok(ResourceLoader.exists(ScenePaths.SCOPE_SHADER), "%s e luneta: shader de luneta existe" % id)


# --------------------------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------------------------

func test_props_contract() -> void:
	var shared: Dictionary = {}   # material instance id -> number of props using it
	var build_us: int = 0
	for id: StringName in PROPS:
		var path: String = ScenePaths.prop(id)
		var t0: int = Time.get_ticks_usec()
		var root: Node3D = _spawn(path)
		build_us += Time.get_ticks_usec() - t0
		if root == null:
			continue
		var spec: Array = PROPS[id]
		_forbidden(root, "prop/%s" % id)
		var meshes: Array[MeshInstance3D] = _meshes(root)
		var tris: int = _tree_tris(root)
		ok(tris <= int(spec[3]), "%s: %d triangulos (<= %d)" % [id, tris, int(spec[3])])
		ok(meshes.size() <= PROP_MAX_MESHES, "%s: %d MeshInstance3D (<= %d)" % [id, meshes.size(), PROP_MAX_MESHES])
		for m_id: int in _unique_materials(meshes):
			shared[m_id] = int(shared.get(m_id, 0)) + 1
		var box: AABB = _aabb_in_root(root)
		var want: Vector3 = Vector3(float(spec[0]), float(spec[1]), float(spec[2]))
		# Height counts only what is above the ground (buried post ends do not count): max.y, not size.y.
		var measured: Vector3 = Vector3(box.size.x, box.end.y, box.size.z)
		print("INFO prop %s: tris=%d malhas=%d AABB size=%s (altura acima do chao %.3f) pos=%s esperado=%s" % [id, tris, meshes.size(), box.size, box.end.y, box.position, want])
		for axis: int in 3:
			var allowed: float = want[axis] * PROP_SIZE_TOLERANCE + PROP_SIZE_SLACK_M
			ok(absf(measured[axis] - want[axis]) <= allowed, "%s: dimensao %s = %.3f, esperado %.2f +- %.3f" % [id, "XYZ"[axis], measured[axis], want[axis], allowed])
		ok(box.position.y >= -PROP_MAX_BURIAL_M - PROP_BURIAL_EPS_M and box.position.y <= 0.1, "%s: base no chao, enterrada ate %.2f m (y min %.3f)" % [id, PROP_MAX_BURIAL_M, box.position.y])
		ok(absf(box.get_center().x) <= want.x * 0.1 + 0.1 and absf(box.get_center().z) <= want.z * 0.1 + 0.1, "%s: centrado na pegada (centro %s)" % [id, box.get_center()])
	# Materials are shared between props (not one private set per prop).
	var shared_count: int = 0
	for m_id: int in shared:
		if int(shared[m_id]) > 1:
			shared_count += 1
	print("INFO props: %d materiais distintos, %d compartilhados entre props" % [shared.size(), shared_count])
	ok(shared_count >= 1, "materiais compartilhados entre props (%d de %d)" % [shared_count, shared.size()])
	var build_ms: float = float(build_us) / 1000.0
	print("INFO props: montagem somada dos %d props = %.1f ms (meta <= %.0f ms, so informativo; cache de materiais pode ja estar quente)" % [PROPS.size(), build_ms, PROP_BUILD_BUDGET_MS])


## Corn stock of the barn (docs/horda.md section 11.1): budget, geometry and API. The stage checks run off-tree,
## where the asset applies a stage instantly (the tween only exists inside the tree).
## Volume of the visible corn meshes. The fixed wooden bin ("Bin") is not corn: it is always there.
func _visible_volume(root: Node3D) -> float:
	var total: float = 0.0
	for mi: MeshInstance3D in _meshes(root):
		if mi.name == &"Bin":
			continue
		if mi.visible and mi.mesh != null:
			var b: AABB = mi.transform * mi.get_aabb()
			total += b.size.x * b.size.y * b.size.z
	return total


func _visible_meshes(root: Node3D) -> int:
	var n: int = 0
	for mi: MeshInstance3D in _meshes(root):
		if mi.name == &"Bin":
			continue
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
	ok(meshes.size() <= BARN_CORN_MAX_MESHES, "%d MeshInstance3D (<= %d)" % [meshes.size(), BARN_CORN_MAX_MESHES])
	ok(tris <= BARN_CORN_MAX_TRIS, "%d triangulos (<= %d)" % [tris, BARN_CORN_MAX_TRIS])
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
	ok(shadow_casters <= 2, "so a tulha e o monte de dentro projetam sombra (%d)" % shadow_casters)
	for mi: MeshInstance3D in meshes:
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			ok(mi.name == &"Bin" or mi.name == &"InnerPile", "%s projeta sombra (so Bin e InnerPile podem)" % mi.name)
	# the wooden bin (docs/plano_horda_nivel2.md section 7): fixed in the barn frame, walls 1.2 m, always visible
	var bin_node: MeshInstance3D = stock.get_node_or_null("Bin") as MeshInstance3D
	ok(bin_node != null and bin_node.mesh != null, "a tulha de madeira existe (no Bin)")
	if bin_node != null and bin_node.mesh != null:
		var bb: AABB = bin_node.transform * bin_node.get_aabb()
		ok(bb.position.x >= BIN_RECT.position.x - 0.05 and bb.end.x <= BIN_RECT.end.x + 0.05, "tulha em x [-6, 6] (%.2f a %.2f)" % [bb.position.x, bb.end.x])
		ok(bb.position.z >= BIN_RECT.position.y - 0.05 and bb.end.z <= BIN_RECT.end.y + 0.05, "tulha em z [1,6, 4,7] (%.2f a %.2f)" % [bb.position.z, bb.end.z])
		ok(bb.size.x >= 11.0 and bb.size.z >= 2.9, "a tulha ocupa a pegada toda (%.1f x %.1f)" % [bb.size.x, bb.size.z])
		ok(bb.end.y <= BIN_WALL_H + 0.3 and bb.end.y >= BIN_WALL_H - 0.1, "parede de ~1,2 m, esteios um pouco acima (%.2f)" % bb.end.y)
		ok(bb.position.y >= -0.05, "a tulha nao afunda no chao (%.2f)" % bb.position.y)
		for pct: float in [100.0, 60.0, 30.0, 10.0, 0.0]:
			stock.set_stock_pct(pct)
			ok(bin_node.visible, "a tulha aparece a %d%% (0 = tulha vazia com palha)" % int(pct))
		stock.set_stock_pct(100.0)
	# stages 4..1 only lower the corn (fixed footprint): same x/z extent of the inner pile, shrinking height
	var pile_node: MeshInstance3D = stock.get_node_or_null("InnerPile") as MeshInstance3D
	if pile_node != null and pile_node.mesh != null:
		var widths: Array[float] = []
		var heights: Array[float] = []
		for pct: float in [100.0, 60.0, 30.0, 10.0]:
			stock.set_stock_pct(pct)
			var pb: AABB = pile_node.transform * pile_node.get_aabb()
			widths.append(pb.size.x)
			widths.append(pb.size.z)
			heights.append(pb.size.y)
		for i: int in range(2, widths.size()):
			near(widths[i], widths[i % 2], 0.01, "estagio %d: pegada do milho igual a do cheio (%.2f)" % [4 - i / 2, widths[i]])
		for i: int in range(1, heights.size()):
			ok(heights[i] < heights[i - 1], "a altura do milho cai a cada estagio (%.2f -> %.2f)" % [heights[i - 1], heights[i]])
		stock.set_stock_pct(100.0)
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
	eq(_visible_meshes(stock), 7, "cheio: monte de dentro + 6 de fora visiveis (a tulha e fixa e fica de fora da conta)")
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


func test_ammo_crate_contract() -> void:
	## docs/plano_horda_nivel2.md section 7: Node3D root, no physics, no light, ~0.6 x 0.35 x 0.4 m, <= 300 tris,
	## one MeshInstance3D, one material, shadow off, origin on the ground at the centre.
	var scene: PackedScene = need_scene(ScenePaths.AMMO_CRATE)
	if scene == null:
		return
	var root: Node3D = scene.instantiate() as Node3D
	if root == null:
		fail("%s: raiz nao e Node3D" % ScenePaths.AMMO_CRATE)
		return
	track(root)
	await frames(2)   # the mesh is built in _ready
	_forbidden(root, "ammo_crate")
	var meshes: Array[MeshInstance3D] = _meshes(root)
	var tris: int = _tree_tris(root)
	print("INFO ammo_crate: %d MeshInstance3D, %d triangulos" % [meshes.size(), tris])
	eq(meshes.size(), 1, "1 MeshInstance3D")
	ok(tris > 0 and tris <= AMMO_CRATE_MAX_TRIS, "%d triangulos (1..%d)" % [tris, AMMO_CRATE_MAX_TRIS])
	var materials: Dictionary = {}
	for mi: MeshInstance3D in meshes:
		eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cast_shadow desligado")
		if mi.mesh != null:
			for si: int in mi.mesh.get_surface_count():
				var m: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(si)
				if m != null:
					materials[m.get_instance_id()] = true
	eq(materials.size(), 1, "1 material")
	var box: AABB = _aabb_in_root(root)
	ok(box.size.x >= 0.5 and box.size.x <= 0.75, "largura ~0,6 m (%.2f)" % box.size.x)
	ok(box.size.z >= 0.3 and box.size.z <= 0.5, "profundidade ~0,4 m (%.2f)" % box.size.z)
	ok(box.size.y >= 0.2 and box.size.y <= 0.5, "altura ~0,35 m (%.2f)" % box.size.y)
	ok(absf(box.position.y) <= 0.02, "origem no chao (y min %.3f)" % box.position.y)
	ok(absf(box.get_center().x) <= 0.05 and absf(box.get_center().z) <= 0.05, "origem no centro (%.2f, %.2f)" % [box.get_center().x, box.get_center().z])
	# the asset loader finds it (the HuntController uses AssetLoader.instantiate with a FallbackMeshes fallback)
	var via_loader: Node = AssetLoader.instantiate(ScenePaths.AMMO_CRATE)
	ok(via_loader != null, "AssetLoader.instantiate(AMMO_CRATE)")
	if via_loader != null:
		track(via_loader)
	# the mesh is shared: two crates, one mesh resource
	var other: Node3D = scene.instantiate() as Node3D
	track(other)
	await frames(2)
	var m1: Array[MeshInstance3D] = _meshes(root)
	var m2: Array[MeshInstance3D] = _meshes(other)
	if m1.size() == 1 and m2.size() == 1:
		ok(m1[0].mesh == m2[0].mesh, "a malha e construida uma vez e compartilhada")


func test_horde_level2_sounds_exist_and_play() -> void:
	## docs/plano_horda_nivel2.md section 7: ammo_pickup (~0.4 s) and revive_done (~0.8 s), procedural, has_sound true.
	for id: StringName in [&"ammo_pickup", &"revive_done"]:
		ok(Sfx.has_sound(id), "Sfx.has_sound(%s)" % id)
	var mark: int = error_mark()
	Sfx.play(&"ammo_pickup")
	Sfx.play(&"revive_done")
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar os sons do nivel 2 nao gera erros: %s" % str(errors_since(mark)))
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	for pair: Array in [[&"ammo_pickup", 0.2, 1.0], [&"revive_done", 0.4, 1.6]]:
		var id: StringName = pair[0]
		ok(fb.call(&"has_sound", id), "fallback: has_sound(%s)" % id)
		var stream: AudioStreamWAV = fb.call(&"_get_stream", id) as AudioStreamWAV
		ok(stream != null, "fallback: %s sintetizado" % id)
		if stream != null:
			var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
			var channels: float = 2.0 if stream.stereo else 1.0
			var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
			ok(seconds >= float(pair[1]) and seconds <= float(pair[2]), "%s dura %.2f s (esperado %.1f a %.1f)" % [id, seconds, float(pair[1]), float(pair[2])])
	# the prompts file lists both ids (the MP3 may come later)
	var prompts_text: String = FileAccess.get_file_as_string("res://assets/audio/sfx_prompts.json")
	for id: String in ["ammo_pickup", "revive_done"]:
		ok(prompts_text.contains("\"id\": \"%s\"" % id), "sfx_prompts.json tem a entrada %s" % id)
	await frames(2)


func test_stamina_sound_exists_and_plays() -> void:
	## docs/plano_faca_mochila_folego.md section 5 (ART2): breath_tired (~0.9 s), synthesized on demand (SynthWeapons.LAZY_IDS).
	ok(Sfx.has_sound(&"breath_tired"), "Sfx.has_sound(breath_tired)")
	ok(SynthWeapons.LAZY_IDS.has(&"breath_tired"), "breath_tired esta em SynthWeapons.LAZY_IDS")
	var mark: int = error_mark()
	Sfx.play(&"breath_tired")
	Sfx.play_3d(&"breath_tired", Vector3(1.0, 1.0, 1.0))
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar breath_tired nao gera erros: %s" % str(errors_since(mark)))
	# no recorded file: the synthesis fallback produces it, about 0.9 s long
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	ok(fb.call(&"has_sound", &"breath_tired"), "fallback: has_sound(breath_tired)")
	var stream: AudioStreamWAV = fb.call(&"_get_stream", &"breath_tired") as AudioStreamWAV
	ok(stream != null, "fallback: breath_tired sintetizado")
	if stream != null:
		var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
		var channels: float = 2.0 if stream.stereo else 1.0
		var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
		ok(seconds >= 0.6 and seconds <= 1.3, "breath_tired dura %.2f s (esperado ~0,9 s)" % seconds)
		ok(not stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "breath_tired nao e loop")
		var peak: int = 0
		if stream.format == AudioStreamWAV.FORMAT_16_BITS:
			var i: int = 0
			while i + 1 < stream.data.size():
				var v: int = stream.data.decode_s16(i)
				peak = maxi(peak, absi(v))
				i += 2 * 16   # every 16th sample is enough to tell silence from sound
		ok(stream.format != AudioStreamWAV.FORMAT_16_BITS or peak > 500, "breath_tired nao e silencio (pico %d)" % peak)
	var live: Variant = (Sfx.get(&"_streams") as Dictionary).get(&"breath_tired")
	ok(live is AudioStreamWAV or live is AudioStreamMP3, "breath_tired no Sfx: WAV sintetizado ou MP3 gravado")
	# the prompts file lists it (the MP3 may come later)
	var prompts_text: String = FileAccess.get_file_as_string("res://assets/audio/sfx_prompts.json")
	ok(prompts_text.contains("\"id\": \"breath_tired\""), "sfx_prompts.json tem a entrada breath_tired")
	var parsed: Variant = JSON.parse_string(prompts_text)
	ok(parsed != null, "sfx_prompts.json continua JSON valido")
	await frames(2)


func test_energy_drink_icon_and_sound_exist() -> void:
	## docs/plano_faca_mochila_folego.md section 5 (ART3): icon `energy_drink` (SVG) and the sound `energy_drink` (~0.8 s),
	## synthesized on demand (SynthWeapons.LAZY_IDS), no MP3 needed.
	var icon_path: String = ScenePaths.icon(&"energy_drink")
	ok(FileAccess.file_exists(icon_path), "icone %s existe" % icon_path)
	ok(load(icon_path) is Texture2D, "o icone carrega como Texture2D")
	ok(UiKit.icon(&"energy_drink") != null, "UiKit.icon(energy_drink) nao e nulo")
	ok(UiKit.icon_rect(&"energy_drink", 48.0) != null, "UiKit.icon_rect(energy_drink) nao e nulo")
	ok(Sfx.has_sound(&"energy_drink"), "Sfx.has_sound(energy_drink)")
	ok(SynthWeapons.LAZY_IDS.has(&"energy_drink"), "energy_drink esta em SynthWeapons.LAZY_IDS")
	var mark: int = error_mark()
	Sfx.play(&"energy_drink")
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar energy_drink nao gera erros: %s" % str(errors_since(mark)))
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	ok(fb.call(&"has_sound", &"energy_drink"), "fallback: has_sound(energy_drink)")
	var stream: AudioStreamWAV = fb.call(&"_get_stream", &"energy_drink") as AudioStreamWAV
	ok(stream != null, "fallback: energy_drink sintetizado")
	if stream != null:
		var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
		var channels: float = 2.0 if stream.stereo else 1.0
		var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
		ok(seconds >= 0.5 and seconds <= 1.2, "energy_drink dura %.2f s (esperado ~0,8 s)" % seconds)
		ok(stream.loop_mode != AudioStreamWAV.LOOP_FORWARD, "energy_drink nao e loop")
		var peak: int = 0
		if stream.format == AudioStreamWAV.FORMAT_16_BITS:
			var i: int = 0
			while i + 1 < stream.data.size():
				peak = maxi(peak, absi(stream.data.decode_s16(i)))
				i += 2 * 16
		ok(stream.format != AudioStreamWAV.FORMAT_16_BITS or peak > 500, "energy_drink nao e silencio (pico %d)" % peak)
	var live: Variant = (Sfx.get(&"_streams") as Dictionary).get(&"energy_drink")
	ok(live is AudioStreamWAV or live is AudioStreamMP3, "energy_drink no Sfx: WAV sintetizado ou MP3 gravado")
	var prompts_text: String = FileAccess.get_file_as_string("res://assets/audio/sfx_prompts.json")
	ok(prompts_text.contains("\"id\": \"energy_drink\""), "sfx_prompts.json tem a entrada energy_drink")
	ok(JSON.parse_string(prompts_text) != null, "sfx_prompts.json continua JSON valido")
	await frames(2)


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


func test_boss_roar_sound_exists_and_plays() -> void:
	## docs/plano_horda_boss.md section 4.4: boar_boss_roar, procedural (SynthWorld.LAZY_IDS, no recorded file yet),
	## played once by Boar.start() / BoarPuppet._ready() when the type is boss.
	ok(SynthWorld.LAZY_IDS.has(&"boar_boss_roar"), "boar_boss_roar e sintetizado sob demanda (LAZY_IDS)")
	ok(Sfx.has_sound(&"boar_boss_roar"), "Sfx.has_sound(boar_boss_roar)")
	var mark: int = error_mark()
	Sfx.play_3d(&"boar_boss_roar", Vector3(2.0, 1.0, -4.0), 3.0, 0.9)
	await frames(3)
	eq(errors_since(mark).size(), 0, "tocar o rugido do chefao nao gera erros: %s" % str(errors_since(mark)))
	var live: Variant = (Sfx.get(&"_streams") as Dictionary).get(&"boar_boss_roar")
	ok(live is AudioStreamWAV or live is AudioStreamMP3, "boar_boss_roar no Sfx: WAV sintetizado ou MP3 gravado")
	var fb: Node = load("res://assets/audio/sfx_library.gd").new()
	fb.set(&"sfx_dir", "res://assets/audio/_sem_arquivos/")
	track(fb)
	ok(fb.call(&"has_sound", &"boar_boss_roar"), "fallback: has_sound(boar_boss_roar)")
	var stream: AudioStreamWAV = fb.call(&"_get_stream", &"boar_boss_roar") as AudioStreamWAV
	ok(stream != null, "fallback: boar_boss_roar sintetizado")
	if stream != null:
		var bytes_per_sample: float = 2.0 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1.0
		var channels: float = 2.0 if stream.stereo else 1.0
		var seconds: float = float(stream.data.size()) / float(maxi(stream.mix_rate, 1)) / bytes_per_sample / channels
		ok(seconds > 0.3 and seconds < 4.0, "o rugido dura %.2f s" % seconds)
		ok(stream.loop_mode != AudioStreamWAV.LOOP_FORWARD, "o rugido nao e loop")
		var peak: int = 0
		if stream.format == AudioStreamWAV.FORMAT_16_BITS:
			var i: int = 0
			while i + 1 < stream.data.size():
				peak = maxi(peak, absi(stream.data.decode_s16(i)))
				i += 2 * 16
		ok(stream.format != AudioStreamWAV.FORMAT_16_BITS or peak > 500, "o rugido nao e silencio (pico %d)" % peak)
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
	var tris_by_id: Dictionary = {}
	var t_start: int = Time.get_ticks_usec()
	for id: StringName in FLORA:
		var t_id: int = Time.get_ticks_usec()
		var mesh: Mesh = lib.call(&"build_mesh", id) as Mesh
		var ms_id: float = float(Time.get_ticks_usec() - t_id) / 1000.0
		ok(mesh != null, "build_mesh(%s) != null" % id)
		if mesh == null:
			continue
		print("INFO flora %-14s tris=%4d (<= %4d)  y_min=%.3f  y_max=%.2f  build=%.1f ms" % [id, _tris(mesh), int(FLORA[id]),
			mesh.get_aabb().position.y, mesh.get_aabb().end.y, ms_id])
		ok(mesh.get_surface_count() >= 1, "%s: tem superficie" % id)
		for s: int in mesh.get_surface_count():
			ok(mesh.surface_get_material(s) != null, "%s: superficie %d com material" % [id, s])
		var tris: int = _tris(mesh)
		ok(tris <= int(FLORA[id]), "%s: %d triangulos (<= %d)" % [id, tris, int(FLORA[id])])
		ok(tris > 0, "%s: nao vazio" % id)
		tris_by_id[id] = tris
		var box: AABB = mesh.get_aabb()
		# contract 7.5: the base may sink up to 0.15 m below y = 0 (termite mound, tree roots)
		ok(box.position.y >= -FLORA_BASE_SINK_M, "%s: base na origem (y min %.3f, >= -%.2f)" % [id, box.position.y, FLORA_BASE_SINK_M])
		ok(lib.call(&"build_mesh", id) == mesh, "%s: cache devolve a mesma malha" % id)
	# INFO only: first-build time of the whole library (cache may already be warm if another test built meshes)
	print("INFO flora: build_mesh de todos os ids em %.1f ms (limite informativo %.0f ms)" % [
		float(Time.get_ticks_usec() - t_start) / 1000.0, FLORA_BUILD_INFO_MS])
	_check_tree_budget(tris_by_id)
	var heights: Dictionary = {&"grass_tuft": 0.4, &"shrub": 1.0, &"cerrado_tree": 4.5, &"ipe": 7.0, &"buriti": 12.0,
		&"termite_mound": 1.2, &"soy_patch": 0.6, &"soy_eaten": 0.15, &"corn_patch": 2.0, &"corn_eaten": 0.5}
	for id: StringName in heights:
		var m: Mesh = lib.call(&"build_mesh", id) as Mesh
		if m != null:
			var h: float = m.get_aabb().end.y
			ok(absf(h - float(heights[id])) <= float(heights[id]) * 0.35 + 0.1, "%s: altura %.2f perto de %.2f" % [id, h, float(heights[id])])
	ok(lib.call(&"build_mesh", &"id_inexistente") == null, "id desconhecido devolve null")
	ok(lib.call(&"build_mesh", &"") == null, "id vazio devolve null")


## Sum of tree triangles over the whole map. Counts the nominal instances of the map scene (base_flora plus
## every FloraZone), without building the world: trees do not scale with flora_density, and placement
## rejections (water, crops, props) can only remove instances, so this is an upper bound of what is drawn.
func _check_tree_budget(tris_by_id: Dictionary) -> void:
	var scene: PackedScene = need_scene(ScenePaths.map_scene(FLORA_MAP_ID))
	if scene == null:
		return
	var map: Node = scene.instantiate()   # not added to the tree: no _ready, only the exported properties
	if map == null:
		fail("mapa %s nao instancia" % FLORA_MAP_ID)
		return
	var counts: Dictionary = {}
	var base: Variant = map.get(&"base_flora")
	if base is Dictionary:
		for key: Variant in (base as Dictionary).keys():
			counts[String(key)] = int(counts.get(String(key), 0)) + int((base as Dictionary)[key])
	var zones: Node = map.get_node_or_null(^"FloraZones")
	if zones != null:
		for z: Node in zones.get_children():
			var zc: Variant = z.get(&"counts")
			if zc is Dictionary:
				for key: Variant in (zc as Dictionary).keys():
					counts[String(key)] = int(counts.get(String(key), 0)) + int((zc as Dictionary)[key])
	map.free()
	var total: int = 0
	var parts: PackedStringArray = PackedStringArray()
	for id: StringName in FLORA_TREE_IDS:
		var n: int = int(counts.get(String(id), 0))
		var t: int = int(tris_by_id.get(id, 0))
		total += n * t
		parts.append("%d %s x %d" % [n, id, t])
	print("INFO flora: triangulos de arvores no mapa %s = %d (<= %d); %s" % [FLORA_MAP_ID, total, FLORA_TREE_TRIS_MAX, ", ".join(parts)])
	ok(total > 0, "mapa %s tem arvores" % FLORA_MAP_ID)
	ok(total <= FLORA_TREE_TRIS_MAX, "arvores do mapa: %d triangulos (<= %d)" % [total, FLORA_TREE_TRIS_MAX])


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
	# Upgrades (backpack, later knife) are not items, but their shop cards use the icon of the same id
	# (docs/plano_faca_mochila_folego.md 2.9 and 2.10).
	for id: StringName in Data.get_upgrade_ids():
		ids.append(String(id))
	ok(ids.has("backpack"), "backpack esta entre os icones exigidos")
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
