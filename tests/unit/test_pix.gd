extends "res://tests/lib/test_case.gd"
## PixBrCode, RedeemCode and DonationService (docs/arquitetura.md section 9.8).

const SECRET: String = "segredo-de-teste"


func _parse_tlv(text: String) -> Array:
	## Splits a top-level EMV string into [[id, value], ...]. Fails the test on malformed length fields.
	var out: Array = []
	var i: int = 0
	while i < text.length():
		if i + 4 > text.length():
			fail("TLV truncado em %d: '%s'" % [i, text.substr(i)])
			return out
		var id: String = text.substr(i, 2)
		var len_text: String = text.substr(i + 2, 2)
		if not len_text.is_valid_int():
			fail("comprimento invalido '%s' no campo %s" % [len_text, id])
			return out
		var length: int = int(len_text)
		if i + 4 + length > text.length():
			fail("campo %s declara %d mas faltam caracteres" % [id, length])
			return out
		out.append([id, text.substr(i + 4, length)])
		i += 4 + length
	return out


func test_crc16_known_vector() -> void:
	eq(PixBrCode.crc16_ccitt("123456789"), 0x29B1, "CRC16/CCITT-FALSE de '123456789'")
	eq(PixBrCode.crc16_ccitt(""), 0xFFFF, "CRC de vazio = init")


func test_build_structure() -> void:
	var payload: String = PixBrCode.build("12345678900", 25.0, "Caçada ao Javali", "Cuiabá", "***", "Apoio")
	var fields: Array = _parse_tlv(payload)
	var by_id: Dictionary = {}
	for f: Array in fields:
		by_id[f[0]] = f[1]
	eq(fields[0][0], "00", "primeiro campo e 00")
	eq(by_id["00"], "01", "payload format indicator")
	eq(by_id["52"], "0000", "MCC")
	eq(by_id["53"], "986", "moeda BRL")
	eq(by_id["54"], "25.00", "valor com 2 casas")
	eq(by_id["58"], "BR", "pais")
	eq(by_id["59"], "CACADA AO JAVALI", "nome sem acento e maiusculo")
	eq(by_id["60"], "CUIABA", "cidade sem acento")
	eq(fields[-1][0], "63", "CRC e o ultimo campo")
	eq((fields[-1][1] as String).length(), 4, "CRC com 4 caracteres")
	var account: Array = _parse_tlv(by_id["26"])
	eq(account[0], ["00", "br.gov.bcb.pix"], "GUI")
	eq(account[1], ["01", "12345678900"], "chave")
	eq(account[2], ["02", "Apoio"], "descricao")
	ok((by_id["26"] as String).length() <= 99, "campo 26 <= 99")
	var extra: Array = _parse_tlv(by_id["62"])
	eq(extra[0], ["05", "***"], "txid estatico")
	# Final CRC checks out.
	var body: String = payload.substr(0, payload.length() - 4)
	ok(body.ends_with("6304"), "CRC calculado incluindo o '6304'")
	eq(payload.substr(payload.length() - 4), "%04X" % PixBrCode.crc16_ccitt(body), "CRC final confere")
	for ch: String in payload:
		ok(ch.unicode_at(0) >= 32 and ch.unicode_at(0) <= 126, "so ASCII imprimivel: '%s'" % ch)
		if not (ch.unicode_at(0) >= 32 and ch.unicode_at(0) <= 126):
			break


func test_build_no_amount_and_limits() -> void:
	var p: String = PixBrCode.build("a@b.com", 0.0, "X", "Y")
	var ids: Array[String] = []
	for f: Array in _parse_tlv(p):
		ids.append(f[0])
	ok(not ids.has("54"), "valor 0 omite o campo 54")
	var long_name: String = PixBrCode.build("k", 5.0, "NOME MUITO LONGO QUE ESTOURA O LIMITE DE 25", "CIDADE COM NOME ENORME DEMAIS", "TX1")
	for f: Array in _parse_tlv(long_name):
		if f[0] == "59":
			ok((f[1] as String).length() <= PixBrCode.MAX_MERCHANT_NAME, "nome truncado em 25")
		if f[0] == "60":
			ok((f[1] as String).length() <= PixBrCode.MAX_MERCHANT_CITY, "cidade truncada em 15")
	# A long description must never push field 26 above 99 chars.
	var big: String = PixBrCode.build("12345678900", 1.0, "N", "C", "***", "d".repeat(200))
	for f: Array in _parse_tlv(big):
		if f[0] == "26":
			ok((f[1] as String).length() <= 99, "campo 26 <= 99 com descricao longa (%d)" % (f[1] as String).length())
	eq(big.substr(big.length() - 4), "%04X" % PixBrCode.crc16_ccitt(big.substr(0, big.length() - 4)), "CRC valido com descricao longa")


func test_build_with_hostile_text() -> void:
	var p: String = PixBrCode.build("chave\tcom\nlixo", 10.0, "日本語", "", "tx id!@#")
	var fields: Array = _parse_tlv(p)
	ok(fields.size() > 5, "payload ainda e parseavel")
	for f: Array in fields:
		if f[0] == "62":
			var inner: Array = _parse_tlv(f[1])
			eq(inner[0][1], "txid", "txid sanitizado (so alfanumerico)")
	eq(p.substr(p.length() - 4), "%04X" % PixBrCode.crc16_ccitt(p.substr(0, p.length() - 4)), "CRC valido")


func test_sanitize() -> void:
	eq(PixBrCode.sanitize("São Paulo", 15), "SAO PAULO", "acentos")
	eq(PixBrCode.sanitize("abcdefghij", 4), "ABCD", "trunca")
	eq(PixBrCode.sanitize("abc", 0), "", "limite 0")
	eq(PixBrCode.sanitize("abc", -3), "", "limite negativo")


func test_redeem_generate_parse() -> void:
	var gold: int = int(Data.get_gold_packages()[0]["gold"])
	var code: String = RedeemCode.generate(gold, "K7Q2MZ", SECRET)
	ok(code.begins_with("JV-"), "prefixo")
	eq(code.split("-").size(), 4, "4 partes")
	eq(RedeemCode.parse(code, SECRET), gold, "codigo valido devolve o ouro")
	eq(RedeemCode.parse(code.to_lower(), SECRET), gold, "minusculas aceitas")
	eq(RedeemCode.parse("  " + code + "\n", SECRET), gold, "espacos aceitos")
	eq(RedeemCode.parse(code, "outro-segredo"), -1, "segredo errado")
	var parts: PackedStringArray = code.split("-")
	var tampered_gold: String = "%s-%04d-%s-%s" % [parts[0], gold + 100, parts[2], parts[3]]
	eq(RedeemCode.parse(tampered_gold, SECRET), -1, "ouro adulterado")
	var tampered_nonce: String = "%s-%s-%s-%s" % [parts[0], parts[1], "AAAAAA", parts[3]]
	eq(RedeemCode.parse(tampered_nonce, SECRET), -1, "nonce adulterado")
	var tampered_chk: String = "%s-%s-%s-%s" % [parts[0], parts[1], parts[2], "0000" if parts[3] != "0000" else "1111"]
	eq(RedeemCode.parse(tampered_chk, SECRET), -1, "checksum adulterado")


func test_redeem_parse_rejects_garbage() -> void:
	for bad: String in ["", "JV", "JV-0050", "JV-0050-K7Q2MZ", "JV-0050-K7Q2MZ-1F3A-EXTRA", "XX-0050-K7Q2MZ-1F3A",
			"JV-ABCD-K7Q2MZ-1F3A", "JV-50-K7Q2MZ-1F3A", "JV--K7Q2MZ-1F3A", "JV-0050-K7Q2-1F3A", "----", "JV-0050-K7Q2MZ-",
			"JV-9999-K7Q2MZ-0000", "JV--050-K7Q2MZ-1F3A", "JV-0050-K7Q2M!-1F3A"]:
		eq(RedeemCode.parse(bad, SECRET), -1, "rejeita '%s'" % bad)


func test_redeem_generate_validates_input() -> void:
	expect_errors()
	eq(RedeemCode.generate(-1, "K7Q2MZ", SECRET), "", "ouro negativo")
	eq(RedeemCode.generate(10000, "K7Q2MZ", SECRET), "", "ouro > 9999")
	eq(RedeemCode.generate(50, "CURTO", SECRET), "", "nonce curto")
	eq(RedeemCode.generate(50, "K7Q2M!", SECRET), "", "nonce com simbolo")
	var gold_not_in_package: String = RedeemCode.generate(7, "K7Q2MZ", SECRET)
	ne(gold_not_in_package, "", "gera para qualquer ouro 0..9999")
	eq(RedeemCode.parse(gold_not_in_package, SECRET), -1, "parse recusa ouro que nao e de nenhum pacote")


func test_redeem_nonce_generator() -> void:
	for i: int in 50:
		var n: String = RedeemCode.generate_nonce()
		eq(n.length(), RedeemCode.NONCE_LENGTH, "tamanho do nonce")
		for ch: String in n:
			ok(RedeemCode.NONCE_CHARS.contains(ch), "caractere '%s' do nonce permitido" % ch)


func test_redeem_normalize() -> void:
	eq(RedeemCode.normalize(" jv-0050 -k7q2mz\t-1f3a\n"), "JV-0050-K7Q2MZ-1F3A", "remove espacos e poe maiuscula")
	eq(RedeemCode.normalize(""), "", "vazio")


func _gateway_with_secret() -> PixGateway:
	var cfg: Dictionary = Data.get_pix_config().duplicate()
	cfg["redeem_secret"] = SECRET
	return PixGateway.create_from_config(cfg)


func _redeem(service: DonationService, code: String) -> Dictionary:
	var rec: Dictionary = record_signal(service.redeem_finished)
	service.redeem(code)
	var guard: int = 0
	while int(rec["count"]) == 0 and guard < 30:
		await frames(1)
		guard += 1
	return rec


func test_donation_redeem_flow_and_reuse() -> void:
	fresh_profile()
	var service: DonationService = DonationService.new(_gateway_with_secret())
	var gold: int = int(Data.get_gold_packages()[0]["gold"])
	var code: String = RedeemCode.generate(gold, "K7Q2MZ", SECRET)
	var gold0: int = Profile.get_gold()
	var rec: Dictionary = await _redeem(service, code)
	eq(rec["count"], 1, "redeem_finished 1x")
	if rec["count"] == 1:
		eq(rec["calls"][0][0], true, "sucesso")
		eq(rec["calls"][0][1], gold, "ouro informado")
	eq(Profile.get_gold(), gold0 + gold, "ouro creditado")
	ok(Profile.is_code_redeemed(code), "codigo marcado como usado")
	# Same code again, lowercase and with spaces: rejected, no extra gold.
	var rec2: Dictionary = await _redeem(service, " " + code.to_lower() + " ")
	eq(rec2["count"], 1, "segunda resposta")
	if rec2["count"] == 1:
		eq(rec2["calls"][0][0], false, "reuso rejeitado")
		eq(rec2["calls"][0][2], DonationService.MSG_USED, "mensagem de codigo usado")
	eq(Profile.get_gold(), gold0 + gold, "reuso nao credita")
	# The used-code mark survives a reload.
	Profile.load_or_create()
	ok(Profile.is_code_redeemed(code), "codigo usado persiste no save")
	cleanup_test_files()


func test_donation_rejects_invalid_and_empty() -> void:
	fresh_profile()
	var service: DonationService = DonationService.new(_gateway_with_secret())
	var gold0: int = Profile.get_gold()
	var rec: Dictionary = await _redeem(service, "")
	eq(rec["calls"][0][0], false, "vazio rejeitado")
	eq(rec["calls"][0][2], DonationService.MSG_EMPTY, "mensagem de vazio")
	var rec2: Dictionary = await _redeem(service, "JV-0050-K7Q2MZ-0000")
	eq(rec2["calls"][0][0], false, "checksum errado rejeitado")
	var rec3: Dictionary = await _redeem(service, "lixo qualquer")
	eq(rec3["calls"][0][0], false, "lixo rejeitado")
	var rec4: Dictionary = await _redeem(service, "   \n ")
	eq(rec4["calls"][0][0], false, "so espacos rejeitado")
	eq(Profile.get_gold(), gold0, "nada creditado")
	cleanup_test_files()


func test_donation_payload_and_placeholder_state() -> void:
	expect_errors()   # unknown package id logs through Data
	var service: DonationService = DonationService.new(_gateway_with_secret())
	var pkgs: Array[Dictionary] = service.get_packages()
	ok(pkgs.size() >= 1, "pacotes")
	if pkgs.is_empty():
		return
	var payload: String = service.get_pix_payload(StringName(str(pkgs[0]["id"])))
	ok(payload.length() > 40, "payload gerado")
	eq(payload.substr(payload.length() - 4), "%04X" % PixBrCode.crc16_ccitt(payload.substr(0, payload.length() - 4)), "CRC do payload do servico")
	eq(service.get_pix_payload(&"pacote_inexistente"), "", "pacote inexistente -> vazio")
	ok(not service.is_secure(), "gateway offline declara nao seguro")
	var key: String = str(Data.get_pix_config().get("pix_key", ""))
	eq(service.is_pix_configured(), not key.to_upper().begins_with("SUA-CHAVE") and key.strip_edges() != "", "is_pix_configured coerente com a chave")
