class_name Wallet
extends RefCounted
## Money (R$) and gold balances. Pure rules, no UI, no autoload access.

const MAX_BALANCE: int = 999999999

var money: int = 0
var gold: int = 0


func balance(currency: StringName) -> int:
	if currency == Ids.GOLD:
		return gold
	return money


func can_afford(price: int, currency: StringName) -> bool:
	return price >= 0 and balance(currency) >= price


## Subtracts price. Returns false (and changes nothing) when the balance is too low.
func spend(price: int, currency: StringName) -> bool:
	if price < 0:
		push_error("Wallet.spend: negative price %d" % price)
		return false
	if not can_afford(price, currency):
		return false
	_store(currency, balance(currency) - price)
	return true


func add(amount: int, currency: StringName) -> void:
	if amount < 0:
		push_error("Wallet.add: negative amount %d ignored" % amount)
		return
	_store(currency, mini(balance(currency) + amount, MAX_BALANCE))


func to_dict() -> Dictionary:
	return {"money": money, "gold": gold}


static func from_dict(d: Dictionary) -> Wallet:
	var w: Wallet = Wallet.new()
	w.money = clampi(_to_int(d.get("money", 0)), 0, MAX_BALANCE)
	w.gold = clampi(_to_int(d.get("gold", 0)), 0, MAX_BALANCE)
	return w


func _store(currency: StringName, value: int) -> void:
	if currency == Ids.GOLD:
		gold = value
	else:
		money = value


static func _to_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(clampf(v, -1.0e12, 1.0e12))
	return 0
