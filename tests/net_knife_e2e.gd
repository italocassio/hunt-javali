extends "res://src/hunt/debug/net_hunt_e2e.gd"
## Two-process knife scenario (docs/plano_faca_mochila_folego.md 1.5 and 2.8; F4, package QA4).
##
## Reuses package B's orchestrator (Bun server + a host process + a client process, victory scenario) and changes only
## HOW THE CLIENT KILLS: it never fires the gun, it walks up to each boar replica and swings the knife (the 4th level,
## 90 damage) with `bot_knife()`. Every swing is a C_SHOT with weapon byte KNIFE_WEAPON_INDEX (254); the host validates
## damage and reach against the knife definition. The host bot keeps shooting with the carbine, as in "victory".
##
## What it proves, on top of everything `_check_victory` already checks (VICTORY on both, same killer for every kill,
## same scoreboard, same money, same crop):
##   - the client got at least CLIENT_KILLS kills with the knife alone (its magazine never changed);
##   - the host accepted those claims and rejected none (none beyond reach, none above the top level damage);
##   - the client's own result credits only its knife kills, and the host's result shows the same kills.
##
## Run through tests/net_test.tscn (scenario "knife"); alone:
##   tools/godot.sh --headless --path . res://tests/net_knife_e2e.tscn -- --scenario=victory
## Prints "NET_HUNT_E2E checks=N failures=M" like its parent.

## Knife level the client brings (the request is patched as the hunt loads, the Profile is never touched).
const KNIFE_LEVEL: int = 4
## Where the client stands from the vital zone of the boar it swings at (the knife reaches 2.2 m).
const KNIFE_STAND_M: float = 1.3
## Wait after standing/looking before the swing, so the client's puppet and the camera settle.
const KNIFE_SETTLE_MS: int = 250
## swing_interval_s (0.6) plus slack: the next swing finds the knife ready.
const KNIFE_COOLDOWN_MS: int = 700

var _swings: int = 0
var _swing_refused: int = 0


## Same seed as the parent; the client additionally brings the top level knife in its pending request.
func _fix_seed() -> void:
	super()
	if _role != "client":
		return
	var req: HuntRequest = Router.get_pending_request()
	if req != null:
		req.knife_level = KNIFE_LEVEL


## The client swings the knife at the nearest live boar until `done`; the host (and every other caller) uses the gun.
func _kill_until(world: HuntController, player: PlayerBase, done: Callable, timeout_s: float) -> void:
	if _role != "client":
		await super(world, player, done, timeout_s)
		return
	var limit: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var ammo_start: int = player.get_ammo_in_mag()
	_result["knife_level"] = KNIFE_LEVEL
	_result["ammo_start"] = ammo_start
	player.bot_set_enabled(true)
	while is_instance_valid(world) and not bool(done.call()) and Time.get_ticks_msec() < limit \
			and not world.is_hunt_over() and not _done:
		var ids: PackedInt32Array = world.get_alive_boar_ids()
		if ids.is_empty() or not player.is_alive():
			await get_tree().process_frame
			continue
		var me: Vector3 = player.global_position
		var best: int = ids[0]
		var best_d: float = INF
		for id: int in ids:
			var p: Vector3 = world.get_boar_position(id)
			var d: float = Vector2(p.x - me.x, p.z - me.z).length()
			if d < best_d:
				best_d = d
				best = id
		var target: Vector3 = world.get_boar_zone_position(best, &"vital")
		if target == Vector3.INF:
			await get_tree().process_frame
			continue
		var away: Vector3 = Vector3(me.x - target.x, 0.0, me.z - target.z)
		away = away.normalized() if away.length() > 0.5 else Vector3.BACK
		var x: float = target.x + away.x * KNIFE_STAND_M
		var z: float = target.z + away.z * KNIFE_STAND_M
		player.bot_teleport(Vector3(x, world.get_height(x, z) + 0.05, z))
		await get_tree().physics_frame
		await get_tree().physics_frame
		var settle_until: int = Time.get_ticks_msec() + KNIFE_SETTLE_MS
		while Time.get_ticks_msec() < settle_until and not _done and is_instance_valid(world) and not world.is_hunt_over():
			var tv: Vector3 = world.get_boar_zone_position(best, &"vital")
			if tv != Vector3.INF:
				player.bot_look_at(tv)
			await get_tree().process_frame
		if not is_instance_valid(world) or world.is_hunt_over():
			break
		var tv2: Vector3 = world.get_boar_zone_position(best, &"vital")
		if tv2 != Vector3.INF:
			player.bot_look_at(tv2)
			if player.bot_knife():
				_swings += 1
			else:
				_swing_refused += 1
		await _sleep(KNIFE_COOLDOWN_MS)
	_result["knife_swings"] = _swings
	_result["knife_refused"] = _swing_refused
	if is_instance_valid(player):
		_result["ammo_end"] = player.get_ammo_in_mag()
	_log("knife swings %d (refused %d)" % [_swings, _swing_refused])


func _check_victory() -> void:
	super()
	var host: Dictionary = _read_json("result_host.json")
	var client: Dictionary = _read_json("result_client.json")
	if host.is_empty() or client.is_empty():
		return
	var client_ids: Array = client.get("credited", [])
	var swings: int = int(client.get("knife_swings", -1))
	_ok(int(client.get("knife_level", 0)) == KNIFE_LEVEL, "[knife] o cliente levou a faca nivel %d" % KNIFE_LEVEL)
	_ok(swings >= client_ids.size() and swings > 0,
		"[knife] o cliente golpeou %d vezes para abater %d javalis (cada abate pede ao menos 1 golpe)" % [swings, client_ids.size()])
	_ok(client_ids.size() >= CLIENT_KILLS, "[knife] o cliente abateu %d javalis so com a faca (minimo %d)" % [client_ids.size(), CLIENT_KILLS])
	_ok(int(client.get("ammo_start", -1)) >= 0 and int(client.get("ammo_end", -2)) == int(client.get("ammo_start", -1)),
		"[knife] o carregador do cliente nao mudou: nenhum tiro de arma (%s -> %s)" % [str(client.get("ammo_start")), str(client.get("ammo_end"))])
	_ok(int(client.get("shots_claimed", -1)) >= swings, "[knife] cada golpe fechou um C_SHOT no cliente (golpes %d, pedidos %s)"
		% [swings, str(client.get("shots_claimed"))])
	_ok(int(client.get("hits_claimed", -1)) >= client_ids.size(), "[knife] o cliente pediu ao menos %d acertos (%s)"
		% [client_ids.size(), str(client.get("hits_claimed"))])
	_ok(int(host.get("hits_accepted", -1)) >= client_ids.size(), "[knife] o anfitriao aceitou ao menos %d acertos (%s)"
		% [client_ids.size(), str(host.get("hits_accepted"))])
	_ok(int(host.get("hits_rejected", -1)) == 0, "[knife] o anfitriao nao rejeitou nenhum acerto (%s)" % str(host.get("hits_rejected")))
	# every kill the client scored is also a kill of the client on the host (same killer slot, as _check_victory proves
	# for the whole hunt): here only that the host really heard knife swings (shots_heard counts every C_SHOT)
	_ok(int(host.get("shots_heard", -1)) >= swings, "[knife] o anfitriao ouviu os %d golpes como disparos (%s)"
		% [swings, str(host.get("shots_heard"))])
