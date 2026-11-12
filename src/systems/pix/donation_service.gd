class_name DonationService
extends RefCounted
## What the donation screen talks to. Wraps a PixGateway; credits gold through Profile.
## Donations are voluntary: nothing here claims a payment was verified.

signal redeem_finished(ok: bool, gold: int, message: String)

const PLACEHOLDER_KEY_PREFIX: String = "SUA-CHAVE"
const MSG_USED: String = "Este código já foi usado."
const MSG_EMPTY: String = "Digite o código de resgate."

var _gateway: PixGateway
var _pending_code: String = ""


func _init(gateway: PixGateway = null) -> void:
	_gateway = gateway if gateway != null else PixGateway.create_from_config(Data.get_pix_config())


func get_packages() -> Array[Dictionary]:
	return Data.get_gold_packages()


## Pix copia e cola for the package, or "" if the package does not exist.
func get_pix_payload(package_id: StringName) -> String:
	var pkg: Dictionary = Data.get_gold_package(package_id)
	if pkg.is_empty():
		return ""
	return _gateway.get_payment_payload(pkg)


## false while data/pix_config.json still has the placeholder key (the UI must warn instead of showing a payload).
func is_pix_configured() -> bool:
	var key: String = str(Data.get_pix_config().get("pix_key", "")).strip_edges()
	return key != "" and not key.to_upper().begins_with(PLACEHOLDER_KEY_PREFIX)


func is_secure() -> bool:
	return _gateway.is_secure()


func get_support_text() -> String:
	return str(Data.get_pix_config().get("support_text", ""))


## Always answers through redeem_finished, asynchronously.
func redeem(code: String) -> void:
	var normalized: String = RedeemCode.normalize(code)
	if normalized == "":
		redeem_finished.emit.call_deferred(false, 0, MSG_EMPTY)
		return
	if Profile.is_code_redeemed(normalized):
		redeem_finished.emit.call_deferred(false, 0, MSG_USED)
		return
	_pending_code = normalized
	_gateway.redeem_completed.connect(_on_gateway_result, CONNECT_ONE_SHOT)
	_gateway.request_redeem(normalized)


func _on_gateway_result(ok: bool, gold: int, message: String) -> void:
	var code: String = _pending_code
	_pending_code = ""
	if not ok or gold <= 0:
		redeem_finished.emit(false, 0, message if message != "" else "Código inválido. Confira e tente de novo.")
		return
	if Profile.is_code_redeemed(code):
		redeem_finished.emit(false, 0, MSG_USED)
		return
	Profile.add_gold(gold)
	Profile.mark_code_redeemed(code)
	Profile.save()
	redeem_finished.emit(true, gold, "Obrigado! +%d de ouro." % gold)
