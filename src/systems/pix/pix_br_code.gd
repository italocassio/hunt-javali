class_name PixBrCode
extends RefCounted
## Static Pix "copia e cola" (EMV BR Code) builder. docs/arquitetura.md §9.8.

const GUI: String = "br.gov.bcb.pix"
const MAX_MERCHANT_NAME: int = 25
const MAX_MERCHANT_CITY: int = 15
const MAX_ACCOUNT_INFO: int = 99

const _ACCENTS: Dictionary = {
	"Á": "A", "À": "A", "Â": "A", "Ã": "A", "Ä": "A", "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
	"É": "E", "È": "E", "Ê": "E", "Ë": "E", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"Í": "I", "Ì": "I", "Î": "I", "Ï": "I", "í": "i", "ì": "i", "î": "i", "ï": "i",
	"Ó": "O", "Ò": "O", "Ô": "O", "Õ": "O", "Ö": "O", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"Ú": "U", "Ù": "U", "Û": "U", "Ü": "U", "ú": "u", "ù": "u", "û": "u", "ü": "u",
	"Ç": "C", "ç": "c", "Ñ": "N", "ñ": "n",
}


## CRC16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no xorout.
static func crc16_ccitt(text: String) -> int:
	var crc: int = 0xFFFF
	for b: int in text.to_utf8_buffer():
		crc ^= b << 8
		for _i: int in 8:
			if crc & 0x8000:
				crc = ((crc << 1) ^ 0x1021) & 0xFFFF
			else:
				crc = (crc << 1) & 0xFFFF
	return crc


## ASCII-only, accents stripped, UPPERCASE, truncated to max_len (for merchant name/city).
static func sanitize(text: String, max_len: int) -> String:
	return _ascii(text, true).substr(0, maxi(0, max_len)).strip_edges()


## Builds the full payload including the trailing CRC. amount_brl <= 0 omits the amount (payer types it).
static func build(pix_key: String, amount_brl: float, merchant_name: String, merchant_city: String, txid: String = "***", description: String = "") -> String:
	var key: String = _ascii(pix_key, false).strip_edges()
	var account: String = _tlv("00", GUI) + _tlv("01", key)
	var desc: String = _ascii(description, false).strip_edges()
	var room: int = MAX_ACCOUNT_INFO - account.length() - 4
	if desc != "" and room > 0:
		account += _tlv("02", desc.substr(0, room))
	var payload: String = _tlv("00", "01")
	payload += _tlv("26", account)
	payload += _tlv("52", "0000")
	payload += _tlv("53", "986")
	if amount_brl > 0.0:
		payload += _tlv("54", "%.2f" % amount_brl)
	payload += _tlv("58", "BR")
	payload += _tlv("59", sanitize(merchant_name, MAX_MERCHANT_NAME))
	payload += _tlv("60", sanitize(merchant_city, MAX_MERCHANT_CITY))
	payload += _tlv("62", _tlv("05", _txid(txid)))
	payload += "6304"
	return payload + "%04X" % crc16_ccitt(payload)


static func _tlv(id: String, value: String) -> String:
	return "%s%02d%s" % [id, value.length(), value]


static func _txid(txid: String) -> String:
	var clean: String = ""
	for ch: String in txid:
		var c: int = ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			clean += ch
	if clean == "":
		return "***"
	return clean.substr(0, 25)


static func _ascii(text: String, upper: bool) -> String:
	var out: String = ""
	for ch: String in text:
		var c: String = _ACCENTS.get(ch, ch)
		var code: int = c.unicode_at(0) if c.length() > 0 else 0
		if code >= 32 and code <= 126:
			out += c
	return out.to_upper() if upper else out
