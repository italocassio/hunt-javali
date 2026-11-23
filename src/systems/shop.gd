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


## Next-level purchase of an upgrade (backpack, knife). Same codes as check(), minus &"already_owned".
static func check_upgrade(upgrade_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName:
	if not Data.get_upgrade_ids().has(upgrade_id):
		return &"unknown_item"
	var level: int = inventory.get_upgrade_level(upgrade_id)
	if level >= Data.get_upgrade_level_count(upgrade_id):
		return &"max_reached"
	var next: Dictionary = Data.get_upgrade_level_def(upgrade_id, level + 1)
	var currency: StringName = StringName(str(Data.get_upgrade(upgrade_id).get("currency", "money")))
	if not wallet.can_afford(int(next.get("price", 0)), currency):
		return &"insufficient_funds"
	return &"ok"


## Spends the price and raises the upgrade by one level. No saving, no events.
static func buy_upgrade(upgrade_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName:
	var code: StringName = check_upgrade(upgrade_id, wallet, inventory)
	if code != &"ok":
		return code
	var level: int = inventory.get_upgrade_level(upgrade_id)
	var currency: StringName = StringName(str(Data.get_upgrade(upgrade_id).get("currency", "money")))
	if not wallet.spend(int(Data.get_upgrade_level_def(upgrade_id, level + 1).get("price", 0)), currency):
		return &"insufficient_funds"
	inventory.upgrades[upgrade_id] = level + 1
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
