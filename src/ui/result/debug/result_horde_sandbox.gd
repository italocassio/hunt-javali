extends Node
## Debug sandbox for the horde result screen (docs/horda.md 10.3). Headless, no window needed.
## Run: tools/godot.sh --headless --path . res://src/ui/result/debug/result_horde_sandbox.tscn
## Prints PASS/FAIL per item and exits with code 1 on any failure. Uses a throwaway save path.

const SAVE_PATH: String = "user://result_horde_sandbox.json"
const WAVES_TOTAL: int = 8
const WAVES_CLEARED: int = 5
const EXPECTED_TITLES: Dictionary = {
	HuntResult.Outcome.VICTORY: "Celeiro defendido!",
	HuntResult.Outcome.DEFEAT_CROP: "O celeiro foi devorado",
	HuntResult.Outcome.DEFEAT_DEATH: "Derrota: os caçadores caíram",
	HuntResult.Outcome.ABANDONED: "Horda abandonada",
	HuntResult.Outcome.DISCONNECTED: "Conexão perdida: a caçada foi encerrada",
}

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.set_save_path(SAVE_PATH)
	var saved_result: HuntResult = Router.last_result
	for outcome: int in EXPECTED_TITLES:
		await _check_horde(outcome)
	await _check_contract_unchanged()
	Router.last_result = saved_result
	for path: String in [SAVE_PATH, SAVE_PATH.replace(".json", ".bak.json")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT_HORDE_SANDBOX checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures += 1


func _make_result(outcome: int, horde: bool) -> HuntResult:
	var r: HuntResult = HuntResult.new()
	r.outcome = outcome as HuntResult.Outcome
	r.map_id = Data.get_map_ids()[0]
	r.contract_index = 0
	r.boars_total = 20
	r.team_kills = 11
	r.counts_for_progression = not horde
	if horde:
		r.mode = Ids.MODE_HORDE
		r.horde_wave_count = WAVES_TOTAL
		r.horde_waves_cleared = WAVES_TOTAL if outcome == HuntResult.Outcome.VICTORY else WAVES_CLEARED
	for i: int in 3:
		var k: KillInfo = KillInfo.new()
		k.type_id = Data.get_boar_type_ids()[0]
		k.weight_kg = 70.0 + 5.0 * i
		k.reward_money = 100 + 10 * i
		k.killing_zone = &"vital"
		r.kills.append(k)
		r.money_from_kills += k.reward_money
	if outcome == HuntResult.Outcome.VICTORY:
		r.contract_bonus = 2610
	r.total_money = r.money_from_kills + r.contract_bonus
	r.crop_health_pct = 87.0
	r.duration_s = 400.0
	return r


func _screen(r: HuntResult) -> Control:
	Router.last_result = r
	var screen: Control = (load(ScenePaths.RESULT) as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	return screen


func _texts(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	for c: Node in node.get_children():
		_texts(c, out)


func _joined(screen: Node) -> String:
	var out: PackedStringArray = []
	_texts(screen, out)
	return "\n".join(out)


func _check_horde(outcome: int) -> void:
	var tag: String = HuntResult.Outcome.keys()[outcome]
	var r: HuntResult = _make_result(outcome, true)
	var screen: Control = await _screen(r)
	var text: String = _joined(screen)
	_ok(text.contains(EXPECTED_TITLES[outcome]), "%s titulo '%s'" % [tag, EXPECTED_TITLES[outcome]])
	var expected_waves: String = "%d de %d" % [r.horde_waves_cleared, WAVES_TOTAL]
	_ok(text.contains("Ondas vencidas") and text.contains(expected_waves), "%s Ondas vencidas: %s" % [tag, expected_waves])
	_ok(text.contains("Celeiro preservado") and not text.contains("Lavoura preservada"), "%s Celeiro preservado" % tag)
	_ok(text.contains("Bônus de defesa") and not text.contains("Bônus do contrato"), "%s Bônus de defesa" % tag)
	_ok(text.contains("Horda Javali  |  "), "%s cabecalho Horda Javali  |  mapa" % tag)
	_ok(text.contains("Abates: 3") and not text.contains(" de 20 javalis"), "%s abates sem 'de N'" % tag)
	_ok(not text.contains("Próximo contrato liberado") and not text.contains("ainda não estava liberado"), "%s sem meta de proximo contrato" % tag)
	var retry: Button = screen.get_node_or_null("%RetryButton") as Button
	_ok(retry != null and not retry.visible, "%s RetryButton invisivel" % tag)
	var cont: Button = screen.get_node_or_null("%ContinueButton") as Button
	_ok(cont != null and cont.visible, "%s ContinueButton visivel" % tag)
	if outcome == HuntResult.Outcome.VICTORY:
		_ok(text.contains("Celeiro em 87% de "), "%s Celeiro em 87%% de ..." % tag)
	elif outcome != HuntResult.Outcome.DISCONNECTED:
		_ok(text.contains("Só na vitória (até "), "%s Só na vitória (até ...)" % tag)
	screen.queue_free()
	await get_tree().process_frame


func _check_contract_unchanged() -> void:
	var r: HuntResult = _make_result(HuntResult.Outcome.VICTORY, false)
	var screen: Control = await _screen(r)
	var text: String = _joined(screen)
	_ok(text.contains("Vitória! Lavoura salva"), "contrato: titulo de vitoria")
	_ok(text.contains("Contrato 1: "), "contrato: cabecalho Contrato 1")
	_ok(text.contains("Lavoura preservada") and text.contains("Bônus do contrato"), "contrato: rotulos de lavoura e bonus")
	_ok(not text.contains("Ondas vencidas") and not text.contains("Celeiro"), "contrato: sem texto de horda")
	var retry: Button = screen.get_node_or_null("%RetryButton") as Button
	_ok(retry != null and retry.visible, "contrato: RetryButton visivel")
	screen.queue_free()
	await get_tree().process_frame
