extends RefCounted
## Base class of every test script plus the shared suite runner (docs/arquitetura.md section 12).
##
## A test script does `extends "res://tests/lib/test_case.gd"` and declares methods named `test_*`.
## Each test method runs on a fresh instance. Methods may be coroutines (use `await frames(2)`).
## Assertions record failures instead of aborting; engine/script errors raised while a test runs
## are also recorded as failures (unless the test calls `expect_errors()`).
##
## Outcome of a test: FAIL if anything failed, else SKIP if `skip()` was called, else PASS.

const WRITE_FAIL_LIMIT: int = 8

## Collects every engine error (push_error, script errors, shader errors). Warnings are ignored.
class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text: String = code if rationale == "" else "%s %s" % [code, rationale]
		_mutex.lock()
		errors.append("%s (%s:%d)" % [text.strip_edges(), file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n: int = errors.size()
		_mutex.unlock()
		return n

	func since(mark: int) -> Array[String]:
		_mutex.lock()
		var out: Array[String] = errors.slice(mark)
		_mutex.unlock()
		return out


static var catcher: ErrorCatcher = null

## Set by the runner.
var host: Node = null
var strict: bool = false

var _failures: Array[String] = []
var _skip_reason: String = ""
var _expect_errors: bool = false
var _tracked: Array[Node] = []
var _error_mark: int = 0
var _checks: int = 0


# --------------------------------------------------------------------------------------------
# Assertions
# --------------------------------------------------------------------------------------------

func ok(condition: bool, what: String = "") -> bool:
	_checks += 1
	if not condition:
		_fail("expected true: %s" % what)
	return condition


func eq(actual: Variant, expected: Variant, what: String = "") -> bool:
	_checks += 1
	if _same(actual, expected):
		return true
	_fail("%s: expected %s, got %s" % [what, _fmt(expected), _fmt(actual)])
	return false


func ne(actual: Variant, unexpected: Variant, what: String = "") -> bool:
	_checks += 1
	if not _same(actual, unexpected):
		return true
	_fail("%s: expected anything but %s" % [what, _fmt(unexpected)])
	return false


func near(actual: float, expected: float, eps: float, what: String = "") -> bool:
	_checks += 1
	if absf(actual - expected) <= eps:
		return true
	_fail("%s: expected %s +/- %s, got %s" % [what, expected, eps, actual])
	return false


func in_range(actual: float, low: float, high: float, what: String = "") -> bool:
	_checks += 1
	if actual >= low and actual <= high:
		return true
	_fail("%s: expected in [%s, %s], got %s" % [what, low, high, actual])
	return false


func contains(container: Variant, item: Variant, what: String = "") -> bool:
	_checks += 1
	var found: bool = false
	if container is String or container is StringName:
		found = String(container).contains(String(item))
	elif container is Dictionary:
		found = (container as Dictionary).has(item)
	elif container is Array or container is PackedStringArray or container is PackedInt32Array:
		found = item in container
	if not found:
		_fail("%s: %s does not contain %s" % [what, _fmt(container), _fmt(item)])
	return found


func fail(what: String) -> void:
	_checks += 1
	_fail(what)


## The test cannot run because a package has not delivered something yet.
func skip(reason: String) -> void:
	if _skip_reason == "":
		_skip_reason = reason


## Missing deliverable: SKIP normally, FAIL under --strict.
func skip_or_fail(reason: String) -> void:
	if strict:
		_checks += 1
		_fail("(strict) %s" % reason)
	else:
		skip(reason)


## Do not turn engine errors raised during this test into failures (the test provokes them).
func expect_errors() -> void:
	_expect_errors = true


func error_mark() -> int:
	return catcher.count() if catcher != null else 0


func errors_since(mark: int) -> Array[String]:
	if catcher == null:
		return []
	return catcher.since(mark)


# --------------------------------------------------------------------------------------------
# Loading helpers (tests never reference package classes by class_name; they load by path)
# --------------------------------------------------------------------------------------------

func need_script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		skip_or_fail("arquivo ainda nao entregue: %s" % path)
		return null
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		fail("script nao compila: %s" % path)
		return null
	return script


func need_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		skip_or_fail("cena ainda nao entregue: %s" % path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		fail("cena nao carrega: %s" % path)
		return null
	return scene


## True when the file is still the Phase 0 stub (header says "PHASE 0 STUB"). Marks the test SKIP.
func is_stub(path: String) -> bool:
	if not FileAccess.file_exists(path):
		skip_or_fail("arquivo ausente: %s" % path)
		return true
	var text: String = FileAccess.get_file_as_string(path)
	if text.contains("PHASE 0 STUB"):
		skip_or_fail("%s ainda e o stub da Fase 0" % path)
		return true
	return false


func call_static(script: Script, method: StringName, args: Array = []) -> Variant:
	return script.callv(method, args)


# --------------------------------------------------------------------------------------------
# Scene tree helpers
# --------------------------------------------------------------------------------------------

func track(node: Node, parent: Node = null) -> Node:
	var p: Node = parent if parent != null else host
	p.add_child(node)
	_tracked.append(node)
	return node


func tree() -> SceneTree:
	return host.get_tree()


func frames(count: int) -> void:
	for i: int in count:
		await host.get_tree().process_frame


func physics_frames(count: int) -> void:
	for i: int in count:
		await host.get_tree().physics_frame


## Waits `seconds` of game time (scaled by Engine.time_scale), at least one frame.
func wait_s(seconds: float) -> void:
	var left: float = seconds
	var last: int = Time.get_ticks_usec()
	while left > 0.0:
		await host.get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		left -= float(now - last) / 1000000.0 * Engine.time_scale
		last = now


## Waits for `sig` up to `timeout_s` real seconds. Returns the emitted args, or null on timeout.
func wait_signal(sig: Signal, timeout_s: float = 5.0) -> Variant:
	var state: Dictionary = {"fired": false, "args": []}
	var handler: Callable = func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null, e: Variant = null) -> void:
		state["fired"] = true
		state["args"] = [a, b, c, d, e]
	sig.connect(handler, CONNECT_ONE_SHOT)
	var start: int = Time.get_ticks_msec()
	while not state["fired"] and float(Time.get_ticks_msec() - start) / 1000.0 < timeout_s:
		await host.get_tree().process_frame
	if not state["fired"]:
		if sig.is_connected(handler):
			sig.disconnect(handler)
		return null
	return state["args"]


## Counts emissions of `sig` (up to 5 args) into the returned dictionary: {"count": n, "calls": [[args]...]}.
func record_signal(sig: Signal) -> Dictionary:
	var rec: Dictionary = {"count": 0, "calls": []}
	var handler: Callable = func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null, e: Variant = null) -> void:
		rec["count"] = int(rec["count"]) + 1
		(rec["calls"] as Array).append([a, b, c, d, e])
	sig.connect(handler)
	return rec


## Profile sandbox: every test that touches the profile starts here. Never touches user://save.json.
func fresh_profile() -> void:
	Profile.set_save_path("user://test_save.json")
	Profile.reset_progress()


func cleanup_test_files() -> void:
	for name: String in ["test_save.json", "test_save.bak.json", "test_save_alt.json", "test_save_alt.bak.json",
			"test_io.json", "test_io.bak.json"]:
		var abs_path: String = ProjectSettings.globalize_path("user://" + name)
		if FileAccess.file_exists("user://" + name):
			DirAccess.remove_absolute(abs_path)


func write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fail("nao consegui escrever %s" % path)
		return
	f.store_string(text)
	f.close()


func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fail("nao consegui escrever %s" % path)
		return
	f.store_buffer(bytes)
	f.close()


func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# --------------------------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------------------------

func _same(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if (ta == TYPE_FLOAT or ta == TYPE_INT) and (tb == TYPE_FLOAT or tb == TYPE_INT):
		if ta == TYPE_INT and tb == TYPE_INT:
			return a == b
		return is_equal_approx(float(a), float(b))
	if (ta == TYPE_STRING or ta == TYPE_STRING_NAME) and (tb == TYPE_STRING or tb == TYPE_STRING_NAME):
		return String(a) == String(b)
	if ta != tb:
		return false
	return a == b


func _fmt(v: Variant) -> String:
	var t: int = typeof(v)
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		return "\"%s\"" % String(v)
	var s: String = str(v)
	if s.length() > 160:
		s = s.substr(0, 157) + "..."
	return s


func _fail(message: String) -> void:
	var where: String = ""
	var own_source: String = (get_script() as Script).resource_path
	for frame: Dictionary in get_stack():
		var src: String = str(frame.get("source", ""))
		if src != own_source:
			where = "%s:%d (%s)" % [src, int(frame.get("line", 0)), str(frame.get("function", ""))]
			break
	_failures.append("%s -> %s" % [where, message] if where != "" else message)


# --------------------------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------------------------

static func new_totals() -> Dictionary:
	return {"pass": 0, "fail": 0, "skip": 0}


static func install_catcher() -> void:
	if catcher == null:
		catcher = ErrorCatcher.new()
		OS.add_logger(catcher)


static func remove_catcher() -> void:
	if catcher != null:
		OS.remove_logger(catcher)
		catcher = null


static func report(status: String, label: String, detail: Array, totals: Dictionary) -> void:
	totals[status.to_lower()] = int(totals[status.to_lower()]) + 1
	if detail.is_empty():
		print("%s %s" % [status, label])
		return
	print("%s %s: %s" % [status, label, str(detail[0])])
	var shown: int = mini(detail.size(), WRITE_FAIL_LIMIT)
	for i: int in range(1, shown):
		print("      %s" % str(detail[i]))
	if detail.size() > shown:
		print("      ... +%d more" % (detail.size() - shown))


static func finish(totals: Dictionary) -> int:
	print("RESULT: %d passed, %d failed, %d skipped" % [totals["pass"], totals["fail"], totals["skip"]])
	return 0 if int(totals["fail"]) == 0 else 1


## Begin/finish pair for code that is not a test method (check_scripts, flow_test).
func begin() -> void:
	_failures.clear()
	_skip_reason = ""
	_expect_errors = false
	_error_mark = error_mark()
	_checks = 0
	if strict:
		AssetLoader.clear_missing()


func conclude(label: String, totals: Dictionary) -> String:
	var details: Array = []
	details.append_array(_failures)
	if not _expect_errors:
		for err: String in errors_since(_error_mark):
			details.append("engine error: %s" % err)
	if strict:
		for path: String in AssetLoader.get_missing():
			details.append("(strict) fallback usado, asset ausente: %s" % path)
	var status: String = "PASS"
	if not details.is_empty():
		status = "FAIL"
	elif _skip_reason != "":
		status = "SKIP"
		details.append(_skip_reason)
	report(status, label, details, totals)
	_cleanup()
	return status


func _cleanup() -> void:
	for n: Node in _tracked:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_tracked.clear()
	Engine.time_scale = 1.0
	if host != null and host.is_inside_tree():
		host.get_tree().paused = false


static func run_script(path: String, host_node: Node, strict_mode: bool, totals: Dictionary) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		report("FAIL", path, ["script de teste nao compila"], totals)
		return
	var names: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var mname: String = str(m["name"])
		if mname.begins_with("test_"):
			names.append(mname)
	names.sort()
	if names.is_empty():
		report("FAIL", path, ["nenhum metodo test_* encontrado"], totals)
		return
	var base: String = path.get_file().get_basename()
	for mname: String in names:
		var inst: RefCounted = script.new()
		inst.set("host", host_node)
		inst.set("strict", strict_mode)
		inst.call("begin")
		var t0: int = Time.get_ticks_msec()
		await inst.call(mname)
		var ms: int = Time.get_ticks_msec() - t0
		var label: String = "%s::%s" % [base, mname.trim_prefix("test_")]
		if ms > 1500:
			label += " (%d ms)" % ms
		inst.call("conclude", label, totals)


static func list_scripts(dir_path: String, prefix: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.begins_with(prefix) and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
