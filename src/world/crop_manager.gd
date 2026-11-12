class_name CropManager
extends Node3D
## Crop health (100 -> 0) and the visible plants. Each 2x2 m patch is one MultiMesh instance.
## Eaters (boars) drain health; every (100 / patch_count)% drained turns the patch nearest to
## the eater from "healthy" into "eaten" (see _eat_patch).
## 2 MultiMeshes per 32x32 m block. Emits crop_health_changed / crop_under_attack.

const PATCH_M: float = 2.0
const BLOCK_M: float = 32.0
const VISIBILITY_END_M: float = 110.0
const SEARCH_RINGS: int = 8
const JITTER_M: float = 0.25
const SCALE_JITTER: float = 0.15
const DEFAULT_SIGNAL_STEP_PCT: float = 0.5

var _hm: Heightmap
var _health_pct: float = 100.0
var _last_sent_pct: float = 100.0
var _step_pct: float = DEFAULT_SIGNAL_STEP_PCT
var _frozen: bool = false
var _zero_sent: bool = false
var _under_attack: bool = false

var _rects: Array[Rect2] = []
var _fields: Array[Dictionary] = []   # {rect, cols, rows, first}
var _patch_total: int = 0
var _patch_eaten: PackedByteArray = PackedByteArray()
var _patch_block: PackedInt32Array = PackedInt32Array()     # index into _blocks
var _patch_slot: PackedInt32Array = PackedInt32Array()      # healthy instance index inside the block
var _slot_patch: PackedInt32Array = PackedInt32Array()      # (block first + healthy slot) -> patch
var _block_first: PackedInt32Array = PackedInt32Array()     # block -> first index in _slot_patch
var _block_healthy_n: PackedInt32Array = PackedInt32Array() # block -> healthy instances drawn
var _block_eaten_n: PackedInt32Array = PackedInt32Array()   # block -> eaten instances drawn
var _patch_xf: Array[Transform3D] = []
var _blocks: Array[Dictionary] = []   # {healthy: MultiMesh, eaten: MultiMesh, eaten_node: MultiMeshInstance3D}
var _eaten_count: int = 0

var _eater_drain: Dictionary = {}   # boar_id -> pct per second
var _eater_pos: Dictionary = {}     # boar_id -> Vector2
var _eater_accum: Dictionary = {}   # boar_id -> pct drained not yet turned into a patch
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## mesh_getter: Callable(id: StringName) -> Mesh.
func setup(hm: Heightmap, fields: Array[CropField], rng: RandomNumberGenerator, mesh_getter: Callable) -> void:
	_hm = hm
	_rng = rng
	_step_pct = float(Data.get_game().get("hunt", {}).get("crop_health_signal_step_pct", DEFAULT_SIGNAL_STEP_PCT))
	for f: CropField in fields:
		_rects.append(f.get_rect())
		_build_field(f, mesh_getter)
	_patch_eaten.resize(_patch_total)


func get_rects() -> Array[Rect2]:
	return _rects


func get_health_pct() -> float:
	return _health_pct


func get_patch_total() -> int:
	return _patch_total


func get_patch_eaten() -> int:
	return _eaten_count


func get_eater_count() -> int:
	return _eater_drain.size()


func has_eater(boar_id: int) -> bool:
	return _eater_drain.has(boar_id)


func is_frozen() -> bool:
	return _frozen


## Stops the drain (hunt over). Eaters are kept so the picture stays as it was.
func freeze() -> void:
	_frozen = true


func register_eater(boar_id: int, drain_pct_per_s: float, pos: Vector2) -> void:
	_eater_drain[boar_id] = drain_pct_per_s
	_eater_pos[boar_id] = pos
	if not _eater_accum.has(boar_id):
		_eater_accum[boar_id] = 0.0
	_update_attack_flag()


func unregister_eater(boar_id: int) -> void:
	if _eater_drain.erase(boar_id):
		_eater_pos.erase(boar_id)
		_update_attack_flag()


## Debug / tests: forces the health value and syncs the visible patches to it.
func set_health(pct: float) -> void:
	_health_pct = clampf(pct, 0.0, 100.0)
	var target_eaten: int = int(round((100.0 - _health_pct) / 100.0 * float(_patch_total)))
	var guard: int = _patch_total * 2
	while _eaten_count < target_eaten and guard > 0:
		guard -= 1
		var p: int = _rng.randi_range(0, maxi(_patch_total - 1, 0))
		if _patch_eaten[p] == 0:
			_eat_patch(p)
	_emit_health(true)


func _process(delta: float) -> void:
	if _frozen or _health_pct <= 0.0 or _eater_drain.is_empty():
		return
	var quantum: float = 100.0 / float(maxi(_patch_total, 1))
	for id: int in _eater_drain.keys():
		var amount: float = float(_eater_drain[id]) * delta
		_health_pct = maxf(_health_pct - amount, 0.0)
		var acc: float = float(_eater_accum.get(id, 0.0)) + amount
		while acc >= quantum:
			acc -= quantum
			_eat_near(_eater_pos[id] as Vector2)
		_eater_accum[id] = acc
	_emit_health(false)


func _emit_health(force: bool) -> void:
	if _health_pct <= 0.0:
		if not _zero_sent:
			_zero_sent = true
			_last_sent_pct = 0.0
			GameEvents.crop_health_changed.emit(0.0)
		return
	_zero_sent = false
	if force or absf(_last_sent_pct - _health_pct) >= _step_pct:
		_last_sent_pct = _health_pct
		GameEvents.crop_health_changed.emit(_health_pct)


func _update_attack_flag() -> void:
	var now: bool = not _eater_drain.is_empty()
	if now != _under_attack:
		_under_attack = now
		GameEvents.crop_under_attack.emit(now)


func _build_field(field: CropField, mesh_getter: Callable) -> void:
	var rect: Rect2 = field.get_rect()
	var cols: int = maxi(int(rect.size.x / PATCH_M), 1)
	var rows: int = maxi(int(rect.size.y / PATCH_M), 1)
	var first: int = _patch_total
	_fields.append({"rect": rect, "cols": cols, "rows": rows, "first": first})
	var healthy_mesh: Mesh = mesh_getter.call(StringName(String(field.crop) + "_patch")) as Mesh
	var eaten_mesh: Mesh = mesh_getter.call(StringName(String(field.crop) + "_eaten")) as Mesh
	var base_block: int = _blocks.size()
	var local_of: Dictionary = {}   # Vector2i -> local block index
	var block_lists: Array[Array] = []
	for r: int in rows:
		for c: int in cols:
			var x: float = rect.position.x + (float(c) + 0.5) * PATCH_M + _rng.randf_range(-JITTER_M, JITTER_M)
			var z: float = rect.position.y + (float(r) + 0.5) * PATCH_M + _rng.randf_range(-JITTER_M, JITTER_M)
			var s: float = 1.0 + _rng.randf_range(-SCALE_JITTER, SCALE_JITTER)
			var xf: Transform3D = Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)),
				Vector3(x, _hm.get_height(x, z), z))
			var key: Vector2i = Vector2i(int(float(c) * PATCH_M / BLOCK_M), int(float(r) * PATCH_M / BLOCK_M))
			if not local_of.has(key):
				local_of[key] = block_lists.size()
				block_lists.append([])
			var li: int = int(local_of[key])
			var list: Array = block_lists[li]
			_patch_block.append(base_block + li)
			_patch_slot.append(list.size())
			list.append(xf)
			_patch_xf.append(xf)
			_patch_total += 1
	for k: int in block_lists.size():
		var list: Array = block_lists[k]
		var healthy: MultiMesh = _make_mm(healthy_mesh, list.size())
		var eaten: MultiMesh = _make_mm(eaten_mesh, list.size())
		for i: int in list.size():
			healthy.set_instance_transform(i, list[i] as Transform3D)
			eaten.set_instance_transform(i, list[i] as Transform3D)   # keeps the AABB on the block
		eaten.visible_instance_count = 0
		_add_instance(healthy, "Healthy")
		var eaten_node: MultiMeshInstance3D = _add_instance(eaten, "Eaten")
		eaten_node.visible = false
		_blocks.append({"healthy": healthy, "eaten": eaten, "eaten_node": eaten_node})
		_block_first.append(_slot_patch.size())
		_slot_patch.resize(_slot_patch.size() + list.size())
		_block_healthy_n.append(list.size())
		_block_eaten_n.append(0)
	for p: int in range(first, _patch_total):
		_slot_patch[_block_first[_patch_block[p]] + _patch_slot[p]] = p


func _make_mm(mesh: Mesh, count: int) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _add_instance(mm: MultiMesh, label: String) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "%s_%d" % [label, _blocks.size()]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = VISIBILITY_END_M
	add_child(mmi)
	return mmi


## Only live instances are drawn: healthy patches stay packed at the front of their MultiMesh and
## eaten ones are appended to the other, so no degenerate (zero-scale) triangles are submitted.
func _eat_patch(p: int) -> void:
	if _patch_eaten[p] != 0:
		return
	_patch_eaten[p] = 1
	_eaten_count += 1
	var b: int = _patch_block[p]
	var block: Dictionary = _blocks[b]
	var healthy: MultiMesh = block["healthy"] as MultiMesh
	var eaten: MultiMesh = block["eaten"] as MultiMesh
	# Healthy: move the last drawn instance into the freed slot and draw one less.
	var first: int = _block_first[b]
	var slot: int = _patch_slot[p]
	var last: int = _block_healthy_n[b] - 1
	if slot != last:
		var moved: int = _slot_patch[first + last]
		healthy.set_instance_transform(slot, _patch_xf[moved])
		_slot_patch[first + slot] = moved
		_patch_slot[moved] = slot
	_block_healthy_n[b] = last
	healthy.visible_instance_count = last
	# Eaten: append.
	var n: int = _block_eaten_n[b]
	eaten.set_instance_transform(n, _patch_xf[p])
	_block_eaten_n[b] = n + 1
	eaten.visible_instance_count = n + 1
	(block["eaten_node"] as MultiMeshInstance3D).visible = true


## Turns the uneaten patch nearest to pos (XZ) into an eaten one.
func _eat_near(pos: Vector2) -> void:
	if _eaten_count >= _patch_total:
		return
	var best_field: int = -1
	var best_d: float = INF
	for k: int in _fields.size():
		var rect: Rect2 = _fields[k]["rect"] as Rect2
		var dx: float = maxf(maxf(rect.position.x - pos.x, pos.x - rect.end.x), 0.0)
		var dz: float = maxf(maxf(rect.position.y - pos.y, pos.y - rect.end.y), 0.0)
		var d: float = dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best_field = k
	if best_field < 0:
		return
	var f: Dictionary = _fields[best_field]
	var rect2: Rect2 = f["rect"] as Rect2
	var cols: int = int(f["cols"])
	var rows: int = int(f["rows"])
	var first: int = int(f["first"])
	var cx: int = clampi(int((pos.x - rect2.position.x) / PATCH_M), 0, cols - 1)
	var cz: int = clampi(int((pos.y - rect2.position.y) / PATCH_M), 0, rows - 1)
	for ring: int in range(0, SEARCH_RINGS + 1):
		for dz2: int in range(-ring, ring + 1):
			for dx2: int in range(-ring, ring + 1):
				if maxi(absi(dx2), absi(dz2)) != ring:
					continue
				var x: int = cx + dx2
				var z: int = cz + dz2
				if x < 0 or z < 0 or x >= cols or z >= rows:
					continue
				var p: int = first + z * cols + x
				if _patch_eaten[p] == 0:
					_eat_patch(p)
					return
	# Nothing near: take any uneaten patch of this field.
	for p2: int in range(first, first + cols * rows):
		if _patch_eaten[p2] == 0:
			_eat_patch(p2)
			return
