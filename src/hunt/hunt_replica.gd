class_name HuntReplica
extends Node3D
## Client side of the boar replication (docs/multiplayer.md sections 4.5, 6.1 and 6.3). Creates, moves and
## kills BoarPuppet children from the host's H_SNAPSHOT and EV_* records, answers the boar getters of the
## world, predicts the local hunter's hits and queues the C_* claims for the host.
## Does not depend on HuntController: setup(world, heightmap, map_rect, crop) is enough (tests build it alone).

## A boar died on the host. kill.killer_slot says who gets the credit; killed/total are the team counts.
signal kill_confirmed(kill: KillInfo, killed: int, total: int)
## A bait was placed on the host (by anyone). at: XZ (Y = 0).
signal bait_received(at: Vector3, duration_s: float)
## EV_MESSAGE addressed to this machine (or everyone). msg: index of docs/multiplayer.md section 4.5.
signal message_received(msg: int)
## The host ended the hunt. entries: Array of {slot, kills, money}.
signal hunt_end_received(outcome: int, crop_pct: float, killed: int, total: int, entries: Array)

const SPAWN_BYTES: int = 9
const HIT_BYTES: int = 8
const ATTACK_BYTES: int = 2
const DEATH_BYTES: int = 15
const SNAP_BOAR_BYTES: int = 7
const CLAIM_HEADER_BYTES: int = 12
const CLAIM_HIT_BYTES: int = 6
const WEIGHT_WIRE_SCALE: float = 100.0   # weight u16 in 0.01 kg
const DAMAGE_WIRE_SCALE: float = 10.0    # damage u16 in 0.1
const DIST_WIRE_SCALE: float = 10.0      # distance u16 in 0.1 m
const HEIGHT_WIRE_SCALE: float = 100.0   # origin_y i16 in cm
const DEATH_FLAG_ONE_SHOT: int = 1
const DEATH_FLAG_CLEAN: int = 2
const NO_INDEX: int = 255
const BAIT_BYTES: int = 5
const MESSAGE_BYTES: int = 2
const HUNT_END_HEADER_BYTES: int = 8
const HUNT_END_ENTRY_BYTES: int = 6
const CROP_WIRE_SCALE: float = 100.0     # crop u16 in 0.01 %
const PATCH_BYTES: int = 2
const SNAP_FLAG_CROP_ATTACK: int = 1     # H_SNAPSHOT flags b0
const DEFAULT_INTERP_DELAY_MS: float = 200.0
const DEFAULT_THERMAL_RANGE_M: float = 150.0
## Host-clock estimate: follows the freshest snapshot at once, eases down slowly when packets come late.
const CLOCK_EASE_DOWN: float = 0.05

var _world: HuntWorld = null
var _hm: Heightmap = null
var _rect: Rect2 = Rect2()
var _crop: CropManager = null           # F5: crop mirror
var _puppets: Dictionary = {}           # boar_id -> BoarPuppet (alive and dead)
var _alive_ids: PackedInt32Array = PackedInt32Array()
var _type_ids: Array[StringName] = []
var _weapon_ids: Array[StringName] = []
var _delay_ms: float = DEFAULT_INTERP_DELAY_MS
var _clock_ms: float = 0.0
var _offset_ms: float = 0.0
var _has_offset: bool = false
var _claims: StreamPeerBuffer = StreamPeerBuffer.new()
var _pending_hits: Array = []           # [boar_id, zone index, damage q, dist q] of the shot being fired
var _pending_shot_id: int = 0
var _thermal_on: bool = false
var _thermal_range: float = DEFAULT_THERMAL_RANGE_M
var _thermal_timer: float = 0.0
var _eaten_scratch: PackedInt32Array = PackedInt32Array()

# Counters for tests and diagnostics.
var baits_claimed: int = 0
var patches_applied: int = 0
var shots_claimed: int = 0
var hits_claimed: int = 0
var charge_hits: int = 0


func setup(world: HuntWorld, heightmap: Heightmap, map_rect: Rect2, crop: CropManager) -> void:
	_world = world
	_hm = heightmap
	_rect = map_rect
	_crop = crop
	_type_ids = Data.get_boar_type_ids()
	_weapon_ids = Data.get_weapon_ids()
	_delay_ms = float(Data.get_net().get("boar_interp_delay_ms", DEFAULT_INTERP_DELAY_MS))
	_thermal_range = float(Data.get_equipment(Ids.I_THERMAL_SCOPE).get("effect", {}).get("highlight_range_m",
		DEFAULT_THERMAL_RANGE_M))
	if not GameEvents.shot_fired.is_connected(_on_shot_fired):
		GameEvents.shot_fired.connect(_on_shot_fired)
	if not GameEvents.thermal_vision_changed.is_connected(_on_thermal_changed):
		GameEvents.thermal_vision_changed.connect(_on_thermal_changed)


func _exit_tree() -> void:
	if GameEvents.shot_fired.is_connected(_on_shot_fired):
		GameEvents.shot_fired.disconnect(_on_shot_fired)
	if GameEvents.thermal_vision_changed.is_connected(_on_thermal_changed):
		GameEvents.thermal_vision_changed.disconnect(_on_thermal_changed)


func _process(delta: float) -> void:
	_clock_ms += delta * 1000.0
	if _thermal_on:
		_thermal_timer -= delta
		if _thermal_timer <= 0.0:
			_thermal_timer = BoarSpawner.THERMAL_REFRESH_S
			refresh_thermal()
	if not _has_offset:
		return
	var t: float = render_time_ms()
	var local: PlayerBase = _world.get_player() if _world != null else null
	var over: bool = _world == null or _world.is_hunt_over()
	for id: int in _alive_ids:
		var p: BoarPuppet = _puppets[id]
		p.update_pose(t, delta)
		if not over and local != null and p.try_charge_hit(local):
			charge_hits += 1
			_queue_charge_claim(id)


# --- Clock ---------------------------------------------------------------------------------------

## Host time (ms since the hunt began) this machine shows the boars at.
func render_time_ms() -> float:
	return _clock_ms + _offset_ms - _delay_ms


func _note_host_time(t_ms: float) -> void:
	var sample: float = t_ms - _clock_ms
	if not _has_offset or sample > _offset_ms:
		_offset_ms = sample
		_has_offset = true
	else:
		_offset_ms = lerpf(_offset_ms, sample, CLOCK_EASE_DOWN)


# --- Snapshot ------------------------------------------------------------------------------------

## Boar section of H_SNAPSHOT: n u8, n x { id u8, xz 2 x u16, yaw u8, st u8 }. Reads exactly that section
## (stops at a truncated entry). Unknown ids wait for their EV_BOAR_SPAWN.
func apply_snapshot_boars(inp: StreamPeerBuffer, t_ms: int) -> void:
	if inp.get_available_bytes() < 1:
		return
	var n: int = inp.get_u8()
	_note_host_time(float(t_ms))
	for i: int in n:
		if inp.get_available_bytes() < SNAP_BOAR_BYTES:
			return
		var id: int = inp.get_u8()
		var xz: Vector2 = NetCodec.get_xz(inp, _rect)
		var yaw: float = NetCodec.u8_to_angle(inp.get_u8())
		var st: int = inp.get_u8()
		var p: BoarPuppet = _puppets.get(id) as BoarPuppet
		if p != null:
			p.push_sample(float(t_ms), xz, yaw, st)


# --- Events (host -> client) ---------------------------------------------------------------------

func apply_event(type: int, inp: StreamPeerBuffer, length: int) -> void:
	match type:
		NetCodec.EV_BOAR_SPAWN:
			if length >= SPAWN_BYTES:
				_on_spawn(inp)
		NetCodec.EV_BOAR_HIT:
			if length >= HIT_BYTES:
				_on_hit(inp)
		NetCodec.EV_BOAR_ATTACK:
			if length >= ATTACK_BYTES:
				_on_attack(inp)
		NetCodec.EV_BOAR_DEATH:
			if length >= DEATH_BYTES:
				_on_death(inp)
		NetCodec.EV_CROP_EATEN:
			_on_crop_eaten(inp, length)
		NetCodec.EV_BAIT:
			if length >= BAIT_BYTES:
				var xz: Vector2 = NetCodec.get_xz(inp, _rect)
				bait_received.emit(Vector3(xz.x, 0.0, xz.y), float(inp.get_u8()))
		NetCodec.EV_MESSAGE:
			if length >= MESSAGE_BYTES:
				var target: int = inp.get_u8()
				var msg: int = inp.get_u8()
				if target == NetCodec.NO_SLOT or (_world != null and target == _world.get_local_slot()):
					message_received.emit(msg)
		NetCodec.EV_HUNT_END:
			if length >= HUNT_END_HEADER_BYTES:
				_on_hunt_end(inp, length)


## H_SNAPSHOT header, crop part: health (x0.01 %) and flags b0 (boars at the crop) into the crop mirror.
func apply_crop_state(crop_pct: float, flags: int) -> void:
	if _crop == null:
		return
	_crop.set_replicated_health(crop_pct)
	_crop.set_replicated_attack((flags & SNAP_FLAG_CROP_ATTACK) != 0)


## EV_CROP_EATEN: n u8, n x patch u16 -> the same patches eaten here.
func _on_crop_eaten(inp: StreamPeerBuffer, length: int) -> void:
	if length < 1:
		return
	var n: int = inp.get_u8()
	n = mini(n, (length - 1) / PATCH_BYTES)
	_eaten_scratch.resize(n)
	for i: int in n:
		_eaten_scratch[i] = inp.get_u16()
	patches_applied += n
	if _crop != null:
		_crop.apply_eaten(_eaten_scratch)


func _on_hunt_end(inp: StreamPeerBuffer, length: int) -> void:
	var outcome: int = inp.get_u8()
	var crop_pct: float = float(inp.get_u16()) / CROP_WIRE_SCALE
	inp.get_u16()   # duration_s: each machine keeps its own (more precise) clock
	var killed: int = inp.get_u8()
	var total: int = inp.get_u8()
	var n: int = inp.get_u8()
	n = mini(n, (length - HUNT_END_HEADER_BYTES) / HUNT_END_ENTRY_BYTES)
	var entries: Array = []
	for i: int in n:
		var slot: int = inp.get_u8()
		var kills: int = inp.get_u8()
		var money: int = inp.get_u32()
		entries.append({"slot": slot, "kills": kills, "money": money})
	hunt_end_received.emit(outcome, crop_pct, killed, total, entries)


func _on_spawn(inp: StreamPeerBuffer) -> void:
	var id: int = inp.get_u8()
	var type_index: int = inp.get_u8()
	var weight: float = float(inp.get_u16()) / WEIGHT_WIRE_SCALE
	var xz: Vector2 = NetCodec.get_xz(inp, _rect)
	var yaw: float = NetCodec.u8_to_angle(inp.get_u8())
	if _puppets.has(id) or type_index >= _type_ids.size():
		return
	var type_id: StringName = _type_ids[type_index]
	var p: BoarPuppet = BoarPuppet.new()
	p.setup(id, type_id, weight, xz, yaw, _hm)
	p.hit_by_local.connect(_on_local_hit)
	add_child(p)
	_puppets[id] = p
	_alive_ids.append(id)
	GameEvents.boar_spawned.emit(id, type_id, weight)


func _on_hit(inp: StreamPeerBuffer) -> void:
	var id: int = inp.get_u8()
	var zone_index: int = inp.get_u8()
	var shot_id: int = inp.get_u32()
	var damage: float = float(inp.get_u16()) / DAMAGE_WIRE_SCALE
	var p: BoarPuppet = _puppets.get(id) as BoarPuppet
	if p == null or not p.alive or zone_index >= NetCodec.ZONES.size():
		return
	if _world != null and NetCodec.shot_slot(shot_id) == _world.get_local_slot():
		return   # this machine already showed its own hit (prediction)
	var zone: StringName = NetCodec.ZONES[zone_index]
	p.play_hit_feedback(zone)
	GameEvents.boar_hit.emit(id, zone, damage, p.get_zone_position(zone), shot_id)


func _on_attack(inp: StreamPeerBuffer) -> void:
	var id: int = inp.get_u8()
	var victim: int = inp.get_u8()
	var p: BoarPuppet = _puppets.get(id) as BoarPuppet
	if p == null or (_world != null and victim == _world.get_local_slot()):
		return   # the local victim already played it when it judged the charge
	p.play_attack()


func _on_death(inp: StreamPeerBuffer) -> void:
	var id: int = inp.get_u8()
	var xz: Vector2 = NetCodec.get_xz(inp, _rect)
	var yaw: float = NetCodec.u8_to_angle(inp.get_u8())
	var killer: int = inp.get_u8()
	var zone_index: int = inp.get_u8()
	var flags: int = inp.get_u8()
	var reward: int = inp.get_u32()
	var killed: int = inp.get_u8()
	var total: int = inp.get_u8()
	var p: BoarPuppet = _puppets.get(id) as BoarPuppet
	if p == null or not p.alive:
		return
	p.die(xz, yaw)
	var at: int = _alive_ids.find(id)
	if at >= 0:
		_alive_ids.remove_at(at)
	var kill: KillInfo = KillInfo.new()
	kill.boar_id = id
	kill.type_id = p.type_id
	kill.weight_kg = p.weight_kg
	kill.killing_zone = NetCodec.ZONES[zone_index] if zone_index < NetCodec.ZONES.size() else Ids.ZONE_BODY
	kill.one_shot = (flags & DEATH_FLAG_ONE_SHOT) != 0
	kill.clean_kill = (flags & DEATH_FLAG_CLEAN) != 0
	kill.reward_money = reward
	kill.position = p.global_position
	kill.killer_slot = killer
	kill_confirmed.emit(kill, killed, total)


# --- Prediction and claims (client -> host) ------------------------------------------------------

## The local weapon hit a puppet zone: show it now and keep it for this shot's C_SHOT.
func _on_local_hit(p: BoarPuppet, hit: HitInfo) -> void:
	var zone_index: int = NetCodec.ZONES.find(hit.zone)
	if zone_index < 0:
		return
	if _pending_hits.is_empty():
		_pending_shot_id = hit.shot_id
	elif hit.shot_id != _pending_shot_id:
		_pending_hits.clear()   # a shot that never reached shot_fired: drop it
		_pending_shot_id = hit.shot_id
	_pending_hits.append([p.boar_id, zone_index,
		clampi(roundi(hit.damage * DAMAGE_WIRE_SCALE), 0, 65535),
		clampi(roundi(hit.distance_m * DIST_WIRE_SCALE), 0, 65535)])
	p.play_hit_feedback(hit.zone)
	GameEvents.boar_hit.emit(p.boar_id, hit.zone, hit.damage * p.zone_multiplier(hit.zone), hit.position, hit.shot_id)


## shot_fired comes after the pellets of the same shot (weapon.gd): close its C_SHOT. A miss is claimed
## too (n = 0): the host's boars hear every shot.
## C_SHOT: shot_id u32, weapon u8, origin xz 2 x u16, origin_y i16 (cm), n u8, n x { boar u8, zone u8,
## damage u16 (x0.1), dist u16 (x0.1 m) }.
func _on_shot_fired(weapon_id: StringName, origin: Vector3, _direction: Vector3, _noise_radius_m: float) -> void:
	if _world == null or not is_inside_tree():
		return
	var shot_id: int = _pending_shot_id if not _pending_hits.is_empty() \
		else NetCodec.make_shot_id(_world.get_local_slot(), 0)
	var n: int = mini(_pending_hits.size(), 255)
	var weapon_index: int = _weapon_ids.find(weapon_id)
	var at: int = _begin_claim(NetCodec.C_SHOT)
	_claims.put_u32(shot_id)
	_claims.put_u8(weapon_index if weapon_index >= 0 and weapon_index < NO_INDEX else NO_INDEX)
	NetCodec.put_xz(_claims, _rect, origin.x, origin.z)
	_claims.put_16(clampi(roundi(origin.y * HEIGHT_WIRE_SCALE), -32768, 32767))
	_claims.put_u8(n)
	for i: int in n:
		var h: Array = _pending_hits[i]
		_claims.put_u8(int(h[0]) & 0xFF)
		_claims.put_u8(int(h[1]))
		_claims.put_u16(int(h[2]))
		_claims.put_u16(int(h[3]))
	_end_claim(at)
	shots_claimed += 1
	hits_claimed += n
	_pending_hits.clear()
	_pending_shot_id = 0


## C_CHARGE_HIT: boar u8.
func _queue_charge_claim(boar_id: int) -> void:
	var at: int = _begin_claim(NetCodec.C_CHARGE_HIT)
	_claims.put_u8(boar_id & 0xFF)
	_end_claim(at)


## C_BAIT: xz 2 x u16. The local hunter used a corn bait; the host places the one that attracts boars.
func queue_bait_claim(at: Vector3) -> void:
	var pos: int = _begin_claim(NetCodec.C_BAIT)
	NetCodec.put_xz(_claims, _rect, at.x, at.z)
	_end_claim(pos)
	baits_claimed += 1


func take_claims(out: StreamPeerBuffer) -> void:
	if _claims.get_size() == 0:
		return
	out.put_data(_claims.data_array)
	_claims.clear()


func _begin_claim(type: int) -> int:
	var at: int = _claims.get_position()
	_claims.put_u8(type)
	_claims.put_u16(0)
	return at


func _end_claim(at: int) -> void:
	var end: int = _claims.get_position()
	_claims.seek(at + 1)
	_claims.put_u16(end - at - NetCodec.RECORD_HEADER_BYTES)
	_claims.seek(end)


# --- Thermal scope (local item, section 6.6): same rule as BoarSpawner on the host -----------------

func _on_thermal_changed(active: bool) -> void:
	_thermal_on = active
	_thermal_timer = 0.0
	if not active:
		for id: int in _alive_ids:
			(_puppets[id] as BoarPuppet).set_highlight(false)


## Highlights the live puppets within highlight_range_m of the local hunter.
func refresh_thermal() -> void:
	var local: PlayerBase = _world.get_player() if _world != null else null
	if local == null:
		return
	var from: Vector2 = Vector2(local.global_position.x, local.global_position.z)
	for id: int in _alive_ids:
		var p: BoarPuppet = _puppets[id]
		p.set_highlight(from.distance_to(p.get_xz()) <= _thermal_range)


func is_thermal_on() -> bool:
	return _thermal_on


# --- Getters for the world (same answers the spawner gives on the host) --------------------------

func get_alive_ids() -> PackedInt32Array:
	return _alive_ids


func get_puppet(boar_id: int) -> BoarPuppet:
	return _puppets.get(boar_id) as BoarPuppet


func get_boar_position(boar_id: int) -> Vector3:
	var p: BoarPuppet = _puppets.get(boar_id) as BoarPuppet
	return p.global_position if p != null and p.is_inside_tree() else Vector3.INF


func get_boar_type(boar_id: int) -> StringName:
	var p: BoarPuppet = _puppets.get(boar_id) as BoarPuppet
	return p.type_id if p != null else &""


func get_boar_zone_position(boar_id: int, zone: StringName) -> Vector3:
	var p: BoarPuppet = _puppets.get(boar_id) as BoarPuppet
	return p.get_zone_position(zone) if p != null and p.is_inside_tree() else Vector3.INF


func get_nearest_boar_position(from: Vector3) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	var at: Vector2 = Vector2(from.x, from.z)
	for id: int in _alive_ids:
		var p: BoarPuppet = _puppets[id]
		var d: float = at.distance_squared_to(p.get_xz())
		if d < best_d:
			best_d = d
			best = p.global_position
	return best
