class_name OfflineRedeemGateway
extends PixGateway
## Validates redeem codes locally with the shared secret. NOT secure against fraud (see §9.8).

const MSG_INVALID: String = "Código inválido. Confira e tente de novo."


func _init(config: Dictionary = {}) -> void:
	super(config)


func request_redeem(code: String) -> void:
	var gold: int = RedeemCode.parse(code, str(_config.get("redeem_secret", "")))
	if gold < 0:
		redeem_completed.emit.call_deferred(false, 0, MSG_INVALID)
	else:
		redeem_completed.emit.call_deferred(true, gold, "")


func is_secure() -> bool:
	return false
