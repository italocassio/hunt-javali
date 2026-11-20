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
	"horde": "res://data/horde.json",
}
# file key -> list key inside the file
const LISTS: Dictionary = {
	"weapons": "weapons", "equipment": "items", "dogs": "dogs",
	"boars": "types", "maps": "maps", "gold": "packages",
}
const SHORT_NAME_MAX_CHARS: int = 9
const MINIMAP_COLOR_KEYS: Array[String] = [
	"grass", "crop_soil", "road", "wet", "water", "water_edge", "soy", "corn", "crop_row", "prop_default",
]
const ONBOARDING_FIELDS: Array[String] = [
	"max_hunts", "eval_interval_s", "opening_delay_s", "opening_duration_s", "hint_duration_s", "hint_gap_s",
	"queue_max", "medkit_health_below_pct", "boar_sighted_range_m", "boar_sighted_half_angle_deg", "drone_no_sighting_s",
	"objective_kills", "objective_crop_min_pct",
]

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


## data/horde.json as loaded ({} if missing; the cause is then in get_load_errors()).
func get_horde() -> Dictionary:
	return _raw.get("horde", {})


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
	_require_fields(_raw["game"].get("music", {}), ["track", "scenes", "volume_db", "fade_in_s", "fade_out_s"], "game.music")
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
	_validate_onboarding()
	_validate_horde()
	_validate_minimap()


# Minimap image parameters (docs/arquitetura.md §9.1 "minimap.*").
func _validate_minimap() -> void:
	var block: Variant = _raw["game"].get("minimap")
	if not (block is Dictionary):
		_errors.append("Data: game.json lacks 'minimap'")
		return
	var mm: Dictionary = block
	var image_px: Variant = mm.get("image_px")
	if not _is_int_in(image_px, 64, 512):
		_errors.append("Data: game.minimap.image_px must be an integer in 64-512")
	if not _is_int_in(mm.get("grid_stride"), 1, 2):
		_errors.append("Data: game.minimap.grid_stride must be 1 or 2")
	if not _is_int_in(mm.get("crop_row_px"), 0, 1000000):
		_errors.append("Data: game.minimap.crop_row_px must be an integer >= 0")
	var hs: Variant = mm.get("hillshade")
	if not (hs is Dictionary):
		_errors.append("Data: game.minimap.hillshade missing")
	else:
		var h: Dictionary = hs
		if not _is_num_in(h.get("azimuth_deg"), 0.0, 360.0):
			_errors.append("Data: game.minimap.hillshade.azimuth_deg must be in 0-360")
		var alt: Variant = h.get("altitude_deg")
		if not _is_num_in(alt, 0.0, 90.0) or float(alt) <= 0.0:
			_errors.append("Data: game.minimap.hillshade.altitude_deg must be in (0, 90]")
		if not _is_num_in(h.get("strength"), 0.0, 2.0):
			_errors.append("Data: game.minimap.hillshade.strength must be in 0-2")
		var lo: Variant = h.get("min")
		var hi: Variant = h.get("max")
		if not _is_num_in(lo, 0.0, INF) or float(lo) <= 0.0 or not _is_num_in(hi, 0.0, INF) or float(lo) > float(hi):
			_errors.append("Data: game.minimap.hillshade needs 0 < min <= max")
	var ht: Variant = mm.get("height_tint")
	for f: String in ["low", "high"]:
		var v: Variant = ht.get(f) if ht is Dictionary else null
		if not _is_num_in(v, 0.0, INF) or float(v) <= 0.0:
			_errors.append("Data: game.minimap.height_tint.%s must be a number > 0" % f)
	var colors: Variant = mm.get("colors")
	if not (colors is Dictionary):
		_errors.append("Data: game.minimap.colors missing")
	else:
		for k: String in MINIMAP_COLOR_KEYS:
			if not (colors as Dictionary).has(k):
				_errors.append("Data: game.minimap.colors lacks '%s'" % k)
		_check_color_values(colors, "colors")
	var pc: Variant = mm.get("prop_colors")
	if not (pc is Dictionary):
		_errors.append("Data: game.minimap.prop_colors missing")
	else:
		_check_color_values(pc, "prop_colors")
	var canopy: Variant = mm.get("canopy")
	if not (canopy is Dictionary):
		_errors.append("Data: game.minimap.canopy missing")
	else:
		for cid: Variant in (canopy as Dictionary):
			var entry: Variant = canopy[cid]
			if not (entry is Dictionary):
				_errors.append("Data: game.minimap.canopy.%s must be an object" % cid)
				continue
			var r: Variant = entry.get("radius_m")
			if not _is_num_in(r, 0.0, INF) or float(r) <= 0.0:
				_errors.append("Data: game.minimap.canopy.%s.radius_m must be > 0" % cid)
			var col: Variant = entry.get("color")
			if not (col is String) or not Color.html_is_valid(col):
				_errors.append("Data: game.minimap.canopy.%s.color is not a valid color" % cid)


func _check_color_values(dict: Dictionary, label: String) -> void:
	for k: Variant in dict:
		var v: Variant = dict[k]
		if not (v is String) or not Color.html_is_valid(v):
			_errors.append("Data: game.minimap.%s.%s is not a valid color" % [label, k])


func _is_num_in(v: Variant, lo: float, hi: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


func _is_int_in(v: Variant, lo: int, hi: int) -> bool:
	return _is_num_in(v, float(lo), float(hi)) and float(v) == floorf(float(v))


# Onboarding hints (docs/arquitetura.md §9.1) and the short_name of every equipment item (§9.3).
func _validate_onboarding() -> void:
	for entry: Variant in _raw["equipment"].get("items", []):
		if not (entry is Dictionary):
			continue
		var short_name: Variant = entry.get("short_name")
		if not (short_name is String) or (short_name as String).strip_edges() == "":
			_errors.append("Data: equipment '%s' lacks short_name" % entry.get("id", "?"))
		elif (short_name as String).length() > SHORT_NAME_MAX_CHARS:
			_errors.append("Data: equipment '%s' short_name is longer than %d characters" % [entry.get("id", "?"), SHORT_NAME_MAX_CHARS])
	var block: Variant = _raw["game"].get("onboarding")
	if not (block is Dictionary):
		_errors.append("Data: game.json lacks 'onboarding'")
		return
	var ob: Dictionary = block
	for f: String in ONBOARDING_FIELDS:
		var v: Variant = ob.get(f)
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) <= 0.0:
			_errors.append("Data: game.onboarding.%s must be a number > 0" % f)
	for f: String in ["max_hunts", "queue_max", "objective_kills"]:
		var v: Variant = ob.get(f)
		if (v is int or v is float) and float(v) != floorf(float(v)):
			_errors.append("Data: game.onboarding.%s must be an integer" % f)
	if float(ob.get("boar_sighted_half_angle_deg", 0.0)) > 90.0:
		_errors.append("Data: game.onboarding.boar_sighted_half_angle_deg must be <= 90")
	if float(ob.get("medkit_health_below_pct", 0.0)) > 100.0:
		_errors.append("Data: game.onboarding.medkit_health_below_pct must be <= 100")
	if float(ob.get("objective_crop_min_pct", 0.0)) > 100.0:
		_errors.append("Data: game.onboarding.objective_crop_min_pct must be <= 100")


# Horde mode rules (docs/horda.md §3.1). Skipped when the file could not be read (error already recorded).
func _validate_horde() -> void:
	var h: Dictionary = _raw.get("horde", {})
	if h.is_empty():
		return
	var typed: Dictionary = {
		"name": TYPE_STRING, "description": TYPE_STRING, "map_id": TYPE_STRING, "objective_prop_id": TYPE_STRING,
		"first_wave_delay_s": TYPE_FLOAT, "intermission_s": TYPE_FLOAT, "barn_drain_mult": TYPE_FLOAT,
		"eat_ring_m": TYPE_FLOAT, "to_barn_speed_frac": TYPE_FLOAT, "max_carcasses": TYPE_INT,
		"player_count_mult": TYPE_ARRAY, "extra_group_delay_s": TYPE_FLOAT, "kill_reward_mult": TYPE_FLOAT,
		"victory_bonus_money": TYPE_INT, "waves": TYPE_ARRAY,
	}
	var ok: bool = true
	for f: String in typed:
		if not h.has(f):
			_errors.append("Data: 'horde' lacks field '%s'" % f)
			ok = false
			continue
		var t: int = typed[f]
		var v: Variant = h[f]
		var good: bool = typeof(v) == t
		if t == TYPE_FLOAT or t == TYPE_INT:
			good = (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT)
			if good and t == TYPE_INT and float(v) != floorf(float(v)):
				good = false
		if not good:
			_errors.append("Data: horde.%s has the wrong type" % f)
			ok = false
	if not ok:
		return
	var map_id: String = str(h["map_id"])
	var map_def: Dictionary = _index.get("maps", {}).get(map_id, {})
	if map_def.is_empty():
		_errors.append("Data: horde.map_id '%s' is not in maps.json" % map_id)
	elif not bool(map_def.get("available", false)):
		_errors.append("Data: horde.map_id '%s' is not available" % map_id)
	if str(h["objective_prop_id"]) == "":
		_errors.append("Data: horde.objective_prop_id is empty")
	if float(h["first_wave_delay_s"]) < 0.0:
		_errors.append("Data: horde.first_wave_delay_s must be >= 0")
	if float(h["intermission_s"]) < 0.0:
		_errors.append("Data: horde.intermission_s must be >= 0")
	if float(h["barn_drain_mult"]) <= 0.0:
		_errors.append("Data: horde.barn_drain_mult must be > 0")
	if float(h["eat_ring_m"]) <= 0.0:
		_errors.append("Data: horde.eat_ring_m must be > 0")
	var speed_frac: float = float(h["to_barn_speed_frac"])
	if speed_frac <= 0.0 or speed_frac > 1.5:
		_errors.append("Data: horde.to_barn_speed_frac must be in (0, 1.5]")
	if int(h["max_carcasses"]) < 0:
		_errors.append("Data: horde.max_carcasses must be >= 0")
	if float(h["extra_group_delay_s"]) < 0.0:
		_errors.append("Data: horde.extra_group_delay_s must be >= 0")
	var reward_mult: float = float(h["kill_reward_mult"])
	if reward_mult <= 0.0 or reward_mult >= 1.0:
		_errors.append("Data: horde.kill_reward_mult must be in (0, 1)")
	if int(h["victory_bonus_money"]) < 0:
		_errors.append("Data: horde.victory_bonus_money must be >= 0")
	var max_players: int = int(_raw["net"].get("max_players", 0))
	var mults: Array = h["player_count_mult"]
	var max_mult: float = 1.0
	if mults.size() != max_players:
		_errors.append("Data: horde.player_count_mult needs %d entries (net.max_players)" % max_players)
	var prev: float = 1.0
	for m: Variant in mults:
		if not (typeof(m) == TYPE_FLOAT or typeof(m) == TYPE_INT):
			_errors.append("Data: horde.player_count_mult has a non-number entry")
			continue
		var mf: float = float(m)
		if mf < 1.0:
			_errors.append("Data: horde.player_count_mult entries must be >= 1.0")
		if mf < prev:
			_errors.append("Data: horde.player_count_mult must not decrease")
		prev = maxf(prev, mf)
		max_mult = maxf(max_mult, mf)
	var boar_types: Dictionary = _index.get("boars", {})
	var waves: Array = h["waves"]
	if waves.is_empty():
		_errors.append("Data: horde.waves must have at least one wave")
	var id_budget: int = 0
	for wi: int in waves.size():
		var wave: Variant = waves[wi]
		var groups: Array = (wave as Dictionary).get("groups", []) if wave is Dictionary else []
		if groups.is_empty():
			_errors.append("Data: horde wave %d has no groups" % (wi + 1))
		var wave_total: int = 0
		var has_alpha: bool = false
		for g: Variant in groups:
			if not (g is Dictionary):
				_errors.append("Data: horde wave %d has a malformed group" % (wi + 1))
				continue
			var gd: Dictionary = g
			var members: Array = gd.get("members", []) if gd.get("members", []) is Array else []
			if members.size() != 1 and (members.size() < 3 or members.size() > 6):
				_errors.append("Data: horde wave %d has a group of %d members (must be 1 or 3-6)" % [wi + 1, members.size()])
			for m: Variant in members:
				if not boar_types.has(str(m)):
					_errors.append("Data: horde wave %d references unknown boar type '%s'" % [wi + 1, m])
				if str(m) == "alpha":
					has_alpha = true
			if not gd.has("spawn_zone") or not (typeof(gd["spawn_zone"]) == TYPE_INT or typeof(gd["spawn_zone"]) == TYPE_FLOAT) or int(gd["spawn_zone"]) < 0:
				_errors.append("Data: horde wave %d has a group with invalid spawn_zone" % (wi + 1))
			if not gd.has("delay_s") or not (typeof(gd["delay_s"]) == TYPE_INT or typeof(gd["delay_s"]) == TYPE_FLOAT) or float(gd["delay_s"]) < 0.0:
				_errors.append("Data: horde wave %d has a group with invalid delay_s" % (wi + 1))
			wave_total += members.size()
		id_budget += ceili(float(wave_total) * max_mult)
		if wi == waves.size() - 1 and not has_alpha:
			_errors.append("Data: the last horde wave must contain an alpha")
	if id_budget > NetCodec.MAX_BOARS_PER_HUNT:
		_errors.append("Data: horde needs up to %d boar ids, above %d" % [id_budget, NetCodec.MAX_BOARS_PER_HUNT])


func _require_fields(entry: Dictionary, fields: Array, label: String) -> void:
	for f: String in fields:
		if not entry.has(f):
			_errors.append("Data: '%s' lacks field '%s'" % [label, f])
