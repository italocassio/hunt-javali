extends RefCounted
## Signatures copied from docs/arquitetura.md sections 5 and 6, plus the comparison helpers.
## Used by tests/check_scripts.gd (R3 in section 13.3: drift of signatures).

const GAME_EVENTS_SIGNALS: Array[String] = [
	"hunt_started(request: HuntRequest)",
	"hunt_ended(result: HuntResult)",
	"hunt_paused_changed(paused: bool)",
	"hunt_abandon_requested()",
	"shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)",
	"player_damaged(amount: float, source_position: Vector3, health_after: float)",
	"player_healed(amount: float, health_after: float)",
	"player_died()",
	"item_used(item_id: StringName, position: Vector3)",
	"thermal_vision_changed(active: bool)",
	"dog_command_requested()",
	"boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)",
	"boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)",
	"boar_state_changed(boar_id: int, state: StringName)",
	"boar_killed(kill: KillInfo)",
	"boar_counts_changed(killed: int, total: int)",
	"crop_health_changed(pct: float)",
	"crop_under_attack(active: bool)",
	"bait_placed(position: Vector3, duration_s: float)",
	"dog_state_changed(state: StringName)",
	"dog_health_changed(pct: float)",
	"dog_marked_boar(position: Vector3, duration_s: float)",
	"dog_command_executed(command: StringName)",
	"hud_message_requested(text: String, duration_s: float)",
	"wallet_changed(money: int, gold: int)",
	"inventory_changed()",
	"loadout_changed()",
	"progression_changed()",
	"settings_changed(key: String, value: Variant)",
	"touch_mode_changed(is_touch: bool)",
]

const DATA_METHODS: Array[String] = [
	"reload() -> void",
	"get_load_errors() -> PackedStringArray",
	"get_game() -> Dictionary",
	"get_weapon(id: StringName) -> Dictionary",
	"get_weapon_ids() -> Array",
	"get_equipment(id: StringName) -> Dictionary",
	"get_equipment_ids() -> Array",
	"get_dog(id: StringName) -> Dictionary",
	"get_dog_ids() -> Array",
	"get_boar_type(id: StringName) -> Dictionary",
	"get_boar_type_ids() -> Array",
	"get_boar_rules() -> Dictionary",
	"get_map(id: StringName) -> Dictionary",
	"get_map_ids() -> Array",
	"get_contract(map_id: StringName, index: int) -> Dictionary",
	"get_contract_count(map_id: StringName) -> int",
	"get_gold_packages() -> Array",
	"get_gold_package(id: StringName) -> Dictionary",
	"get_pix_config() -> Dictionary",
	"get_item_def(id: StringName) -> Dictionary",
	"get_item_category(id: StringName) -> StringName",
]

const PROFILE_METHODS: Array[String] = [
	"set_save_path(path: String) -> void",
	"load_or_create() -> void",
	"save() -> bool",
	"reset_progress() -> void",
	"get_money() -> int",
	"get_gold() -> int",
	"add_money(amount: int) -> void",
	"add_gold(amount: int) -> void",
	"owns(item_id: StringName) -> bool",
	"get_item_count(item_id: StringName) -> int",
	"can_buy(item_id: StringName) -> StringName",
	"buy(item_id: StringName) -> StringName",
	"get_loadout_weapons() -> Array",
	"set_loadout_weapon(slot: int, weapon_id: StringName) -> bool",
	"get_loadout_dog() -> StringName",
	"set_loadout_dog(dog_id: StringName) -> bool",
	"get_loadout_items() -> Array",
	"set_loadout_items(item_ids: Array) -> bool",
	"get_unlocked_contract_count(map_id: StringName) -> int",
	"is_contract_unlocked(map_id: StringName, index: int) -> bool",
	"is_contract_completed(map_id: StringName, index: int) -> bool",
	"get_stats() -> Dictionary",
	"build_hunt_request(map_id: StringName, contract_index: int) -> HuntRequest",
	"kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, map_id: StringName, contract_index: int) -> int",
	"contract_bonus(map_id: StringName, contract_index: int, crop_health_pct: float) -> int",
	"apply_hunt_result(result: HuntResult) -> void",
	"is_code_redeemed(code: String) -> bool",
	"mark_code_redeemed(code: String) -> void",
	"get_setting(key: String) -> Variant",
	"set_setting(key: String, value: Variant) -> void",
]

const INPUT_SETUP_METHODS: Array[String] = [
	"register_actions() -> void",
	"is_touch_mode() -> bool",
	"set_touch_override(mode: String) -> void",
	"release_all_actions() -> void",
]

const SFX_METHODS: Array[String] = [
	"has_sound(id: StringName) -> bool",
	"play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void",
	"play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void",
	"play_loop(id: StringName, volume_db: float = 0.0) -> void",
	"stop_loop(id: StringName) -> void",
	"stop_all_loops() -> void",
	"unlock_audio() -> void",
	"set_bus_volume(bus: StringName, linear: float) -> void",
]

const ROUTER_METHODS: Array[String] = [
	"goto(scene_path: String) -> void",
	"get_current_scene_path() -> String",
	"set_pending_request(request: HuntRequest) -> void",
	"get_pending_request() -> HuntRequest",
	"start_hunt(request: HuntRequest) -> void",
	"finish_hunt(result: HuntResult) -> void",
]

## autoload name -> [script path, methods, property names]
const AUTOLOADS: Dictionary = {
	"GameEvents": ["res://src/core/game_events.gd"],
	"Data": ["res://src/systems/data_registry.gd"],
	"Profile": ["res://src/systems/profile.gd"],
	"InputSetup": ["res://src/input/input_setup.gd"],
	"Sfx": ["res://assets/audio/sfx_library.gd"],
	"Router": ["res://src/systems/router.gd"],
}
const AUTOLOAD_ORDER: Array[String] = ["GameEvents", "Data", "Profile", "InputSetup", "Sfx", "Router"]

const ROUTER_PROPERTIES: Array[String] = ["selected_map_id", "selected_contract_index", "last_result"]
const PROFILE_CONSTANTS: Array[String] = ["SAVE_VERSION", "DEFAULT_SAVE_PATH"]
const INPUT_CONSTANTS: Array[String] = ["ACTIONS"]

## Public classes of packages A, B and game-systems (6.8, 6.9, 6.10).
## name -> {path, base (script class name or native class), methods, signals, props}
const CLASSES: Array[Dictionary] = [
	# --- Package A ---
	{"name": "Player", "path": "res://src/player/player.gd", "base": "PlayerBase", "pkg": "A"},
	{"name": "Weapon", "path": "res://src/weapons/weapon.gd", "base": "Node", "pkg": "A"},
	{"name": "WeaponHolder", "path": "res://src/weapons/weapon_holder.gd", "base": "Node3D", "pkg": "A"},
	{"name": "Hitscan", "path": "res://src/weapons/hitscan.gd", "base": "RefCounted", "pkg": "A",
		"methods": ["cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range_m: float, exclude: Array) -> Dictionary"]},
	{"name": "ItemBelt", "path": "res://src/player/item_belt.gd", "base": "Node", "pkg": "A"},
	{"name": "Hud", "path": "res://src/hud/hud.gd", "base": "CanvasLayer", "pkg": "A",
		"methods": ["bind(player: PlayerBase, world: HuntWorld) -> void"]},
	{"name": "PauseOverlay", "path": "res://src/hud/pause_overlay.gd", "base": "CanvasLayer", "pkg": "A"},
	{"name": "TouchControls", "path": "res://src/hud/touch/touch_controls.gd", "base": "CanvasLayer", "pkg": "A"},
	{"name": "TouchJoystick", "path": "res://src/hud/touch/virtual_joystick.gd", "base": "Control", "pkg": "A"},
	# --- Package B ---
	{"name": "HuntController", "path": "res://src/hunt/hunt_controller.gd", "base": "HuntWorld", "pkg": "B",
		"props": ["route_on_finish"]},
	{"name": "BoarSpawner", "path": "res://src/hunt/boar_spawner.gd", "base": "Node", "pkg": "B"},
	{"name": "FallbackPlayer", "path": "res://src/hunt/debug/fallback_player.gd", "base": "PlayerBase", "pkg": "B"},
	{"name": "MapRoot", "path": "res://src/world/map_root.gd", "base": "Node3D", "pkg": "B",
		"props": ["map_size_m", "grid_resolution", "terrain_seed", "height_amplitude_m", "base_flora"]},
	{"name": "Heightmap", "path": "res://src/world/heightmap.gd", "base": "RefCounted", "pkg": "B",
		"methods": ["get_height(x: float, z: float) -> float", "get_normal(x: float, z: float) -> Vector3"]},
	{"name": "Terrain", "path": "res://src/world/terrain.gd", "base": "Node3D", "pkg": "B"},
	{"name": "CropField", "path": "res://src/world/crop_field.gd", "base": "Marker3D", "pkg": "B",
		"props": ["size_m", "crop"]},
	{"name": "CropManager", "path": "res://src/world/crop_manager.gd", "base": "Node3D", "pkg": "B"},
	{"name": "PropSpawn", "path": "res://src/world/prop_spawn.gd", "base": "Marker3D", "pkg": "B",
		"props": ["prop_id", "collision_size", "footprint_radius_m"]},
	{"name": "WaterBody", "path": "res://src/world/water_body.gd", "base": "Marker3D", "pkg": "B",
		"props": ["radius_m", "depth_m"]},
	{"name": "FloraZone", "path": "res://src/world/flora_zone.gd", "base": "Marker3D", "pkg": "B",
		"props": ["radius_m", "counts"]},
	{"name": "FloraScatter", "path": "res://src/world/flora_scatter.gd", "base": "Node3D", "pkg": "B"},
	{"name": "ObstacleGrid", "path": "res://src/world/obstacle_grid.gd", "base": "RefCounted", "pkg": "B"},
	{"name": "Bait", "path": "res://src/world/bait.gd", "base": "Node3D", "pkg": "B"},
	{"name": "Steering", "path": "res://src/boars/steering.gd", "base": "RefCounted", "pkg": "B"},
	{"name": "Boar", "path": "res://src/boars/boar.gd", "base": "Node3D", "pkg": "B"},
	{"name": "BoarHerd", "path": "res://src/boars/boar_herd.gd", "base": "RefCounted", "pkg": "B"},
	{"name": "Dog", "path": "res://src/dogs/dog.gd", "base": "Node3D", "pkg": "B"},
	# --- game-systems ---
	{"name": "Wallet", "path": "res://src/systems/wallet.gd", "base": "RefCounted", "pkg": "S",
		"props": ["money", "gold"],
		"methods": ["balance(currency: StringName) -> int", "can_afford(price: int, currency: StringName) -> bool",
			"spend(price: int, currency: StringName) -> bool", "add(amount: int, currency: StringName) -> void",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Wallet"]},
	{"name": "Inventory", "path": "res://src/systems/inventory.gd", "base": "RefCounted", "pkg": "S",
		"props": ["owned_weapons", "owned_dogs", "items", "loadout_weapons", "loadout_dog", "loadout_items"],
		"methods": ["owns(id: StringName) -> bool", "get_count(id: StringName) -> int",
			"add_item(id: StringName, count: int) -> void", "remove_item(id: StringName, count: int) -> bool",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Inventory"]},
	{"name": "Progression", "path": "res://src/systems/progression.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["unlocked_count(map_id: StringName) -> int", "is_unlocked(map_id: StringName, index: int) -> bool",
			"is_completed(map_id: StringName, index: int) -> bool",
			"mark_won(map_id: StringName, index: int, crop_pct: float) -> void",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Progression"]},
	{"name": "Shop", "path": "res://src/systems/shop.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["check(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName",
			"buy(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName"]},
	{"name": "RewardCalculator", "path": "res://src/systems/reward_calculator.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["kill_reward(type_def: Dictionary, rules: Dictionary, weight_kg: float, killing_zone: StringName, one_shot: bool, contract_def: Dictionary) -> int",
			"contract_bonus(contract_def: Dictionary, crop_health_pct: float) -> int"]},
	{"name": "SaveService", "path": "res://src/systems/save_service.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["write(path: String, data: Dictionary) -> bool", "read(path: String) -> Dictionary",
			"migrate(data: Dictionary) -> Dictionary", "sanitize(data: Dictionary) -> Dictionary",
			"new_save() -> Dictionary"]},
	{"name": "PixBrCode", "path": "res://src/systems/pix/pix_br_code.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["crc16_ccitt(text: String) -> int",
			"build(pix_key: String, amount_brl: float, merchant_name: String, merchant_city: String, txid: String = \"***\", description: String = \"\") -> String",
			"sanitize(text: String, max_len: int) -> String"]},
	{"name": "PixGateway", "path": "res://src/systems/pix/pix_gateway.gd", "base": "RefCounted", "pkg": "S",
		"signals": ["redeem_completed(ok: bool, gold: int, message: String)"],
		"methods": ["get_payment_payload(package: Dictionary) -> String", "request_redeem(code: String) -> void",
			"is_secure() -> bool", "create_from_config(config: Dictionary) -> PixGateway"]},
	{"name": "OfflineRedeemGateway", "path": "res://src/systems/pix/offline_redeem_gateway.gd", "base": "PixGateway", "pkg": "S",
		"methods": ["is_secure() -> bool"]},
	{"name": "RedeemCode", "path": "res://src/systems/pix/redeem_code.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["normalize(code: String) -> String",
			"generate(gold: int, nonce: String, secret: String) -> String",
			"parse(code: String, secret: String) -> int"]},
	{"name": "DonationService", "path": "res://src/systems/pix/donation_service.gd", "base": "RefCounted", "pkg": "S",
		"signals": ["redeem_finished(ok: bool, gold: int, message: String)"],
		"methods": ["_init(gateway: PixGateway = null)", "get_packages() -> Array",
			"get_pix_payload(package_id: StringName) -> String", "redeem(code: String) -> void"]},
]


# --------------------------------------------------------------------------------------------
# Parsing and comparing
# --------------------------------------------------------------------------------------------

static func parse(spec: String) -> Dictionary:
	var open: int = spec.find("(")
	var close: int = spec.rfind(")")
	var arrow: int = spec.rfind("->")
	if arrow > 0:
		close = spec.rfind(")", arrow)
	var out: Dictionary = {"name": spec.substr(0, open).strip_edges(), "args": [], "ret": ""}
	if arrow > 0:
		out["ret"] = spec.substr(arrow + 2).strip_edges()
	var inner: String = spec.substr(open + 1, close - open - 1).strip_edges()
	if inner != "":
		for part: String in _split_top_level(inner):
			var p: String = part.strip_edges()
			var default_idx: int = p.find(" = ")
			var has_default: bool = default_idx >= 0
			if has_default:
				p = p.substr(0, default_idx)
			var colon: int = p.find(":")
			(out["args"] as Array).append({
				"name": p.substr(0, colon).strip_edges(),
				"type": p.substr(colon + 1).strip_edges(),
				"default": has_default,
			})
	return out


static func _split_top_level(text: String) -> Array[String]:
	var parts: Array[String] = []
	var depth: int = 0
	var in_str: bool = false
	var cur: String = ""
	for ch: String in text:
		if ch == "\"":
			in_str = not in_str
		if not in_str:
			if ch == "[" or ch == "(":
				depth += 1
			elif ch == "]" or ch == ")":
				depth -= 1
			elif ch == "," and depth == 0:
				parts.append(cur)
				cur = ""
				continue
		cur += ch
	parts.append(cur)
	return parts


## Variant.Type for a contract type name; -1 = any (Variant), -2 = unknown class name (object).
static func type_code(type_name: String) -> int:
	match type_name:
		"int", "HuntResult.Outcome":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"bool":
			return TYPE_BOOL
		"String":
			return TYPE_STRING
		"StringName":
			return TYPE_STRING_NAME
		"Vector2":
			return TYPE_VECTOR2
		"Vector3":
			return TYPE_VECTOR3
		"Rect2":
			return TYPE_RECT2
		"Dictionary":
			return TYPE_DICTIONARY
		"Array":
			return TYPE_ARRAY
		"PackedStringArray":
			return TYPE_PACKED_STRING_ARRAY
		"PackedInt32Array":
			return TYPE_PACKED_INT32_ARRAY
		"PackedVector3Array":
			return TYPE_PACKED_VECTOR3_ARRAY
		"Variant":
			return -1
	return TYPE_OBJECT


static func _type_name(code: int) -> String:
	return type_string(code) if code >= 0 else "any"


## Compares one method entry (from get_method_list / get_script_method_list) against a spec.
## Returns "" when it matches, otherwise a human readable difference.
static func compare_method(entry: Dictionary, spec: Dictionary) -> String:
	var problems: PackedStringArray = PackedStringArray()
	var args: Array = entry.get("args", [])
	var spec_args: Array = spec["args"]
	if args.size() != spec_args.size():
		problems.append("%d parametros (esperado %d)" % [args.size(), spec_args.size()])
	else:
		for i: int in args.size():
			var want: Dictionary = spec_args[i]
			var got: Dictionary = args[i]
			var want_code: int = type_code(want["type"])
			var got_code: int = int(got.get("type", TYPE_NIL))
			var got_name: String = str(got.get("name", "")).trim_prefix("_")
			if got_name != want["name"]:
				problems.append("parametro %d chama '%s' (esperado '%s')" % [i, got_name, want["name"]])
			if want_code >= 0 and got_code != want_code and not (want_code == TYPE_OBJECT and got_code == TYPE_OBJECT):
				problems.append("parametro '%s' e %s (esperado %s)" % [want["name"], _type_name(got_code), want["type"]])
			elif want_code == TYPE_OBJECT and got_code == TYPE_OBJECT:
				var cls: String = str(got.get("class_name", ""))
				if cls != "" and cls != want["type"] and not _derives(cls, want["type"]):
					problems.append("parametro '%s' e %s (esperado %s)" % [want["name"], cls, want["type"]])
		var defaults: Array = entry.get("default_args", [])
		var want_defaults: int = 0
		for a: Dictionary in spec_args:
			if a["default"]:
				want_defaults += 1
		if defaults.size() != want_defaults:
			problems.append("%d valores padrao (esperado %d)" % [defaults.size(), want_defaults])
	var ret_name: String = spec["ret"]
	if ret_name != "" and entry.has("return"):
		var ret: Dictionary = entry["return"]
		var ret_code: int = int(ret.get("type", TYPE_NIL))
		var is_variant: bool = (int(ret.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0
		if ret_name == "void":
			if ret_code != TYPE_NIL or is_variant:
				problems.append("retorno nao e void")
		elif ret_name != "Variant":
			var want_ret: int = type_code(ret_name)
			if ret_code != want_ret and not (is_variant and ret_code == TYPE_NIL):
				problems.append("retorno e %s (esperado %s)" % [_type_name(ret_code), ret_name])
	return "; ".join(problems)


static func _derives(cls: String, base: String) -> bool:
	if ClassDB.class_exists(cls):
		return ClassDB.is_parent_class(cls, base)
	return false


static func find_method(entries: Array[Dictionary], name: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("name", "")) == name:
			return e
	return {}


static func find_signal(entries: Array[Dictionary], name: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("name", "")) == name:
			return e
	return {}


## Same as compare_method but for signals (no defaults, no return).
static func compare_signal(entry: Dictionary, spec: Dictionary) -> String:
	var as_method: Dictionary = {"args": entry.get("args", []), "default_args": []}
	var spec_copy: Dictionary = spec.duplicate(true)
	spec_copy["ret"] = ""
	for a: Dictionary in spec_copy["args"]:
		a["default"] = false
	return compare_method(as_method, spec_copy)
