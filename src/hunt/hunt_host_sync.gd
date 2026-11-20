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
const BAIT_EVENT_BYTES: int = 5          # EV_BAIT body
const DOG_MARK_EVENT_BYTES: int = 3      # EV_DOG_MARK body
const MAX_PATCHES_PER_RECORD: int = 255
const CROP_WIRE_SCALE: float = 100.0     # crop u16 in 0.01 %
const MAX_U8: int = 255
const MAX_U16: int = 65535
const MARK_WIRE_SCALE: float = 10.0      # EV_DOG_MARK duration u8 in 0.1 s
const DOG_CMD_ATTACK: int = 0            # EV_DOG_CMD cmd: 0 "Pega!", 1 "Volta!"
const DOG_CMD_RECALL: int = 1
const FULL_SYNC_BYTES: int = 10          # EV_FULL_SYNC body: t_ms u32, crop u16, killed u8, total u8, n_records u16
const FULL_SYNC_COUNT_AT: int = 8        # offset of n_records inside that body
const SYNC_MARK_OWNER: int = 255         # EV_DOG_MARK owner of a replayed mark (the owner does not matter)
const HORDE_WAVE_BYTES: int = 7          # EV_HORDE_WAVE body (docs/horda.md section 9.2)
const COUNTDOWN_WIRE_SCALE: float = 10.0 # EV_HORDE_WAVE countdown u16 in 0.1 s, rounded up
const COUNTDOWN_EPSILON: float = 0.0001  # keeps 12.0 s from rounding up to 12.1 s
const DEFAULT_CLAIM_TOLERANCE_M: float = 12.0
const HUNTER_REVIVED_BYTES: int = 2      # EV_HUNTER_REVIVED body: target_slot u8, by_slot u8
const AMMO_CRATE_BYTES: int = 3          # EV_AMMO_CRATE body: crate u8, available u8, taker_slot u8
const REVIVE_CLAIM_BYTES: int = 1        # C_REVIVE body: target_slot u8
const AMMO_CRATE_CLAIM_BYTES: int = 1    # C_AMMO_CRATE body: crate u8
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
## Rejoin (section 4.7.6): the original bytes of every EV_BOAR_SPAWN and EV_BOAR_DEATH since the hunt began,
## in the order they happened, and the EV_HUNT_END record once the hunt is over.
var _journal: StreamPeerBuffer = StreamPeerBuffer.new()
var _journal_records: int = 0
var _hunt_end_record: PackedByteArray = PackedByteArray()

# Counters for tests and diagnostics.
var baits_claimed: int = 0
var patches_sent: int = 0
var hits_accepted: int = 0
var hits_rejected: int = 0
var shots_heard: int = 0
var charge_claims_accepted: int = 0
var charge_claims_rejected: int = 0
var dog_commands_applied: int = 0
var dog_commands_ignored: int = 0
var full_syncs_written: int = 0
var revive_claims: int = 0
var ammo_crate_claims: int = 0


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


## Dog section of H_SNAPSHOT: n u8, n x { owner u8, xz 2 x u16, yaw u8, st u8, health u8 (%) }.
func write_dogs(out: StreamPeerBuffer) -> void:
	var dogs: Array[Dog] = _world.get_dogs()
	var n: int = mini(dogs.size(), MAX_U8)
	out.put_u8(n)
	for i: int in n:
		var d: Dog = dogs[i]
		out.put_u8(d.owner_slot & MAX_U8)
		NetCodec.put_xz(out, _rect, d.position.x, d.position.z)
		out.put_u8(NetCodec.angle_to_u8(d.get_yaw()))
		out.put_u8(d.net_state_byte())
		out.put_u8(clampi(roundi(d.get_health_pct()), 0, MAX_U8))


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


func _write_crop(out: StreamPeerBuffer) -> void:
	_put_patch_records(out, _eaten)
	patches_sent += _eaten.size()
	_eaten.clear()


## EV_CROP_EATEN: n u8, n x patch u16. One record per 255 patches; returns how many records were written.
func _put_patch_records(out: StreamPeerBuffer, patches: PackedInt32Array) -> int:
	var total: int = patches.size()
	var start: int = 0
	var records: int = 0
	while start < total:
		var n: int = mini(total - start, MAX_PATCHES_PER_RECORD)
		out.put_u8(NetCodec.EV_CROP_EATEN)
		out.put_u16(1 + n * 2)
		out.put_u8(n)
		for i: int in n:
			out.put_u16(patches[start + i] & MAX_U16)
		start += n
		records += 1
	return records


# --- Rejoin sync (host -> the client that came back, section 4.7.6) --------------------------------

## EV_FULL_SYNC record (t_ms u32, crop u16 x0.01 %, killed u8, total u8, n_records u16) followed by the first two
## parts of the replay: the spawn/death journal and every eaten patch. Returns the records replayed so far; the
## world appends its own (baits, marks, hunt end) and closes the count with set_full_sync_count.
## Consistent cut: the caller drains net_take_events to the links that already existed BEFORE calling this, so
## nothing in here is sent again to the link that came back (section 4.7.4, step 3).
func write_full_sync(out: StreamPeerBuffer) -> int:
	if has_pending_events():
		push_warning("HuntHostSync: full sync written with events still queued (they will reach the new link twice)")
	out.put_u8(NetCodec.EV_FULL_SYNC)
	out.put_u16(FULL_SYNC_BYTES)
	out.put_u32(_world.net_time_ms() & 0xFFFFFFFF)
	out.put_u16(clampi(roundi(_world.get_crop_health_pct() * CROP_WIRE_SCALE), 0, MAX_U16))
	out.put_u8(mini(_world.get_boars_killed(), MAX_U8))
	out.put_u8(mini(_world.get_boars_total(), MAX_U8))
	out.put_u16(0)   # n_records: set_full_sync_count
	var records: int = _journal_records
	if _journal.get_size() > 0:
		out.put_data(_journal.data_array)
	if _world.crop != null:
		records += _put_patch_records(out, _world.crop.get_eaten_indices())
	full_syncs_written += 1
	return records


## Replayed EV_BAIT of an active bait: duration_s = ceil(remaining_s), 1..255.
func write_bait_replay(out: StreamPeerBuffer, at: Vector3, remaining_s: float) -> void:
	out.put_u8(NetCodec.EV_BAIT)
	out.put_u16(BAIT_EVENT_BYTES)
	NetCodec.put_xz(out, _rect, at.x, at.z)
	out.put_u8(clampi(ceili(remaining_s), 1, MAX_U8))


## Replayed EV_DOG_MARK of a mark that has not expired: owner 255, time left x0.1 s, 1..255.
func write_mark_replay(out: StreamPeerBuffer, boar_id: int, remaining_s: float) -> void:
	out.put_u8(NetCodec.EV_DOG_MARK)
	out.put_u16(DOG_MARK_EVENT_BYTES)
	out.put_u8(SYNC_MARK_OWNER)
	out.put_u8(boar_id & MAX_WIRE_ID)
	out.put_u8(clampi(ceili(remaining_s * MARK_WIRE_SCALE), 1, MAX_U8))


## Horde: replayed EV_HORDE_WAVE with the current wave state (countdown = time left). One record.
func write_horde_wave_replay(out: StreamPeerBuffer, wave: int, wave_count: int, phase: StringName, countdown_s: float,
		wave_total: int, killed_before: int) -> void:
	out.put_u8(NetCodec.EV_HORDE_WAVE)
	out.put_u16(HORDE_WAVE_BYTES)
	_put_horde_wave(out, wave, wave_count, phase, countdown_s, wave_total, killed_before)


## Horde level 2: replayed EV_AMMO_CRATE with a crate's state now (taker 255). One record.
func write_ammo_crate_replay(out: StreamPeerBuffer, crate: int, available: bool) -> void:
	out.put_u8(NetCodec.EV_AMMO_CRATE)
	out.put_u16(AMMO_CRATE_BYTES)
	out.put_u8(crate & MAX_U8)
	out.put_u8(1 if available else 0)
	out.put_u8(NetCodec.NO_SLOT)


## The EV_HUNT_END sent when the hunt ended, byte for byte. Returns 1 if written, 0 if the hunt is still on.
func write_hunt_end_replay(out: StreamPeerBuffer) -> int:
	if _hunt_end_record.is_empty():
		return 0
	out.put_data(_hunt_end_record)
	return 1


## Writes n_records into the EV_FULL_SYNC record that starts at `sync_at` in `out` (cursor stays at the end).
func set_full_sync_count(out: StreamPeerBuffer, sync_at: int, records: int) -> void:
	var end: int = out.get_position()
	out.seek(sync_at + NetCodec.RECORD_HEADER_BYTES + FULL_SYNC_COUNT_AT)
	out.put_u16(clampi(records, 0, MAX_U16))
	out.seek(end)


## True while something waits for the next take_events (tests and the cut check of write_full_sync).
func has_pending_events() -> bool:
	return _events.get_size() > 0 or not _eaten.is_empty()


func get_journal_records() -> int:
	return _journal_records


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


## EV_DOG_MARK: owner u8, boar u8, duration u8 (x0.1 s). The mark is good for the whole team.
func queue_dog_mark(owner_slot: int, boar_id: int, duration_s: float) -> void:
	var at: int = _begin(NetCodec.EV_DOG_MARK)
	_events.put_u8(owner_slot & MAX_U8)
	_events.put_u8(boar_id & MAX_WIRE_ID)
	_events.put_u8(clampi(roundi(duration_s * MARK_WIRE_SCALE), 0, MAX_U8))
	_end(at)


## EV_DOG_CMD: owner u8, cmd u8 (0 "Pega!", 1 "Volta!"). cmd is Ids.CMD_ATTACK or Ids.CMD_RECALL.
func queue_dog_command(owner_slot: int, cmd: StringName) -> void:
	var at: int = _begin(NetCodec.EV_DOG_CMD)
	_events.put_u8(owner_slot & MAX_U8)
	_events.put_u8(DOG_CMD_ATTACK if cmd == Ids.CMD_ATTACK else DOG_CMD_RECALL)
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


## Horde, EV_HORDE_WAVE: wave u8, wave_count u8, phase u8 (NetCodec.HORDE_PHASES), countdown u16 (x0.1 s, rounded
## up; 0 in a wave), wave_total u8, killed_before u8. Once per HordeDirector.wave_changed.
func queue_horde_wave(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int) -> void:
	var at: int = _begin(NetCodec.EV_HORDE_WAVE)
	_put_horde_wave(_events, wave, wave_count, phase, countdown_s, wave_total, killed_before)
	_end(at)


## Horde level 2, EV_HUNTER_REVIVED: target_slot u8, by_slot u8. Once per revive the host accepted.
func queue_hunter_revived(target_slot: int, by_slot: int) -> void:
	var at: int = _begin(NetCodec.EV_HUNTER_REVIVED)
	_events.put_u8(target_slot & MAX_U8)
	_events.put_u8(by_slot & MAX_U8)
	_end(at)


## Horde level 2, EV_AMMO_CRATE: crate u8, available u8 (0/1), taker_slot u8 (255 = nobody). A crate taken
## (available false, taker = who) or back (available true, taker 255).
func queue_ammo_crate(crate: int, available: bool, taker_slot: int) -> void:
	var at: int = _begin(NetCodec.EV_AMMO_CRATE)
	_events.put_u8(crate & MAX_U8)
	_events.put_u8(1 if available else 0)
	_events.put_u8(taker_slot & MAX_U8)
	_end(at)


func _put_horde_wave(out: StreamPeerBuffer, wave: int, wave_count: int, phase: StringName, countdown_s: float,
		wave_total: int, killed_before: int) -> void:
	var phase_index: int = maxi(NetCodec.HORDE_PHASES.find(phase), 0)
	var countdown: int = 0
	if phase == Ids.HP_INTERMISSION:
		countdown = clampi(ceili(countdown_s * COUNTDOWN_WIRE_SCALE - COUNTDOWN_EPSILON), 0, MAX_U16)
	out.put_u8(clampi(wave, 0, MAX_U8))
	out.put_u8(clampi(wave_count, 0, MAX_U8))
	out.put_u8(phase_index)
	out.put_u16(countdown)
	out.put_u8(clampi(wave_total, 0, MAX_U8))
	out.put_u8(clampi(killed_before, 0, MAX_U8))


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
	_events.seek(at)
	var type: int = _events.get_u8()
	_events.put_u16(end - at - NetCodec.RECORD_HEADER_BYTES)
	_events.seek(end)
	# Rejoin: births and kills are kept for the whole hunt, the end record once (section 4.7.6).
	if type == NetCodec.EV_BOAR_SPAWN or type == NetCodec.EV_BOAR_DEATH:
		_journal.put_data(_events.data_array.slice(at, end))
		_journal_records += 1
	elif type == NetCodec.EV_HUNT_END:
		_hunt_end_record = _events.data_array.slice(at, end)


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
		NetCodec.C_DOG_CMD:
			# C_DOG_CMD: no body. The dog of that slot gets the command as if its owner had pressed the key here.
			var dog: Dog = _world.get_dog_of(from_slot)
			if dog != null and not dog.is_local_owner():
				dog.command()
				dog_commands_applied += 1
			else:
				dog_commands_ignored += 1
		NetCodec.C_BAIT:
			# C_BAIT: xz 2 x u16. The host places it (it attracts its boars) and tells everybody (EV_BAIT).
			var placer: PlayerBase = _world.get_hunter(from_slot)
			if length >= BAIT_CLAIM_BYTES and placer != null and not placer.is_local():
				var xz: Vector2 = NetCodec.get_xz(inp, _rect)
				baits_claimed += 1
				_world.place_bait(Vector3(xz.x, 0.0, xz.y))
		NetCodec.C_REVIVE:
			# C_REVIVE: target_slot u8. The client finished holding interact next to a downed hunter.
			if length >= REVIVE_CLAIM_BYTES:
				revive_claims += 1
				_world.claim_revive(from_slot, inp.get_u8())
		NetCodec.C_AMMO_CRATE:
			# C_AMMO_CRATE: crate u8. The client pressed interact at an available crate and needs ammo.
			if length >= AMMO_CRATE_CLAIM_BYTES:
				ammo_crate_claims += 1
				_world.claim_ammo_crate(from_slot, inp.get_u8())


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
