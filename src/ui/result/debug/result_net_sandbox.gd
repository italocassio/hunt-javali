extends Node
## Debug sandbox: shows the result screen with a synthetic 3-player cooperative result.

const OUTCOME_NAMES: Array[StringName] = [&"VICTORY", &"DISCONNECTED"]


func _ready() -> void:
	var outcome: HuntResult.Outcome = HuntResult.Outcome.VICTORY
	if OS.get_cmdline_user_args().has("--disconnected"):
		outcome = HuntResult.Outcome.DISCONNECTED
	var map_id: StringName = Data.get_map_ids()[0]
	var r: HuntResult = HuntResult.new()
	r.outcome = outcome
	r.map_id = map_id
	r.contract_index = 0
	r.boars_total = 14
	r.team_kills = 14 if outcome == HuntResult.Outcome.VICTORY else 9
	r.player_count = 3
	r.counts_for_progression = outcome == HuntResult.Outcome.VICTORY
	for i: int in 5:
		var k: KillInfo = KillInfo.new()
		k.type_id = Data.get_boar_type_ids()[0]
		k.weight_kg = 60.0 + 7.5 * i
		k.reward_money = 120 + 15 * i
		k.clean_kill = i % 2 == 0
		k.killing_zone = &"vital"
		r.kills.append(k)
		r.money_from_kills += k.reward_money
	r.contract_bonus = 400 if outcome == HuntResult.Outcome.VICTORY else 0
	r.total_money = r.money_from_kills + r.contract_bonus
	r.crop_health_pct = 82.0
	r.duration_s = 312.0
	r.scoreboard = [
		{"slot": 0, "name": "Italo", "kills": 5, "money": r.money_from_kills, "weight_kg": 375.0},
		{"slot": 1, "name": "", "kills": 6, "money": 700, "weight_kg": 410.5},
		{"slot": 2, "name": "Marcela", "kills": 3, "money": 300, "weight_kg": 190.0},
	]
	Router.last_result = r
	add_child((load(ScenePaths.RESULT) as PackedScene).instantiate())
