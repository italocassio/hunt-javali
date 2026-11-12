class_name Inventory
extends RefCounted
## Owned items and the current loadout. Pure rules; item definitions come from Data.

var owned_weapons: Array[StringName] = []
var owned_dogs: Array[StringName] = []
var items: Dictionary = {}                      # equipment id (StringName) -> int
var loadout_weapons: Array[StringName] = [&"", &""]
var loadout_dog: StringName = &""
var loadout_items: Array[StringName] = []


func owns(id: StringName) -> bool:
	return get_count(id) > 0


## Consumables: quantity. Weapons, dogs, passive/active equipment: 0 or 1.
func get_count(id: StringName) -> int:
	if owned_weapons.has(id) or owned_dogs.has(id):
		return 1
	return int(items.get(id, 0))


## Weapons/dogs are added once (count ignored). Equipment accumulates for consumables, caps at 1 otherwise.
func add_item(id: StringName, count: int) -> void:
	if count <= 0:
		return
	match Data.get_item_category(id):
		&"weapon":
			if not owned_weapons.has(id):
				owned_weapons.append(id)
		&"dog":
			if not owned_dogs.has(id):
				owned_dogs.append(id)
		&"equipment":
			if Data.get_equipment(id).get("kind", "") == "consumable":
				items[id] = int(items.get(id, 0)) + count
			else:
				items[id] = 1
		_:
			push_error("Inventory.add_item: unknown item '%s'" % id)


## Only equipment can be removed (consumables being used). Returns false if there is not enough.
func remove_item(id: StringName, count: int) -> bool:
	if count < 0 or int(items.get(id, 0)) < count:
		return false
	var left: int = int(items.get(id, 0)) - count
	if left <= 0:
		items.erase(id)
	else:
		items[id] = left
	prune_loadout()
	return true


## Drops loadout entries that are no longer owned.
func prune_loadout() -> void:
	var kept: Array[StringName] = []
	for id: StringName in loadout_items:
		if owns(id) and not kept.has(id):
			kept.append(id)
	loadout_items = kept
	if loadout_dog != &"" and not owned_dogs.has(loadout_dog):
		loadout_dog = &""


## Returns {"inventory": {...}, "loadout": {...}} matching the save schema blocks.
func to_dict() -> Dictionary:
	var item_dict: Dictionary = {}
	for id: StringName in items:
		item_dict[String(id)] = int(items[id])
	return {
		"inventory": {
			"weapons": _strings(owned_weapons),
			"dogs": _strings(owned_dogs),
			"items": item_dict,
		},
		"loadout": {
			"weapons": _strings(loadout_weapons),
			"dog": String(loadout_dog),
			"items": _strings(loadout_items),
		},
	}


## Accepts the "inventory"/"loadout" blocks side by side ({"inventory": {...}, "loadout": {...}}).
## Expects already sanitized data (see SaveService.sanitize) but tolerates missing keys.
static func from_dict(d: Dictionary) -> Inventory:
	var inv: Inventory = Inventory.new()
	var block: Dictionary = d.get("inventory", {}) if d.get("inventory", {}) is Dictionary else {}
	var load_block: Dictionary = d.get("loadout", {}) if d.get("loadout", {}) is Dictionary else {}
	var raw_w: Variant = block.get("weapons", [])
	if raw_w is Array:
		for w: Variant in raw_w:
			inv.owned_weapons.append(StringName(str(w)))
	var raw_d: Variant = block.get("dogs", [])
	if raw_d is Array:
		for dg: Variant in raw_d:
			inv.owned_dogs.append(StringName(str(dg)))
	var raw_items: Variant = block.get("items", {})
	if raw_items is Dictionary:
		for key: Variant in raw_items:
			inv.items[StringName(str(key))] = int(raw_items[key])
	var lw: Array[StringName] = [&"", &""]
	var raw_lw: Variant = load_block.get("weapons", [])
	if raw_lw is Array:
		for i: int in mini(2, (raw_lw as Array).size()):
			lw[i] = StringName(str(raw_lw[i]))
	inv.loadout_weapons = lw
	inv.loadout_dog = StringName(str(load_block.get("dog", "")))
	var raw_li: Variant = load_block.get("items", [])
	if raw_li is Array:
		for it: Variant in raw_li:
			inv.loadout_items.append(StringName(str(it)))
	return inv


static func _strings(list: Array[StringName]) -> Array:
	var out: Array = []
	for id: StringName in list:
		out.append(String(id))
	return out
