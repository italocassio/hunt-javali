extends "res://tests/lib/test_case.gd"
## tests/lib/child_runner.gd, the process runner behind net_test and net_unit: a suite that runs children must
## never report green for a child that failed, crashed or printed nothing.

const ChildRunner := preload("res://tests/lib/child_runner.gd")
const PROBE_SCENE: String = "res://tests/fixtures/child_probe.tscn"


func test_parse_summary_formats() -> void:
	var a: Dictionary = ChildRunner.parse_summary("noise\nRESULT: 30 passed, 2 failed, 1 skipped\n")
	ok(a["found"], "formato RESULT encontrado")
	eq(a["checks"], 32, "RESULT: passou + falhou")
	eq(a["failures"], 2, "RESULT: falhas")
	var b: Dictionary = ChildRunner.parse_summary("PASS x\nNET_HUNT_E2E checks=32 failures=0\n")
	ok(b["found"], "formato NET_HUNT_E2E")
	eq(b["checks"], 32, "checks")
	eq(b["failures"], 0, "failures")
	var c: Dictionary = ChildRunner.parse_summary("NET_E2E checks=111 failures=3")
	eq(c["failures"], 3, "NET_E2E com falhas")
	var d: Dictionary = ChildRunner.parse_summary("LINK_SELFTEST checks=73 failures=0")
	eq(d["checks"], 73, "LINK_SELFTEST")
	ok(ChildRunner.parse_summary("profile_net_check: OK")["found"], "profile_net_check OK")
	eq(ChildRunner.parse_summary("profile_net_check: OK")["failures"], 0, "profile_net_check sem falhas")
	eq(ChildRunner.parse_summary("profile_net_check: 4 FAILED")["failures"], 4, "profile_net_check com falhas")
	ok(ChildRunner.parse_summary("remote_sandbox: PASS (0 failures)")["found"], "remote_sandbox PASS")
	eq(ChildRunner.parse_summary("remote_sandbox: PASS (0 failures)")["failures"], 0, "remote_sandbox sem falhas")
	eq(ChildRunner.parse_summary("remote_sandbox: FAIL (3 failures)")["failures"], 3, "remote_sandbox com falhas")
	ok(int(ChildRunner.parse_summary("remote_sandbox: FAIL (0 failures)")["failures"]) > 0, "FAIL nunca vira verde")


func test_parse_summary_ignores_peer_lines_and_missing_summary() -> void:
	# A per-peer line that merely starts with the same words must not count as the orchestrator's summary.
	var peer: Dictionary = ChildRunner.parse_summary("NET_E2E_PEER checks=9 failures=0")
	ok(not peer["found"], "linha de par nao e resumo")
	var none: Dictionary = ChildRunner.parse_summary("")
	ok(not none["found"], "log vazio nao tem resumo")
	var last: Dictionary = ChildRunner.parse_summary("NET_E2E checks=5 failures=1\nNET_E2E checks=7 failures=0\n")
	eq(last["checks"], 7, "vale a ultima linha de resumo")
	var fails: Dictionary = ChildRunner.parse_summary("PASS a\nFAIL b: x\nSCRIPT ERROR: boom\nERROR: engine\n")
	eq((fails["fail_lines"] as Array).size(), 3, "linhas que explicam a falha")


func test_problems_verdicts() -> void:
	var green: Dictionary = {"started": true, "timed_out": false, "summary": true, "checks": 10, "failures": 0,
		"exit_code": 0, "secs": 1.0, "fail_lines": [] as Array[String], "log_path": "x"}
	eq(ChildRunner.problems(green, "h").size(), 0, "verde sem problemas")
	var failing: Dictionary = green.duplicate()
	failing["failures"] = 2
	ok(ChildRunner.problems(failing, "h").size() > 0, "falhas viram problema")
	var bad_exit: Dictionary = green.duplicate()
	bad_exit["exit_code"] = 1
	ok(ChildRunner.problems(bad_exit, "h").size() > 0, "codigo de saida 1 com 0 falhas e problema")
	var silent: Dictionary = green.duplicate()
	silent["summary"] = false
	ok(ChildRunner.problems(silent, "h").size() > 0, "sem resumo e problema")
	var empty: Dictionary = green.duplicate()
	empty["checks"] = 0
	ok(ChildRunner.problems(empty, "h").size() > 0, "0 verificacoes e problema (nada foi testado)")
	var timeout: Dictionary = green.duplicate()
	timeout["timed_out"] = true
	ok(ChildRunner.problems(timeout, "h").size() > 0, "estouro de tempo e problema")
	var not_started: Dictionary = green.duplicate()
	not_started["started"] = false
	ok(ChildRunner.problems(not_started, "h").size() > 0, "filho que nao iniciou e problema")


func test_real_child_failure_is_propagated() -> void:
	var runner: ChildRunner = ChildRunner.new(host)
	var r: Dictionary = await runner.run(PROBE_SCENE, "probe_fail", [], ["--mode=fail"], 60.0)
	runner.cleanup_logs()
	ok(r["started"], "filho iniciou")
	eq(r["checks"], 2, "2 verificacoes lidas do filho")
	eq(r["failures"], 1, "1 falha lida do filho")
	eq(r["exit_code"], 1, "codigo de saida do filho")
	var detail: Array = ChildRunner.problems(r, "h")
	ok(detail.size() > 0, "o filho que falhou vira FAIL")
	ok(str(detail).contains("second check"), "a linha FAIL do filho aparece no detalhe")


func test_real_child_without_summary_is_a_failure() -> void:
	var runner: ChildRunner = ChildRunner.new(host)
	var r: Dictionary = await runner.run(PROBE_SCENE, "probe_nosummary", [], ["--mode=nosummary"], 60.0)
	runner.cleanup_logs()
	ok(r["started"], "filho iniciou")
	ok(not r["summary"], "sem linha de resumo")
	eq(r["exit_code"], 0, "saiu com 0 mesmo assim")
	ok(ChildRunner.problems(r, "h").size() > 0, "saida 0 sem resumo NAO passa")
