class_name PixGateway
extends RefCounted
## Swappable donation backend. The UI only talks to DonationService, which talks to this interface.
## "offline" -> OfflineRedeemGateway. A real PSP/backend is another subclass selected by config "gateway".

signal redeem_completed(ok: bool, gold: int, message: String)

const OFFLINE_SCRIPT: String = "res://src/systems/pix/offline_redeem_gateway.gd"

var _config: Dictionary = {}


func _init(config: Dictionary = {}) -> void:
	_config = config


## Pix "copia e cola" text for a gold package (dictionary from gold_packages.json).
func get_payment_payload(package: Dictionary) -> String:
	return PixBrCode.build(
		str(_config.get("pix_key", "")),
		float(package.get("price_brl", 0.0)),
		str(_config.get("merchant_name", "")),
		str(_config.get("merchant_city", "")),
		str(_config.get("txid", "***")),
		str(_config.get("description", "")))


## Asynchronous by contract: always emits redeem_completed later, never inside this call.
func request_redeem(_code: String) -> void:
	redeem_completed.emit.call_deferred(false, 0, "Resgate indisponível.")


## true only when codes are verified by something the player cannot forge (a server).
func is_secure() -> bool:
	return false


static func create_from_config(config: Dictionary) -> PixGateway:
	# Loaded by path: referencing the subclass by class_name here would make a cyclic dependency.
	match str(config.get("gateway", "offline")):
		"offline":
			return load(OFFLINE_SCRIPT).new(config) as PixGateway
		var other:
			push_warning("PixGateway: unknown gateway '%s', using offline." % other)
			return load(OFFLINE_SCRIPT).new(config) as PixGateway
