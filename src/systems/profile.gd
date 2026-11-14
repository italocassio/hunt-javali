extends Node
## Autoload "Profile": wallet, inventory, loadout, progression, settings, economy rules and save.
## Facade over Wallet/Inventory/Progression/Shop/RewardCalculator/SaveService.
## See docs/arquitetura.md §6.3, §8.7 and §10.

const SAVE_VERSION: int = SaveService.CURRENT_VERSION
const DEFAULT_SAVE_PATH: String = "user://save.json"

var _save_path: String = DEFAULT_SAVE_PATH
var _wallet: Wallet = Wallet.new()
var _inventory: Inventory = Inventory.new()
var _progression: Progression = Progression.new()
var _stats: Dictionary = {}
var _redeemed: Array[String] = []
var _settings: Dictionary = SaveService.default_settings()
var _last_applied: HuntResult = null
var _flush_pending: bool = false


func _ready() -> void:
	load_or_create()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_flush_settings()


func set_save_path(path: String) -> void:
	_save_path = path


## Loads save.json, then save.bak.json, then a new profile. Never fails.
func load_or_create() -> void:
	var data: Dictionary = SaveService.read(_save_path)
	var needs_save: bool = false
	if data.is_empty():
		var existed: bool = FileAccess.file_exists(_save_path)
		needs_save = true
		data = SaveService.read(SaveService.backup_path(_save_path))
		if not data.is_empty():
			push_warning("Profile: save unreadable, restored from backup.")
		else:
			if existed:
				push_warning("Profile: save corrupted and no backup, starting a new profile.")
			data = SaveService.new_save()
	var migrated: Dictionary = SaveService.migrate(data)
	# The stored version may be missing or of any type in a damaged save: never convert it blindly.
	var raw_version: Variant = data.get("version")
	var loaded_version: int = int(raw_version) if (raw_version is int or raw_version is float) and is_finite(float(raw_version)) else 0
	if int(migrated["version"]) != loaded_version:
		needs_save = true   # persist the migrated save right away
	_apply_dict(SaveService.sanitize(migrated))
	if needs_save:
		save()


func save() -> bool:
	_flush_pending = false
	return SaveService.write(_save_path, _to_dict())


## New profile; keeps settings; saves.
func reset_progress() -> void:
	var keep: Dictionary = _settings.duplicate()
	var fresh: Dictionary = SaveService.new_save()
	fresh["settings"] = keep
	_apply_dict(SaveService.sanitize(fresh))
	_last_applied = null
	save()
	_emit_all()


# --- Wallet ---

func get_money() -> int:
	return _wallet.money


func get_gold() -> int:
	return _wallet.gold


func add_money(amount: int) -> void:
	_wallet.add(amount, Ids.MONEY)
	GameEvents.wallet_changed.emit(_wallet.money, _wallet.gold)


func add_gold(amount: int) -> void:
	_wallet.add(amount, Ids.GOLD)
	GameEvents.wallet_changed.emit(_wallet.money, _wallet.gold)


# --- Inventory / shop ---

func owns(item_id: StringName) -> bool:
	return _inventory.owns(item_id)


func get_item_count(item_id: StringName) -> int:
	return _inventory.get_count(item_id)


func can_buy(item_id: StringName) -> StringName:
	return Shop.check(item_id, _wallet, _inventory)


func buy(item_id: StringName) -> StringName:
	var code: StringName = Shop.buy(item_id, _wallet, _inventory)
	if code != &"ok":
		return code
	_auto_equip(item_id)
	save()
	GameEvents.wallet_changed.emit(_wallet.money, _wallet.gold)
	GameEvents.inventory_changed.emit()
	GameEvents.loadout_changed.emit()
	return code


# --- Loadout ---

func get_loadout_weapons() -> Array[StringName]:
	var out: Array[StringName] = [&"", &""]
	for i: int in mini(2, _inventory.loadout_weapons.size()):
		out[i] = _inventory.loadout_weapons[i]
	return out


func set_loadout_weapon(slot: int, weapon_id: StringName) -> bool:
	var slots: int = int(Data.get_game().get("loadout", {}).get("weapon_slots", 2))
	if slot < 0 or slot >= slots or slot >= _inventory.loadout_weapons.size():
		return false
	if weapon_id == &"":
		if slot == 0:
			return false
	elif Data.get_item_category(weapon_id) != &"weapon" or not _inventory.owned_weapons.has(weapon_id):
		return false
	var current: Array[StringName] = _inventory.loadout_weapons
	if weapon_id != &"":
		for other: int in current.size():
			if other != slot and current[other] == weapon_id:
				if current[slot] == &"" and other == 0:
					return false
				current[other] = current[slot]   # swap, so a weapon never sits in two slots
	current[slot] = weapon_id
	save()
	GameEvents.loadout_changed.emit()
	return true


func get_loadout_dog() -> StringName:
	return _inventory.loadout_dog


func set_loadout_dog(dog_id: StringName) -> bool:
	if dog_id != &"" and not _inventory.owned_dogs.has(dog_id):
		return false
	_inventory.loadout_dog = dog_id
	save()
	GameEvents.loadout_changed.emit()
	return true


func get_loadout_items() -> Array[StringName]:
	return _inventory.loadout_items.duplicate()


func set_loadout_items(item_ids: Array[StringName]) -> bool:
	var slots: int = int(Data.get_game().get("loadout", {}).get("item_slots", 3))
	if item_ids.size() > slots:
		return false
	var seen: Array[StringName] = []
	for id: StringName in item_ids:
		if Data.get_item_category(id) != &"equipment" or not _inventory.owns(id) or seen.has(id):
			return false
		seen.append(id)
	_inventory.loadout_items = seen
	save()
	GameEvents.loadout_changed.emit()
	return true


# --- Progression ---

func get_unlocked_contract_count(map_id: StringName) -> int:
	return _progression.unlocked_count(map_id)


func is_contract_unlocked(map_id: StringName, index: int) -> bool:
	return _progression.is_unlocked(map_id, index)


func is_contract_completed(map_id: StringName, index: int) -> bool:
	return _progression.is_completed(map_id, index)


func get_stats() -> Dictionary:
	return _stats.duplicate()


## Best crop health % of a won contract (-1 if never won). Extra to the contract, for the UI.
func get_best_crop_pct(map_id: StringName, index: int) -> float:
	return _progression.best_crop_pct(map_id, index)


# --- Hunt bridge ---

func build_hunt_request(map_id: StringName, contract_index: int) -> HuntRequest:
	var r: HuntRequest = HuntRequest.new()
	r.map_id = map_id
	r.contract_index = contract_index
	var weapons: Array[StringName] = []
	for id: StringName in _inventory.loadout_weapons:
		if id != &"" and _inventory.owned_weapons.has(id) and not weapons.has(id):
			weapons.append(id)
	if weapons.is_empty():
		weapons.append(Ids.W_CARBINE_22)
	r.weapon_ids = weapons
	r.dog_id = _inventory.loadout_dog if _inventory.owned_dogs.has(_inventory.loadout_dog) else &""
	var item_ids: Array[StringName] = []
	var counts: Dictionary = {}
	for id: StringName in _inventory.loadout_items:
		var owned: int = _inventory.get_count(id)
		if owned <= 0 or item_ids.has(id):
			continue
		var def: Dictionary = Data.get_equipment(id)
		if def.get("kind", "") == "consumable":
			counts[id] = mini(owned, maxi(1, int(def.get("max_per_hunt", 1))))
		else:
			counts[id] = 1
		item_ids.append(id)
	r.item_ids = item_ids
	r.item_counts = counts
	return r


func kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, map_id: StringName, contract_index: int) -> int:
	if not Data.get_boar_type_ids().has(type_id):
		return 0
	return RewardCalculator.kill_reward(Data.get_boar_type(type_id), Data.get_boar_rules(), weight_kg, killing_zone, one_shot, _contract(map_id, contract_index))


func contract_bonus(map_id: StringName, contract_index: int, crop_health_pct: float) -> int:
	return RewardCalculator.contract_bonus(_contract(map_id, contract_index), crop_health_pct)


## The only place that credits a hunt. Ignores the same result object if applied twice.
func apply_hunt_result(result: HuntResult) -> void:
	if result == null or result == _last_applied:
		return
	_last_applied = result
	_wallet.add(maxi(0, result.total_money), Ids.MONEY)
	for id: Variant in result.consumables_used:
		var item_id: StringName = StringName(str(id))
		var n: int = mini(int(result.consumables_used[id]), int(_inventory.items.get(item_id, 0)))
		if n > 0:
			_inventory.remove_item(item_id, n)
	# Network hunts: a win on a contract the player had not unlocked pays but does not advance progression.
	var won: bool = result.is_victory()
	var progressed: bool = won and result.counts_for_progression
	if progressed:
		_progression.mark_won(result.map_id, result.contract_index, result.crop_health_pct)
	if won:
		_stats["hunts_won"] = int(_stats.get("hunts_won", 0)) + 1
	_stats["hunts_played"] = int(_stats.get("hunts_played", 0)) + 1
	_stats["boars_killed"] = int(_stats.get("boars_killed", 0)) + result.kills.size()
	_stats["money_earned_total"] = int(_stats.get("money_earned_total", 0)) + maxi(0, result.total_money)
	for k: KillInfo in result.kills:
		_stats["heaviest_kg"] = maxf(float(_stats.get("heaviest_kg", 0.0)), k.weight_kg)
	save()
	GameEvents.wallet_changed.emit(_wallet.money, _wallet.gold)
	GameEvents.inventory_changed.emit()
	GameEvents.loadout_changed.emit()
	if progressed:
		GameEvents.progression_changed.emit()


# --- Donations ---

func is_code_redeemed(code: String) -> bool:
	return _redeemed.has(RedeemCode.normalize(code))


func mark_code_redeemed(code: String) -> void:
	var normalized: String = RedeemCode.normalize(code)
	if normalized != "" and not _redeemed.has(normalized):
		_redeemed.append(normalized)


# --- Settings ---

func get_setting(key: String) -> Variant:
	return _settings.get(key, null)


func set_setting(key: String, value: Variant) -> void:
	if not SaveService.DEFAULT_SETTINGS.has(key):
		push_warning("Profile.set_setting: unknown key '%s'" % key)
		return
	var clean: Variant = SaveService.sanitize_setting(key, value)
	if typeof(clean) != typeof(value) or clean != value:
		push_warning("Profile.set_setting: invalid value for '%s', using %s" % [key, str(clean)])
	_settings[key] = clean
	GameEvents.settings_changed.emit(key, clean)
	# Sliders fire many changes per second: write once at the end of the frame.
	if not _flush_pending:
		_flush_pending = true
		_flush_settings.call_deferred()


# --- Internals ---

func _flush_settings() -> void:
	if _flush_pending:
		save()


func _contract(map_id: StringName, index: int) -> Dictionary:
	if not Data.get_map_ids().has(map_id):
		return {}
	return Data.get_contract(map_id, index)


func _auto_equip(item_id: StringName) -> void:
	var inv: Inventory = _inventory
	match Data.get_item_category(item_id):
		&"weapon":
			if inv.loadout_weapons.size() > 1 and inv.loadout_weapons[1] == &"" and not inv.loadout_weapons.has(item_id):
				inv.loadout_weapons[1] = item_id
		&"dog":
			if inv.loadout_dog == &"":
				inv.loadout_dog = item_id
		&"equipment":
			var slots: int = int(Data.get_game().get("loadout", {}).get("item_slots", 3))
			if not inv.loadout_items.has(item_id) and inv.loadout_items.size() < slots:
				inv.loadout_items.append(item_id)


func _to_dict() -> Dictionary:
	var out: Dictionary = {
		"format": SaveService.FORMAT_NAME,
		"version": SAVE_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"wallet": _wallet.to_dict(),
		"progression": _progression.to_dict(),
		"stats": _stats.duplicate(),
		"redeemed_codes": _redeemed.duplicate(),
		"settings": _settings.duplicate(),
	}
	out.merge(_inventory.to_dict())
	return out


func _apply_dict(d: Dictionary) -> void:
	_wallet = Wallet.from_dict(d["wallet"])
	_inventory = Inventory.from_dict(d)
	_progression = Progression.from_dict(d["progression"])
	_stats = (d["stats"] as Dictionary).duplicate()
	_redeemed.clear()
	for c: Variant in d["redeemed_codes"]:
		_redeemed.append(str(c))
	_settings = (d["settings"] as Dictionary).duplicate()


func _emit_all() -> void:
	GameEvents.wallet_changed.emit(_wallet.money, _wallet.gold)
	GameEvents.inventory_changed.emit()
	GameEvents.loadout_changed.emit()
	GameEvents.progression_changed.emit()
