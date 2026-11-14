class_name HuntHostSync
extends Node
## Host side of the boar replication (docs/multiplayer.md sections 4.5, 6.1 and 6.3). Listens to the
## spawner and its boars, queues EV_* records in order, writes the boar section of H_SNAPSHOT and applies
## the clients' C_* claims after a light validation ("favor the shooter": a hit the client saw on its
## replica counts if it is plausible here).

const SPAWN_BYTES: int = 9
const HIT_BYTES: int = 8
const ATTACK_BYTES: int = 2
const CLAIM_HEADER_BYTES: int = 12
const CLAIM_HIT_BYTES: int = 6
const CHARGE_CLAIM_BYTES: int = 1
const WEIGHT_WIRE_SCALE: float = 100.0   # weight u16 in 0.01 kg
const DAMAGE_WIRE_SCALE: float = 10.0    # damage u16 in 0.1
const DIST_WIRE_SCALE: float = 10.0      # distance u16 in 0.1 m
const HEIGHT_WIRE_SCALE: float = 100.0   # origin_y i16 in cm
const DEATH_FLAG_ONE_SHOT: int = 1
const DEATH_FLAG_CLEAN: int = 2
const MAX_WIRE_ID: int = 255
const BAIT_CLAIM_BYTES: int = 4
const MAX_PATCHES_PER_RECORD: int = 255
const CROP_WIRE_SCALE: float = 100.0     # crop u16 in 0.01 %
const MAX_U8: int = 255
const MAX_U16: int = 65535
const DEFAULT_CLAIM_TOLERANCE_M: float = 12.0
## Rounding slack of the u16 fields when comparing a claim with the weapon limits.
const DAMAGE_SLACK: float = 1.0 / DAMAGE_WIRE_SCALE
const DIST_SLACK_M: float = 1.0 / DIST_WIRE_SCALE

var _world: HuntController = null
var _spawner: BoarSpawner = null
var _rect: Rect2 = Rect2()
var _events: StreamPeerBuffer = StreamPeerBuffer.new()
var _type_ids: Array[StringName] = []
var _weapon_ids: Array[StringName] = []
var _tolerance_m: float = DEFAULT_CLAIM_TOLERANCE_M
var _eaten: PackedInt32Array = PackedInt32Array()   # patches eaten since the last tick (EV_CROP_EATEN)

# Counters for tests and diagnostics.
var baits_claimed: int = 0
var patches_sent: int = 0
var hits_accepted: int = 0
var hits_rejected: int = 0
var shots_heard: int = 0
var charge_claims_accepted: int = 0
var charge_claims_rejected: int = 0


func setup(world: HuntController, spawner: BoarSpawner) -> void:
	_world = world
	_spawner = spawner
	_rect = world.get_map_rect()
	_type_ids = Data.get_boar_type_ids()
	_weapon_ids = Data.get_weapon_ids()
	_tolerance_m = float(Data.get_net().get("hit_claim_tolerance_m", DEFAULT_CLAIM_TOLERANCE_M))
	spawner.boar_added.connect(_on_boar_added)
	if world.crop != null:
		world.crop.patch_eaten.connect(_on_patch_eaten)


# --- Snapshot ------------------------------------------------------------------------------------

## Boar section of H_SNAPSHOT: n u8, n x { id u8, xz 2 x u16, yaw u8, st u8 } (alive only).
func write_boars(out: StreamPeerBuffer) -> void:
	var alive: Array[Boar] = _spawner.get_alive()
	var n: int = mini(alive.size(), MAX_WIRE_ID)
	out.put_u8(n)
	for i: int in n:
		var b: Boar = alive[i]
		out.put_u8(b.boar_id & MAX_WIRE_ID)
		NetCodec.put_xz(out, _rect, b.position.x, b.position.z)
		out.put_u8(NetCodec.angle_to_u8(b.get_yaw()))
		out.put_u8(b.net_state_byte())


# --- Events (host -> clients) --------------------------------------------------------------------

## The tick's eaten patches go first (one EV_CROP_EATEN per 255 patches), then the other events in order,
## so EV_HUNT_END always comes after the last patch of the hunt.
func take_events(out: StreamPeerBuffer) -> void:
	_write_crop(out)
	if _events.get_size() == 0:
		return
	out.put_data(_events.data_array)
	_events.clear()


func _on_patch_eaten(index: int) -> void:
	_eaten.append(index)


## EV_CROP_EATEN: n u8, n x patch u16.
func _write_crop(out: StreamPeerBuffer) -> void:
	var total: int = _eaten.size()
	var start: int = 0
	while start < total:
		var n: int = mini(total - start, MAX_PATCHES_PER_RECORD)
		out.put_u8(NetCodec.EV_CROP_EATEN)
		out.put_u16(1 + n * 2)
		out.put_u8(n)
		for i: int in n:
			out.put_u16(_eaten[start + i] & MAX_U16)
		start += n
	patches_sent += total
	_eaten.clear()


## EV_BAIT: xz 2 x u16, duration_s u8. Every bait placed on the host (its own or a client's C_BAIT).
func queue_bait(at: Vector3, duration_s: float) -> void:
	var at_pos: int = _begin(NetCodec.EV_BAIT)
	NetCodec.put_xz(_events, _rect, at.x, at.z)
	_events.put_u8(clampi(roundi(duration_s), 0, MAX_U8))
	_end(at_pos)


## EV_MESSAGE: target_slot u8 (255 = everyone), msg u8.
func queue_message(target_slot: int, msg: int) -> void:
	var at: int = _begin(NetCodec.EV_MESSAGE)
	_events.put_u8(target_slot & MAX_U8)
	_events.put_u8(msg & MAX_U8)
	_end(at)


## EV_HUNT_END: outcome u8, crop u16 (x0.01 %), duration_s u16, killed u8, total u8,
## n u8, n x {slot u8, kills u8, money u32}. entries: Array of {slot, kills, money}.
func queue_hunt_end(outcome: int, crop_pct: float, duration_s: float, killed: int, total: int, entries: Array) -> void:
	var at: int = _begin(NetCodec.EV_HUNT_END)
	_events.put_u8(outcome & MAX_U8)
	_events.put_u16(clampi(roundi(crop_pct * CROP_WIRE_SCALE), 0, MAX_U16))
	_events.put_u16(clampi(roundi(duration_s), 0, MAX_U16))
	_events.put_u8(mini(killed, MAX_U8))
	_events.put_u8(mini(total, MAX_U8))
	var n: int = mini(entries.size(), MAX_U8)
	_events.put_u8(n)
	for i: int in n:
		var e: Dictionary = entries[i]
		_events.put_u8(int(e.get("slot", 0)) & MAX_U8)
		_events.put_u8(mini(int(e.get("kills", 0)), MAX_U8))
		_events.put_u32(maxi(int(e.get("money", 0)), 0))
	_end(at)


func _on_boar_added(boar: Boar) -> void:
	if boar.boar_id > MAX_WIRE_ID:
		push_warning("HuntHostSync: boar id %d does not fit the wire (u8)" % boar.boar_id)
	boar.hit_applied.connect(_on_boar_hit)
	boar.attacked.connect(_on_boar_attacked)
	# EV_BOAR_SPAWN: id u8, type u8, weight u16 (x0.01 kg), xz 2 x u16, yaw u8
	var at: int = _begin(NetCodec.EV_BOAR_SPAWN)
	_events.put_u8(boar.boar_id & MAX_WIRE_ID)
	_events.put_u8(maxi(_type_ids.find(boar.type_id), 0))
	_events.put_u16(clampi(roundi(boar.weight_kg * WEIGHT_WIRE_SCALE), 0, 65535))
	NetCodec.put_xz(_events, _rect, boar.position.x, boar.position.z)
	_events.put_u8(NetCodec.angle_to_u8(boar.get_yaw()))
	_end(at)


## EV_BOAR_HIT: id u8, zone u8, shot_id u32, damage u16 (x0.1). Damage after the zone multiplier.
func _on_boar_hit(boar: Boar, zone: StringName, damage: float, shot_id: int) -> void:
	var at: int = _begin(NetCodec.EV_BOAR_HIT)
	_events.put_u8(boar.boar_id & MAX_WIRE_ID)
	_events.put_u8(maxi(NetCodec.ZONES.find(zone), 0))
	_events.put_u32(shot_id & 0xFFFFFFFF)
	_events.put_u16(clampi(roundi(damage * DAMAGE_WIRE_SCALE), 0, 65535))
	_end(at)


## EV_BOAR_ATTACK: id u8, victim_slot u8.
func _on_boar_attacked(boar: Boar, victim_slot: int) -> void:
	var at: int = _begin(NetCodec.EV_BOAR_ATTACK)
	_events.put_u8(boar.boar_id & MAX_WIRE_ID)
	_events.put_u8(victim_slot & 0xFF)
	_end(at)


## EV_BOAR_DEATH: id u8, xz 2 x u16, yaw u8, killer_slot u8, zone u8, flags u8 (b0 one shot, b1 clean),
## reward u32, killed u8, total u8. Called by HuntController once the kill is computed.
func queue_death(boar: Boar, kill: KillInfo, killed: int, total: int) -> void:
	var at: int = _begin(NetCodec.EV_BOAR_DEATH)
	_events.put_u8(boar.boar_id & MAX_WIRE_ID)
	NetCodec.put_xz(_events, _rect, boar.position.x, boar.position.z)
	_events.put_u8(NetCodec.angle_to_u8(boar.get_yaw()))
	_events.put_u8(kill.killer_slot & 0xFF)
	_events.put_u8(maxi(NetCodec.ZONES.find(kill.killing_zone), 0))
	var flags: int = 0
	if kill.one_shot:
		flags |= DEATH_FLAG_ONE_SHOT
	if kill.clean_kill:
		flags |= DEATH_FLAG_CLEAN
	_events.put_u8(flags)
	_events.put_u32(maxi(kill.reward_money, 0))
	_events.put_u8(mini(killed, 255))
	_events.put_u8(mini(total, 255))
	_end(at)


func _begin(type: int) -> int:
	var at: int = _events.get_position()
	_events.put_u8(type)
	_events.put_u16(0)
	return at


func _end(at: int) -> void:
	var end: int = _events.get_position()
	_events.seek(at + 1)
	_events.put_u16(end - at - NetCodec.RECORD_HEADER_BYTES)
	_events.seek(end)


# --- Claims (client -> host) ---------------------------------------------------------------------

func apply_claim(from_slot: int, type: int, inp: StreamPeerBuffer, length: int) -> void:
	match type:
		NetCodec.C_SHOT:
			_apply_shot(from_slot, inp, length)
		NetCodec.C_CHARGE_HIT:
			if length >= CHARGE_CLAIM_BYTES:
				var b: Boar = _spawner.get_boar(inp.get_u8())
				if b != null and b.is_alive() and b.net_confirm_charge_hit(from_slot):
					charge_claims_accepted += 1
				else:
					charge_claims_rejected += 1
		NetCodec.C_BAIT:
			# C_BAIT: xz 2 x u16. The host places it (it attracts its boars) and tells everybody (EV_BAIT).
			var placer: PlayerBase = _world.get_hunter(from_slot)
			if length >= BAIT_CLAIM_BYTES and placer != null and not placer.is_local():
				var xz: Vector2 = NetCodec.get_xz(inp, _rect)
				baits_claimed += 1
				_world.place_bait(Vector3(xz.x, 0.0, xz.y))


func _apply_shot(from_slot: int, inp: StreamPeerBuffer, length: int) -> void:
	if length < CLAIM_HEADER_BYTES:
		return
	var shot_id: int = inp.get_u32()
	var weapon_index: int = inp.get_u8()
	var oxz: Vector2 = NetCodec.get_xz(inp, _rect)
	var origin: Vector3 = Vector3(oxz.x, float(inp.get_16()) / HEIGHT_WIRE_SCALE, oxz.y)
	var n: int = inp.get_u8()
	if length < CLAIM_HEADER_BYTES + n * CLAIM_HIT_BYTES:
		return
	var weapon_id: StringName = _weapon_ids[weapon_index] if weapon_index < _weapon_ids.size() else &""
	var def: Dictionary = Data.get_weapon(weapon_id) if weapon_id != &"" else {}
	var shooter: PlayerBase = _world.get_hunter(from_slot)
	var valid_shooter: bool = shooter != null and not shooter.is_local() and not def.is_empty() \
		and (n == 0 or NetCodec.shot_slot(shot_id) == from_slot) and n <= int(def.get("pellets", 1))
	var max_damage: float = float(def.get("damage", 0.0)) + DAMAGE_SLACK
	var max_range: float = float(def.get("max_range_m", 0.0)) + DIST_SLACK_M
	for i: int in n:
		var boar_id: int = inp.get_u8()
		var zone_index: int = inp.get_u8()
		var damage: float = float(inp.get_u16()) / DAMAGE_WIRE_SCALE
		var dist: float = float(inp.get_u16()) / DIST_WIRE_SCALE
		var b: Boar = _spawner.get_boar(boar_id)
		var zone: StringName = NetCodec.ZONES[zone_index] if zone_index < Boar.HIT_ZONE_NODES.size() else &""
		var hz: HitZone = b.get_hit_zone(zone) if b != null and zone != &"" else null
		if not valid_shooter or hz == null or not b.is_alive() or damage > max_damage or dist > max_range:
			hits_rejected += 1
			continue
		var at: Vector3 = b.get_zone_position(zone)
		if absf(at.distance_to(origin) - dist) > _tolerance_m:
			hits_rejected += 1
			continue
		var hit: HitInfo = HitInfo.new()
		hit.shot_id = shot_id
		hit.weapon_id = weapon_id
		hit.damage = minf(damage, float(def.get("damage", damage)))
		hit.origin = origin
		hit.position = at
		hit.direction = (at - origin).normalized()
		hit.distance_m = dist
		hit.shooter_slot = from_slot
		hz.receive_hit(hit)    # same path as a local pellet: Boar._on_hit_received
		hits_accepted += 1
	if valid_shooter:
		shots_heard += 1
		_spawner.notify_shot(origin, float(def.get("noise_radius_m", 0.0)))
