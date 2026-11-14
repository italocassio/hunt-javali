extends Node
## Autoload "Data": read-only access to data/*.json. See docs/arquitetura.md §6.2 and §9.

const FILES: Dictionary = {
	"game": "res://data/game.json",
	"weapons": "res://data/weapons.json",
	"equipment": "res://data/equipment.json",
	"dogs": "res://data/dogs.json",
	"boars": "res://data/boars.json",
	"maps": "res://data/maps.json",
	"gold": "res://data/gold_packages.json",
	"pix": "res://data/pix_config.json",
	"net": "res://data/net.json",
}
# file key -> list key inside the file
const LISTS: Dictionary = {
	"weapons": "weapons", "equipment": "items", "dogs": "dogs",
	"boars": "types", "maps": "maps", "gold": "packages",
}

var _raw: Dictionary = {}
var _index: Dictionary = {}   # file key -> { id String -> Dictionary }
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	_raw.clear()
	_index.clear()
	_errors.clear()
	for key: String in FILES:
		var path: String = FILES[key]
		var text: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			_raw[key] = parsed
		else:
			_raw[key] = {}
			_errors.append("Data: cannot read %s" % path)
	for key: String in LISTS:
		var by_id: Dictionary = {}
		for entry: Variant in _raw[key].get(LISTS[key], []):
			if entry is Dictionary and entry.has("id"):
				by_id[String(entry["id"])] = entry
		_index[key] = by_id
	_validate()
	for e: String in _errors:
		push_error(e)


func get_load_errors() -> PackedStringArray:
	return _errors


func get_game() -> Dictionary:
	return _raw.get("game", {})


func get_net() -> Dictionary:
	return _raw.get("net", {})


func get_weapon(id: StringName) -> Dictionary:
	return _lookup("weapons", id)


func get_weapon_ids() -> Array[StringName]:
	return _ids("weapons")


func get_equipment(id: StringName) -> Dictionary:
	return _lookup("equipment", id)


func get_equipment_ids() -> Array[StringName]:
	return _ids("equipment")


func get_dog(id: StringName) -> Dictionary:
	return _lookup("dogs", id)


func get_dog_ids() -> Array[StringName]:
	return _ids("dogs")


func get_boar_type(id: StringName) -> Dictionary:
	return _lookup("boars", id)


func get_boar_type_ids() -> Array[StringName]:
	return _ids("boars")


func get_boar_rules() -> Dictionary:
	var rules: Dictionary = _raw.get("boars", {}).duplicate()
	rules.erase("types")
	return rules


func get_map(id: StringName) -> Dictionary:
	return _lookup("maps", id)


func get_map_ids() -> Array[StringName]:
	return _ids("maps")


func get_contract(map_id: StringName, index: int) -> Dictionary:
	var contracts: Array = get_map(map_id).get("contracts", [])
	if index < 0 or index >= contracts.size():
		push_error("Data: no contract %d in map %s" % [index, map_id])
		return {}
	return contracts[index]


func get_contract_count(map_id: StringName) -> int:
	return (get_map(map_id).get("contracts", []) as Array).size()


func get_gold_packages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in _raw.get("gold", {}).get("packages", []):
		if entry is Dictionary:
			out.append(entry)
	return out


func get_gold_package(id: StringName) -> Dictionary:
	return _lookup("gold", id)


func get_pix_config() -> Dictionary:
	return _raw.get("pix", {})


func get_item_def(id: StringName) -> Dictionary:
	for key: String in ["weapons", "equipment", "dogs"]:
		if _index.get(key, {}).has(String(id)):
			return _index[key][String(id)]
	return {}


func get_item_category(id: StringName) -> StringName:
	if _index.get("weapons", {}).has(String(id)):
		return &"weapon"
	if _index.get("equipment", {}).has(String(id)):
		return &"equipment"
	if _index.get("dogs", {}).has(String(id)):
		return &"dog"
	return &""


func _lookup(key: String, id: StringName) -> Dictionary:
	var by_id: Dictionary = _index.get(key, {})
	if not by_id.has(String(id)):
		push_error("Data: unknown id '%s' in %s" % [id, key])
		return {}
	return by_id[String(id)]


func _ids(key: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Variant in _raw.get(key, {}).get(LISTS[key], []):
		if entry is Dictionary and entry.has("id"):
			out.append(StringName(entry["id"]))
	return out


# --- Schema validation (adds to get_load_errors(); never changes the API) ---

func _validate() -> void:
	for key: String in FILES:
		if _raw[key].is_empty():
			continue
		if int(_raw[key].get("version", 0)) != 1:
			_errors.append("Data: %s has unsupported version" % FILES[key])
	for key: String in LISTS:
		var seen: Dictionary = {}
		for entry: Variant in _raw[key].get(LISTS[key], []):
			if not (entry is Dictionary) or not (entry as Dictionary).has("id"):
				_errors.append("Data: %s has an entry without id" % FILES[key])
				continue
			var id: String = str(entry["id"])
			if seen.has(id):
				_errors.append("Data: duplicate id '%s' in %s" % [id, FILES[key]])
			seen[id] = true
	var all_item_ids: Dictionary = {}
	for key: String in ["weapons", "equipment", "dogs"]:
		for entry: Variant in _raw[key].get(LISTS[key], []):
			if not (entry is Dictionary):
				continue
			var id: String = str(entry.get("id", ""))
			if all_item_ids.has(id):
				_errors.append("Data: item id '%s' used in more than one catalog" % id)
			all_item_ids[id] = true
			_require_fields(entry, ["name", "description", "price", "currency"], id)
			if not ["money", "gold"].has(str(entry.get("currency", ""))):
				_errors.append("Data: '%s' has invalid currency" % id)
			if float(entry.get("price", -1)) < 0.0:
				_errors.append("Data: '%s' has negative price" % id)
	for entry: Variant in _raw["equipment"].get("items", []):
		if entry is Dictionary and not ["passive", "active", "consumable"].has(str(entry.get("kind", ""))):
			_errors.append("Data: equipment '%s' has invalid kind" % entry.get("id", "?"))
	for entry: Variant in _raw["boars"].get("types", []):
		if entry is Dictionary:
			_require_fields(entry, ["weight_min_kg", "weight_max_kg", "health_per_kg", "value_per_kg", "aggression"], str(entry.get("id", "?")))
	_require_fields(_raw["net"], ["server_url", "dev_server_url", "max_players", "name_max_chars", "max_frame_bytes"], "net")
	for needed: String in ["economy", "loadout", "shop", "hunt", "player", "quality_presets", "coop"]:
		if not _raw["game"].has(needed):
			_errors.append("Data: game.json lacks '%s'" % needed)
	for wid: Variant in _raw["game"].get("economy", {}).get("start_weapons", []):
		if not _index.get("weapons", {}).has(str(wid)):
			_errors.append("Data: economy.start_weapons has unknown weapon '%s'" % wid)
	var max_alive: int = int(_raw["game"].get("hunt", {}).get("max_alive_boars", 0))
	var boar_types: Dictionary = _index.get("boars", {})
	for map_entry: Variant in _raw["maps"].get("maps", []):
		if not (map_entry is Dictionary):
			continue
		var contracts: Array = map_entry.get("contracts", [])
		if bool(map_entry.get("available", false)) and contracts.is_empty():
			_errors.append("Data: available map '%s' has no contracts" % map_entry.get("id", "?"))
		for ci: int in contracts.size():
			var c: Dictionary = contracts[ci]
			var label: String = "%s contract %d" % [map_entry.get("id", "?"), ci]
			_require_fields(c, ["name", "reward_mult", "bonus_money", "crop_drain_mult", "groups"], label)
			var total: int = 0
			var groups: Array = c.get("groups", [])
			if groups.is_empty():
				_errors.append("Data: %s has no groups" % label)
			for g: Variant in groups:
				var members: Array = g.get("members", []) if g is Dictionary else []
				if members.size() != 1 and (members.size() < 3 or members.size() > 6):
					_errors.append("Data: %s has a group of %d members (must be 1 or 3-6)" % [label, members.size()])
				for m: Variant in members:
					if not boar_types.has(str(m)):
						_errors.append("Data: %s references unknown boar type '%s'" % [label, m])
				total += members.size()
			if max_alive > 0 and total > max_alive:
				_errors.append("Data: %s has %d boars, above max_alive_boars" % [label, total])
	for pkg: Dictionary in get_gold_packages():
		_require_fields(pkg, ["name", "price_brl", "gold"], str(pkg.get("id", "?")))
	_require_fields(_raw["pix"], ["gateway", "pix_key", "merchant_name", "merchant_city", "redeem_secret"], "pix_config")


func _require_fields(entry: Dictionary, fields: Array, label: String) -> void:
	for f: String in fields:
		if not entry.has(f):
			_errors.append("Data: '%s' lacks field '%s'" % [label, f])
