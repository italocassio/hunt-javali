class_name Shop
extends RefCounted
## Purchase rules. Static, no UI. Result codes: &"ok" | &"insufficient_funds" | &"already_owned" |
## &"max_reached" | &"unknown_item".


static func check(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName:
	var category: StringName = Data.get_item_category(item_id)
	if category == &"":
		return &"unknown_item"
	var def: Dictionary = Data.get_item_def(item_id)
	if category == &"equipment" and def.get("kind", "") == "consumable":
		var max_owned: int = int(Data.get_game().get("shop", {}).get("max_consumable_owned", 9))
		if inventory.get_count(item_id) >= max_owned:
			return &"max_reached"
	elif inventory.owns(item_id):
		return &"already_owned"
	if not wallet.can_afford(int(def.get("price", 0)), StringName(str(def.get("currency", "money")))):
		return &"insufficient_funds"
	return &"ok"


static func buy(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName:
	var code: StringName = check(item_id, wallet, inventory)
	if code != &"ok":
		return code
	var def: Dictionary = Data.get_item_def(item_id)
	var currency: StringName = StringName(str(def.get("currency", "money")))
	if not wallet.spend(int(def.get("price", 0)), currency):
		return &"insufficient_funds"
	inventory.add_item(item_id, 1)
	return &"ok"
