class_name SaveService
extends RefCounted
## Save file I/O, version migration and sanitizing (docs/arquitetura.md §10). Static, no autoload state
## besides read-only Data lookups. Never throws on bad input.

const FORMAT_NAME: String = "cacada-ao-javali-save"
const CURRENT_VERSION: int = 2
const DRONE_ID: String = "scout_drone"   # item granted by the v1 -> v2 migration (amount comes from economy.start_items)
const MAX_CODES: int = 500

const DEFAULT_SETTINGS: Dictionary = {
	"mouse_sensitivity": 1.0,
	"touch_sensitivity": 1.0,
	"invert_y": false,
	"volume_master": 1.0,
	"volume_sfx": 1.0,
	"volume_ambience": 0.7,
	"quality": "auto",
	"touch_controls": "auto",
	"show_fps": false,
}
const SENSITIVITY_RANGE: Vector2 = Vector2(0.1, 3.0)
const QUALITY_VALUES: Array[String] = ["auto", "low", "medium", "high"]
const TOUCH_VALUES: Array[String] = ["auto", "on", "off"]
const STAT_KEYS: Array[String] = ["hunts_played", "hunts_won", "boars_killed", "money_earned_total"]


static func backup_path(path: String) -> String:
	return path.get_basename() + ".bak.json"


## Writes data as JSON. Keeps the previous valid file as backup, re-reads and verifies. false on any failure.
static func write(path: String, data: Dictionary) -> bool:
	var text: String = JSON.stringify(data, "\t")
	if FileAccess.file_exists(path) and not read(path).is_empty():
		var err: int = DirAccess.copy_absolute(path, backup_path(path))
		if err != OK:
			push_warning("SaveService: could not back up %s (error %d)" % [path, err])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveService: cannot open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.flush()
	file.close()
	# Verify the file parses back (floats/ints may print differently, so no text comparison).
	var back: Dictionary = read(path)
	return back.size() == data.size()


## Parsed save dictionary, or {} if the file is missing, unreadable or not a JSON object.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {}
	var json: JSON = JSON.new()
	if json.parse(text) != OK:   # parse() reports through its return code, unlike parse_string (which logs an error)
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


## Brings old saves up to CURRENT_VERSION (chain n -> n+1). Newer versions are returned as they are.
static func migrate(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var v: Variant = out.get("version", 1)
	var version: int = int(v) if (v is int or v is float) and is_finite(float(v)) else 1
	if version < 1:
		version = 1
	while version < CURRENT_VERSION:
		out = _migrate_step(out, version)
		version += 1
		out["version"] = version
	out["version"] = maxi(version, _int(out.get("version"), version))
	return out


## Returns a complete, valid save built from whatever was in data (wrong types, missing keys, unknown ids).
static func sanitize(data: Dictionary) -> Dictionary:
	var economy: Dictionary = Data.get_game().get("economy", {})
	var wallet: Dictionary = _dict(data.get("wallet"))
	var inv_block: Dictionary = _dict(data.get("inventory"))
	var load_block: Dictionary = _dict(data.get("loadout"))
	var max_consumable: int = maxi(1, int(Data.get_game().get("shop", {}).get("max_consumable_owned", 9)))
	var weapon_slots: int = maxi(1, int(Data.get_game().get("loadout", {}).get("weapon_slots", 2)))
	var item_slots: int = maxi(0, int(Data.get_game().get("loadout", {}).get("item_slots", 3)))

	var out: Dictionary = {
		"format": FORMAT_NAME,
		"version": maxi(CURRENT_VERSION, _int(data.get("version"), CURRENT_VERSION)),
		"saved_at_unix": maxi(0, _int(data.get("saved_at_unix"), 0)),
	}
	out["wallet"] = {
		"money": clampi(_int(wallet.get("money"), int(economy.get("start_money", 0))), 0, Wallet.MAX_BALANCE),
		"gold": clampi(_int(wallet.get("gold"), int(economy.get("start_gold", 0))), 0, Wallet.MAX_BALANCE),
	}

	# Inventory
	var weapons: Array[String] = _id_list(inv_block.get("weapons"), &"weapon")
	for start_weapon: Variant in economy.get("start_weapons", []):
		if not weapons.has(str(start_weapon)) and Data.get_item_category(StringName(str(start_weapon))) == &"weapon":
			weapons.insert(0, str(start_weapon))
	var dogs: Array[String] = _id_list(inv_block.get("dogs"), &"dog")
	var items: Dictionary = {}
	var raw_items: Variant = inv_block.get("items")
	if raw_items is Dictionary:
		for key: Variant in raw_items:
			var id: StringName = StringName(str(key))
			if Data.get_item_category(id) != &"equipment":
				continue
			var n: int = _int(raw_items[key], 0)
			if n <= 0:
				continue
			var kind: String = str(Data.get_equipment(id).get("kind", ""))
			items[String(id)] = clampi(n, 1, max_consumable) if kind == "consumable" else 1
	elif not inv_block.has("items") and not data.has("inventory"):
		for key: Variant in _dict(economy.get("start_items")):
			if Data.get_item_category(StringName(str(key))) == &"equipment":
				items[str(key)] = maxi(1, _int(economy["start_items"][key], 1))
	out["inventory"] = {"weapons": weapons, "dogs": dogs, "items": items}

	# Loadout
	var lw: Array[String] = []
	var raw_lw: Variant = load_block.get("weapons")
	if raw_lw is Array:
		for w: Variant in raw_lw:
			var wid: String = str(w) if w is String else ""
			if wid != "" and (not weapons.has(wid) or lw.has(wid)):
				wid = ""
			lw.append(wid)
	while lw.size() < weapon_slots:
		lw.append("")
	lw.resize(weapon_slots)
	if lw[0] == "":
		lw[0] = "carbine_22" if weapons.has("carbine_22") else String(weapons[0] if not weapons.is_empty() else "carbine_22")
		if lw.count(lw[0]) > 1:
			for i: int in range(1, lw.size()):
				if lw[i] == lw[0]:
					lw[i] = ""
	var ldog: String = str(load_block.get("dog")) if load_block.get("dog") is String else ""
	if not dogs.has(ldog):
		ldog = ""
	var litems: Array[String] = []
	var raw_li: Variant = load_block.get("items")
	if raw_li is Array:
		for it: Variant in raw_li:
			var iid: String = str(it) if it is String else ""
			if items.has(iid) and not litems.has(iid) and litems.size() < item_slots:
				litems.append(iid)
	elif not data.has("loadout"):
		for iid: String in items:
			if litems.size() < item_slots:
				litems.append(iid)
	out["loadout"] = {"weapons": lw, "dog": ldog, "items": litems}

	# Progression
	out["progression"] = Progression.from_dict(_dict(data.get("progression"))).to_dict()

	# Stats
	var stats_in: Dictionary = _dict(data.get("stats"))
	var stats: Dictionary = {}
	for key: String in STAT_KEYS:
		stats[key] = maxi(0, _int(stats_in.get(key), 0))
	stats["heaviest_kg"] = maxf(0.0, _float(stats_in.get("heaviest_kg"), 0.0))
	out["stats"] = stats

	# Redeemed codes
	var codes: Array = []
	var raw_codes: Variant = data.get("redeemed_codes")
	if raw_codes is Array:
		for c: Variant in raw_codes:
			if c is String and (c as String) != "" and not codes.has(c) and codes.size() < MAX_CODES:
				codes.append(c)
	out["redeemed_codes"] = codes

	# Settings
	var settings_in: Dictionary = _dict(data.get("settings"))
	var settings: Dictionary = {}
	for key: String in DEFAULT_SETTINGS:
		settings[key] = sanitize_setting(key, settings_in.get(key))
	out["settings"] = settings
	return out


## A fresh profile built from data/game.json (economy.*).
static func new_save() -> Dictionary:
	return sanitize({})


static func default_settings() -> Dictionary:
	return DEFAULT_SETTINGS.duplicate()


## Validates one setting value; wrong type or unknown value gives the default. Unknown key gives null.
static func sanitize_setting(key: String, value: Variant) -> Variant:
	if not DEFAULT_SETTINGS.has(key):
		return null
	var default_value: Variant = DEFAULT_SETTINGS[key]
	match key:
		"mouse_sensitivity", "touch_sensitivity":
			if (value is float or value is int) and is_finite(float(value)):
				return clampf(float(value), SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
		"volume_master", "volume_sfx", "volume_ambience":
			if (value is float or value is int) and is_finite(float(value)):
				return clampf(float(value), 0.0, 1.0)
		"quality":
			if value is String and QUALITY_VALUES.has(value):
				return value
		"touch_controls":
			if value is String and TOUCH_VALUES.has(value):
				return value
		"invert_y", "show_fps":
			if value is bool:
				return value
	return default_value


static func _migrate_step(data: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		1:
			_migrate_v1_to_v2(data)
	return data


## v1 -> v2: the scout drone became a basic item; every existing player gets the free starting drones once.
## Without an inventory.items dictionary nothing is created, so sanitize applies economy.start_items as usual.
static func _migrate_v1_to_v2(data: Dictionary) -> void:
	var economy: Dictionary = _dict(Data.get_game().get("economy"))
	var grant: int = maxi(0, _int(_dict(economy.get("start_items")).get(DRONE_ID), 0))
	if grant <= 0:
		return
	var inv: Variant = data.get("inventory")
	if inv is Dictionary and (inv as Dictionary).get("items") is Dictionary:
		var items: Dictionary = (inv as Dictionary)["items"]
		items[DRONE_ID] = clampi(maxi(0, _int(items.get(DRONE_ID), 0)) + grant, 0, Wallet.MAX_BALANCE)
	var load_block: Variant = data.get("loadout")
	if load_block is Dictionary and (load_block as Dictionary).get("items") is Array:
		var equipped: Array = (load_block as Dictionary)["items"]
		var item_slots: int = maxi(0, int(Data.get_game().get("loadout", {}).get("item_slots", 3)))
		if not equipped.has(DRONE_ID) and equipped.size() < item_slots:
			equipped.append(DRONE_ID)


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _int(v: Variant, fallback: int) -> int:
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(clampf(v, -1.0e12, 1.0e12))
	return fallback


static func _float(v: Variant, fallback: float) -> float:
	if (v is float or v is int) and is_finite(float(v)):
		return float(v)
	return fallback


static func _id_list(v: Variant, category: StringName) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for e: Variant in v:
			if e is String and Data.get_item_category(StringName(e)) == category and not out.has(e):
				out.append(e)
	return out
