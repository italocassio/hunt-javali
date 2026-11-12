class_name RedeemCode
extends RefCounted
## Offline redeem codes: JV-<GOLD 4 digits>-<NONCE 6 [A-Z0-9]>-<CHK 4 hex>.
## NOT fraud-safe: the secret ships with the game (docs/arquitetura.md §9.8).

const PREFIX: String = "JV"
const NONCE_LENGTH: int = 6
const NONCE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


## Strips whitespace and uppercases.
static func normalize(code: String) -> String:
	var out: String = ""
	for ch: String in code:
		if ch != " " and ch != "\t" and ch != "\n" and ch != "\r" and ch != " ":
			out += ch
	return out.to_upper()


## Returns "" (and push_error) for invalid gold or nonce.
static func generate(gold: int, nonce: String, secret: String) -> String:
	var n: String = normalize(nonce)
	if gold < 0 or gold > 9999 or not _is_nonce(n):
		push_error("RedeemCode.generate: gold must be 0..9999 and nonce %d chars [A-Z0-9]" % NONCE_LENGTH)
		return ""
	var gold_text: String = "%04d" % gold
	return "%s-%s-%s-%s" % [PREFIX, gold_text, n, _checksum(gold_text, n, secret)]


## Gold granted by a valid code, or -1 (bad format, bad checksum or gold not matching any package).
static func parse(code: String, secret: String) -> int:
	var parts: PackedStringArray = normalize(code).split("-")
	if parts.size() != 4 or parts[0] != PREFIX:
		return -1
	var gold_text: String = parts[1]
	if gold_text.length() != 4 or not gold_text.is_valid_int():
		return -1
	if not _is_nonce(parts[2]) or parts[3] != _checksum(gold_text, parts[2], secret):
		return -1
	var gold: int = int(gold_text)
	for pkg: Dictionary in Data.get_gold_packages():
		if int(pkg.get("gold", -2)) == gold:
			return gold
	return -1


static func generate_nonce() -> String:
	var out: String = ""
	for _i: int in NONCE_LENGTH:
		out += NONCE_CHARS[randi() % NONCE_CHARS.length()]
	return out


static func _checksum(gold_text: String, nonce: String, secret: String) -> String:
	return (secret + "|" + gold_text + "|" + nonce).sha256_text().substr(0, 4).to_upper()


static func _is_nonce(n: String) -> bool:
	if n.length() != NONCE_LENGTH:
		return false
	for ch: String in n:
		var c: int = ch.unicode_at(0)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90)):
			return false
	return true
