class_name HuntRequest
extends RefCounted
## What the hunt receives from the menus (built by Profile.build_hunt_request).

var map_id: StringName = &"mato_grosso"
var contract_index: int = 0
var weapon_ids: Array[StringName] = [&"carbine_22"]   # 1..2 entries, slot order, no empty ids
var dog_id: StringName = &""                          # &"" = no dog
var item_ids: Array[StringName] = []                  # equipped equipment ids (max 3)
var item_counts: Dictionary = {}                      # StringName -> int (consumables: carried; others: 1)
var quality: StringName = &""                         # &"" = resolve from settings
var rng_seed: int = 0                                 # 0 = randomize
var player_count: int = 1


static func make_debug(p_map_id: StringName = &"mato_grosso", p_contract_index: int = 0) -> HuntRequest:
	var r: HuntRequest = HuntRequest.new()
	r.map_id = p_map_id
	r.contract_index = p_contract_index
	return r


func has_item(item_id: StringName) -> bool:
	return item_ids.has(item_id)


func get_item_count(item_id: StringName) -> int:
	return int(item_counts.get(item_id, 0))
