extends Node
## Sandbox: measures what a frozen tab does to the frame clock (docs/multiplayer.md section 6.9).
## Blocks the main thread with OS.delay_msec (what a frozen browser tab looks like from inside), then
## prints the _process delta of the first frame after it, the wall time that passed, the physics frames
## that ran and what Engine.max_physics_steps_per_frame allows.
## Run: tools/godot.sh --headless --path . res://src/net/debug/freeze_probe.tscn [-- --freeze-ms=5000]
## Add --fixed-fps 60 before the scene to see the fixed-step clock instead of the real one.

const WARMUP_FRAMES: int = 30
const DEFAULT_FREEZE_MS: int = 5000
const FREEZE_ARG: String = "--freeze-ms="
const FRAMES_AFTER: int = 6

var _frame: int = 0
var _freeze_ms: int = DEFAULT_FREEZE_MS
var _last_wall_ms: int = 0
var _physics_before: int = 0
var _freeze_done: bool = false
var _after: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(FREEZE_ARG):
			_freeze_ms = int(arg.trim_prefix(FREEZE_ARG))
	_last_wall_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	_frame += 1
	if _frame == WARMUP_FRAMES:
		_physics_before = Engine.get_physics_frames()
		OS.delay_msec(_freeze_ms)
		_freeze_done = true
		_last_wall_ms = now
		return
	if _freeze_done:
		_after += 1
		print("FREEZE_PROBE frame +%d: process delta %.4f s, wall gap %d ms, physics frames since freeze %d" % [
			_after, delta, now - _last_wall_ms, Engine.get_physics_frames() - _physics_before])
		if _after >= FRAMES_AFTER:
			print("FREEZE_PROBE froze %d ms; max_physics_steps_per_frame=%d physics_ticks_per_second=%d" % [
				_freeze_ms, Engine.max_physics_steps_per_frame, Engine.physics_ticks_per_second])
			get_tree().quit()
	_last_wall_ms = now
