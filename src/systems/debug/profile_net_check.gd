extends Node
## Debug check: Profile.apply_hunt_result with counts_for_progression and DISCONNECTED. Uses a temp save path.

var _fails: int = 0


func _ready() -> void:
	Profile.set_save_path("user://test_save_net.json")
	Profile.reset_progress()
	var map_id: StringName = Data.get_map_ids()[0]

	var a: HuntResult = _result(HuntResult.Outcome.VICTORY, map_id, false)
	var m0: int = Profile.get_money()
	Profile.apply_hunt_result(a)
	_eq(Profile.get_money(), m0 + a.total_money, "victory without progression pays")
	_eq(Profile.is_contract_unlocked(map_id, 1), false, "victory without progression does not unlock")
	_eq(Profile.is_contract_completed(map_id, 0), false, "victory without progression does not complete")
	_eq(int(Profile.get_stats()["hunts_won"]), 1, "hunts_won counts the win")

	var b: HuntResult = _result(HuntResult.Outcome.VICTORY, map_id, true)
	Profile.apply_hunt_result(b)
	_eq(Profile.is_contract_unlocked(map_id, 1), true, "victory with progression unlocks")

	var c: HuntResult = _result(HuntResult.Outcome.DISCONNECTED, map_id, false)
	var m1: int = Profile.get_money()
	Profile.apply_hunt_result(c)
	_eq(Profile.get_money(), m1 + c.total_money, "DISCONNECTED pays")
	_eq(int(Profile.get_stats()["hunts_won"]), 2, "DISCONNECTED is not a win")

	Profile.reset_progress()
	print("profile_net_check: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(_fails)


func _result(outcome: HuntResult.Outcome, map_id: StringName, counts: bool) -> HuntResult:
	var r: HuntResult = HuntResult.new()
	r.outcome = outcome
	r.map_id = map_id
	r.contract_index = 0
	r.total_money = 500
	r.counts_for_progression = counts
	return r


func _eq(got: Variant, want: Variant, label: String) -> void:
	if got != want:
		_fails += 1
		printerr("FAIL %s: got %s want %s" % [label, got, want])
