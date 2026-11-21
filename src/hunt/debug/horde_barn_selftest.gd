extends Node
## Self-test of the open barn in the horde (both levels): runs hunt.tscn headless offline.
##   eat   levels 1 and 2: every eat point (boar ids 0..NetCodec.MAX_BOARS_PER_HUNT - 1) lies outside the heaps of the
##         corn stock (CornStockVisualBase.get_heap_circles), and over the first waves no boar in `eat` ever has its
##         centre inside a heap (heap radius + its own body radius) or inside the grain bin of the barn
##   dog   level 2, the dog of the hunter: placed inside the barn with the hunter behind it (and beside it), it gets
##         out by the open front and comes back to the hunter; placed behind the barn with the hunter inside, it
##         goes round and in
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/horde_barn_selftest.tscn [-- --only=dog]
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 900.0
const BARN_XZ: Vector2 = Vector2(38.0, -88.0)
const BIN_LOCAL: Rect2 = Rect2(-6.0, 1.6, 12.0, 3.1)    # grain bin, barn frame (barn_corn.gd BIN_*)
const SAFE_XZ: Vector2 = Vector2(-15.0, -105.0)          # far corner of the farm, away from the boars' ways
const EAT_WAVES: int = 3
const ARRIVE_LIMIT_S: float = 90.0
const EAT_WATCH_S: float = 4.0
const STOCK_RESET_BELOW: float = 40.0
const DOG_ID: StringName = &"caramelo"
const DOG_LIMIT_S: float = 10.0
const DOG_NEAR_M: float = 6.0
## Dog scenarios: [name, dog start (barn frame), hunter (barn frame), hunter yaw]. Yaw 0 = facing -Z.
const DOG_CASES: Array = [
	["inside_hunter_behind", Vector2(3.0, -2.0), Vector2(0.0, 11.0), PI],
	["inside_hunter_beside", Vector2(-4.0, -1.0), Vector2(12.0, 1.0), -PI * 0.5],
	["inside_back_corner_hunter_behind", Vector2(6.5, 0.5), Vector2(-3.0, 10.0), PI],
	["behind_hunter_inside", Vector2(2.0, 9.0), Vector2(0.0, -2.0), PI],
	["behind_hunter_inside_facing_out", Vector2(-2.0, 8.0), Vector2(-1.0, -3.0), 0.0],
]

var _passed: int = 0
var _failed: int = 0
var _hunt: HuntController = null
var _start_ms: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	if only.is_empty() or only.has("dog"):
		print("--- dog")
		await _test_dog()
	if only.is_empty() or only.has("eat"):
		for level: int in [1, 2]:
			print("--- eat level %d" % level)
			await _test_eat(level)
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: self-test timed out")
		print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed + 1])
		get_tree().quit(1)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


# --- Plumbing ------------------------------------------------------------------------------------

func _open(level: int, dog_id: StringName) -> void:
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, level)
	req.rng_seed = 3131
	req.quality = Ids.Q_LOW
	req.dog_id = dog_id
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	while not _hunt.is_world_ready():
		await get_tree().process_frame


func _close() -> void:
	if _hunt == null:
		return
	_hunt.queue_free()
	_hunt = null
	Router.set_pending_request(null)
	await get_tree().process_frame
	await get_tree().process_frame


func _place(xz: Vector2, yaw: float) -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_set_move(Vector2.ZERO, false)
	p.bot_teleport(Vector3(xz.x, _hunt.get_height(xz.x, xz.y) + 0.05, xz.y))
	p.rotation.y = yaw


## The barn's route rectangle (the obstacle with an exit) in world XZ.
func _barn_rect() -> Rect2:
	for o: Dictionary in _hunt.horde_route_obstacles:
		if (o.get("exit", Vector2.INF) as Vector2).is_finite():
			return o["rect"] as Rect2
	return Rect2()


## Heap circles of the stock visual in world XZ: (x, z, radius).
func _heaps() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var stock: CornStockVisualBase = _hunt.get_node_or_null(^"BarnCorn") as CornStockVisualBase
	if stock == null:
		return out
	for c: Vector3 in stock.get_heap_circles():
		var g: Vector3 = stock.global_transform * Vector3(c.x, 0.0, c.y)
		out.append(Vector3(g.x, g.z, c.z))
	return out


func _wave_ids(wave_index: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.wave == wave_index:
			out.append(id)
	return out


# --- eat -----------------------------------------------------------------------------------------

func _test_eat(level: int) -> void:
	await _open(level, &"")
	var tag: String = "l%d" % level
	var heaps: PackedVector3Array = _heaps()
	_check("%s_stock_has_heaps" % tag, heaps.size() >= CornStockVisualBase.FALLBACK_HEAPS, "%d" % heaps.size())
	# Pure: every eat point is off every heap.
	var bad_points: Array = []
	for id: int in NetCodec.MAX_BOARS_PER_HUNT:
		var p: Vector2 = _hunt.get_horde_eat_point(id)
		for h: Vector3 in heaps:
			if p.distance_to(Vector2(h.x, h.y)) < h.z:
				bad_points.append([id, snappedf(p.distance_to(Vector2(h.x, h.y)), 0.01)])
	_check("%s_eat_points_off_the_heaps" % tag, bad_points.is_empty(), "%d bad %s" % [bad_points.size(), str(bad_points.slice(0, 8))])
	_place(SAFE_XZ, 0.0)
	var bin: Rect2 = Rect2(BIN_LOCAL.position + BARN_XZ, BIN_LOCAL.size)
	var inside: Dictionary = {}          # boar_id -> [x, z, clearance] (first time seen inside, eating)
	var min_clear: float = INF
	var eaters_seen: Dictionary = {}
	var all_reached: bool = true
	for w: int in range(1, EAT_WAVES + 1):
		_hunt.debug_horde_start_next_wave()
		await get_tree().process_frame
		await get_tree().process_frame
		var total: int = _hunt.get_horde_wave_total()
		var t0: float = _hunt.get_elapsed_s()
		var reached: Dictionary = {}
		var watch_until: float = INF
		while _hunt.get_elapsed_s() < watch_until and _hunt.get_elapsed_s() - t0 < ARRIVE_LIMIT_S and not _hunt.is_hunt_over():
			for id: int in _wave_ids(w - 1):
				var b: Boar = _hunt.spawner.get_boar(id)
				if b.state != Ids.BS_EAT:
					continue
				reached[id] = true
				eaters_seen[id] = true
				var xz: Vector2 = b.get_xz()
				var body_r: float = Boar.BODY_RADIUS_M * b.body_scale
				for h: Vector3 in heaps:
					var clear: float = xz.distance_to(Vector2(h.x, h.y)) - h.z - body_r
					min_clear = minf(min_clear, clear)
					if clear < 0.0 and not inside.has(id):
						inside[id] = [b.type_id, snappedf(xz.x, 0.01), snappedf(xz.y, 0.01), snappedf(clear, 0.01)]
				if bin.has_point(xz) and not inside.has(id):
					inside[id] = [b.type_id, snappedf(xz.x, 0.01), snappedf(xz.y, 0.01), "bin"]
			if reached.size() >= total and watch_until == INF:
				watch_until = _hunt.get_elapsed_s() + EAT_WATCH_S
			if _hunt.get_crop_health_pct() < STOCK_RESET_BELOW:
				_hunt.debug_set_crop_health(100.0)
			await get_tree().process_frame
		all_reached = all_reached and reached.size() >= total
		print("trace %s wave %d: total=%d eating=%d t=%.1f" % [tag, w, total, reached.size(), _hunt.get_elapsed_s() - t0])
		for id: int in _wave_ids(w - 1):
			_hunt.debug_kill_boar(id)
		_hunt.debug_set_crop_health(100.0)
		await get_tree().process_frame
		await get_tree().process_frame
	_check("%s_every_boar_eats" % tag, all_reached and not eaters_seen.is_empty(), "eaters=%d" % eaters_seen.size())
	_check("%s_no_eating_boar_inside_the_stock" % tag, inside.is_empty(),
		"inside=%s min_clearance=%.2f m" % [str(inside), min_clear])
	await _close()


# --- dog -----------------------------------------------------------------------------------------

func _test_dog() -> void:
	for c: Array in DOG_CASES:
		await _open(2, DOG_ID)
		var case_name: String = c[0]
		var dog: Dog = _hunt.get_dog_of(_hunt.get_local_slot())
		if dog == null:
			_check("dog_%s" % case_name, false, "no dog")
			await _close()
			continue
		var hunter_xz: Vector2 = BARN_XZ + (c[2] as Vector2)
		_place(hunter_xz, float(c[3]))
		var start: Vector2 = BARN_XZ + (c[1] as Vector2)
		dog.position = Vector3(start.x, _hunt.get_height(start.x, start.y), start.y)
		await get_tree().process_frame
		var barn: Rect2 = _barn_rect()
		var hunter_in: bool = barn.has_point(hunter_xz)
		var t0: float = _hunt.get_elapsed_s()
		var done_at: float = -1.0
		var dist: float = INF
		while _hunt.get_elapsed_s() - t0 < DOG_LIMIT_S:
			await get_tree().process_frame
			var hp: Vector3 = _hunt.get_player().global_position
			dist = dog.get_xz().distance_to(Vector2(hp.x, hp.z))
			if dist <= DOG_NEAR_M and barn.has_point(dog.get_xz()) == hunter_in:
				done_at = _hunt.get_elapsed_s() - t0
				break
		var at: Vector2 = dog.get_xz()
		_check("dog_%s" % case_name, done_at >= 0.0,
			"t=%.1f s dog=(%.1f, %.1f) dist=%.1f in_barn=%s state=%s" % [done_at, at.x, at.y, dist, barn.has_point(at), dog.state])
		await _close()
