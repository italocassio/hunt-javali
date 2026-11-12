class_name SynthWeapons
extends RefCounted
## Gunshots, mechanics, impacts, player and HUD sounds.


const SHOT_IDS: Array[StringName] = [&"shot_22", &"shot_12", &"shot_308", &"shot_3006", &"shot_338"]


## Gunshots are the most expensive sounds: built on first use, not at startup.
static func build_shot(id: StringName) -> AudioStreamWAV:
	match id:
		&"shot_22": return _shot(0.4, 1.0, 0.95, 0.03, 0.6, 280.0, 120.0, 0.4, 0.07, 0.15)
		&"shot_12": return _shot(0.7, 0.9, 0.7, 0.09, 0.3, 120.0, 38.0, 1.0, 0.16, 0.45)
		&"shot_308": return _shot(0.6, 1.0, 0.9, 0.05, 0.45, 150.0, 48.0, 0.9, 0.12, 0.3)
		&"shot_3006": return _shot(0.65, 1.0, 0.85, 0.06, 0.38, 125.0, 42.0, 1.0, 0.15, 0.35)
		&"shot_338": return _shot(0.9, 1.0, 0.8, 0.08, 0.3, 95.0, 30.0, 1.1, 0.22, 0.5)
	return null


static func build(out: Dictionary) -> void:
	out[&"dry_fire"] = _click_pair(0.1, 0.0, 0.0, 3200.0)
	out[&"reload_start"] = _click_pair(0.25, 0.0, 0.09, 1800.0)
	out[&"reload_end"] = _click_pair(0.28, 0.0, 0.12, 1300.0, 1.0)
	out[&"bolt_cycle"] = _bolt()
	out[&"pump_cycle"] = _pump()
	out[&"weapon_swap"] = _swap()
	out[&"scope_in"] = _whoosh(0.22, true)
	out[&"scope_out"] = _whoosh(0.2, false)
	out[&"impact_dirt"] = _impact_dirt()
	out[&"impact_wood"] = _impact_wood()
	out[&"impact_flesh"] = _impact_flesh()
	out[&"step_grass"] = _step(0.16, 0.35, 0.02)
	out[&"step_dirt"] = _step(0.14, 0.18, 0.15)
	out[&"player_hurt"] = _hurt()
	out[&"player_heal"] = _heal()
	out[&"player_death"] = _death()
	out[&"heartbeat"] = _heartbeat()
	out[&"binocular_in"] = _whoosh(0.28, true, 0.6)
	out[&"hit_marker"] = _tick()
	out[&"kill_confirm"] = _kill()
	out[&"crop_alarm"] = _alarm()
	out[&"drone_buzz"] = _drone()


static func _shot(dur: float, crack_amp: float, crack_lp: float, crack_tau: float, body_amp: float, f0: float, f1: float, thump_amp: float, body_tau: float, tail_amp: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(dur)
	SynthDsp.noise(b, 0.0, 0.06, crack_amp, crack_tau, crack_lp, 0.15)
	SynthDsp.noise(b, 0.0, dur, body_amp, body_tau, 0.3, 0.0)
	SynthDsp.tone(b, 0.0, 0.3, f0, f1, thump_amp, body_tau * 0.8, SynthDsp.SHAPE_SINE, 0.001)
	SynthDsp.noise(b, 0.04, dur - 0.04, tail_amp, body_tau * 2.2, 0.07)
	SynthDsp.drive(b, 1.8)
	return SynthDsp.to_stream(b, 0.95)


static func _click_pair(dur: float, t_a: float, t_b: float, freq: float, vol: float = 0.8) -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(dur)
	SynthDsp.noise(b, t_a, 0.03, 0.8, 0.006, 0.9, 0.2, 0.0005)
	SynthDsp.tone(b, t_a, 0.04, freq, freq * 0.6, 0.5, 0.01, SynthDsp.SHAPE_SQUARE, 0.0005)
	if t_b > 0.0:
		SynthDsp.noise(b, t_b, 0.05, vol, 0.012, 0.7, 0.2, 0.0005)
		SynthDsp.tone(b, t_b, 0.06, freq * 0.7, freq * 0.4, 0.5, 0.015, SynthDsp.SHAPE_SQUARE, 0.0005)
	return SynthDsp.to_stream(b, 0.7)


static func _bolt() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.5)
	for t: float in [0.0, 0.09, 0.26, 0.37]:
		SynthDsp.noise(b, t, 0.04, 0.7, 0.01, 0.6, 0.2, 0.0005)
		SynthDsp.tone(b, t, 0.05, 1500.0 if t < 0.2 else 900.0, 600.0, 0.4, 0.012, SynthDsp.SHAPE_SQUARE, 0.0005)
	return SynthDsp.to_stream(b, 0.7)


static func _pump() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.4)
	SynthDsp.noise(b, 0.0, 0.06, 0.9, 0.02, 0.5, 0.1, 0.0005)
	SynthDsp.tone(b, 0.0, 0.08, 500.0, 260.0, 0.6, 0.03, SynthDsp.SHAPE_SQUARE, 0.0005)
	SynthDsp.noise(b, 0.2, 0.08, 1.0, 0.025, 0.5, 0.1, 0.0005)
	SynthDsp.tone(b, 0.2, 0.1, 380.0, 180.0, 0.7, 0.04, SynthDsp.SHAPE_SQUARE, 0.0005)
	return SynthDsp.to_stream(b, 0.75)


static func _swap() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.3)
	SynthDsp.noise(b, 0.0, 0.18, 0.5, 0.07, 0.2, 0.05, 0.03)
	SynthDsp.noise(b, 0.17, 0.05, 0.8, 0.012, 0.6, 0.2, 0.0005)
	SynthDsp.tone(b, 0.17, 0.06, 1100.0, 600.0, 0.4, 0.015, SynthDsp.SHAPE_SQUARE, 0.0005)
	return SynthDsp.to_stream(b, 0.65)


static func _whoosh(dur: float, rising: bool, amp: float = 1.0) -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(dur)
	var steps: int = 4
	for s in steps:
		var k: float = float(s) / float(steps)
		var lp: float = lerpf(0.06, 0.35, k) if rising else lerpf(0.35, 0.06, k)
		SynthDsp.noise(b, k * dur, dur / steps, 0.7 * amp, 1.0, lp, 0.02, 0.01)
	SynthDsp.tone(b, 0.0, dur, 300.0 if rising else 600.0, 700.0 if rising else 250.0, 0.12 * amp, 1.0, SynthDsp.SHAPE_SINE, 0.02)
	return SynthDsp.to_stream(b, 0.45)


static func _impact_dirt() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.25)
	SynthDsp.noise(b, 0.0, 0.2, 1.0, 0.04, 0.22, 0.0, 0.001)
	SynthDsp.tone(b, 0.0, 0.15, 110.0, 55.0, 0.8, 0.04, SynthDsp.SHAPE_SINE, 0.001)
	SynthDsp.noise(b, 0.0, 0.05, 0.4, 0.015, 0.8, 0.2, 0.0005)
	return SynthDsp.to_stream(b, 0.8)


static func _impact_wood() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.25)
	SynthDsp.tone(b, 0.0, 0.2, 420.0, 300.0, 0.8, 0.05, SynthDsp.SHAPE_TRI, 0.0008)
	SynthDsp.tone(b, 0.0, 0.15, 910.0, 700.0, 0.4, 0.03, SynthDsp.SHAPE_SINE, 0.0008)
	SynthDsp.noise(b, 0.0, 0.05, 0.7, 0.012, 0.6, 0.1, 0.0005)
	return SynthDsp.to_stream(b, 0.8)


static func _impact_flesh() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.25)
	SynthDsp.tone(b, 0.0, 0.18, 90.0, 45.0, 1.0, 0.045, SynthDsp.SHAPE_SINE, 0.001)
	SynthDsp.noise(b, 0.0, 0.18, 0.7, 0.035, 0.14, 0.0, 0.001)
	SynthDsp.noise(b, 0.0, 0.03, 0.3, 0.01, 0.5, 0.1, 0.0005)
	return SynthDsp.to_stream(b, 0.85)


static func _step(dur: float, lp: float, hp: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(dur)
	SynthDsp.noise(b, 0.0, dur, 1.0, dur * 0.3, lp, hp, 0.004)
	SynthDsp.tone(b, 0.0, 0.08, 120.0, 70.0, 0.4, 0.03, SynthDsp.SHAPE_SINE, 0.002)
	return SynthDsp.to_stream(b, 0.45)


static func _hurt() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.35)
	SynthDsp.tone(b, 0.0, 0.3, 190.0, 120.0, 0.8, 0.12, SynthDsp.SHAPE_SAW, 0.01, 0.0, 0.0, 14.0, 0.05)
	SynthDsp.noise(b, 0.0, 0.1, 0.5, 0.03, 0.4, 0.0, 0.002)
	SynthDsp.drive(b, 1.5)
	return SynthDsp.to_stream(b, 0.7)


static func _heal() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.5)
	var i: int = 0
	for s: float in [0.0, 4.0, 7.0, 12.0]:
		var f: float = SynthDsp.note(s + 3.0)
		SynthDsp.tone(b, i * 0.07, 0.4 - i * 0.05, f, f, 0.6, 0.12, SynthDsp.SHAPE_SINE, 0.004)
		SynthDsp.tone(b, i * 0.07, 0.3, f * 2.0, f * 2.0, 0.15, 0.08, SynthDsp.SHAPE_SINE, 0.004)
		i += 1
	return SynthDsp.to_stream(b, 0.6)


static func _death() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.9)
	SynthDsp.tone(b, 0.0, 0.8, 160.0, 45.0, 0.9, 0.35, SynthDsp.SHAPE_SAW, 0.01, 0.0, 0.0, 6.0, 0.04)
	SynthDsp.noise(b, 0.0, 0.8, 0.5, 0.3, 0.1, 0.0, 0.01)
	SynthDsp.tone(b, 0.0, 0.3, 70.0, 35.0, 1.0, 0.1, SynthDsp.SHAPE_SINE, 0.002)
	SynthDsp.drive(b, 1.5)
	return SynthDsp.to_stream(b, 0.7)


static func _heartbeat() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.7)
	SynthDsp.tone(b, 0.0, 0.2, 75.0, 45.0, 1.0, 0.06, SynthDsp.SHAPE_SINE, 0.004)
	SynthDsp.tone(b, 0.2, 0.25, 65.0, 40.0, 0.7, 0.07, SynthDsp.SHAPE_SINE, 0.004)
	SynthDsp.noise(b, 0.0, 0.1, 0.15, 0.03, 0.1, 0.0, 0.004)
	return SynthDsp.to_stream(b, 0.85)


static func _tick() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.07)
	SynthDsp.tone(b, 0.0, 0.06, 1800.0, 1400.0, 0.8, 0.02, SynthDsp.SHAPE_SINE, 0.0005)
	SynthDsp.noise(b, 0.0, 0.02, 0.3, 0.006, 0.7, 0.2, 0.0003)
	return SynthDsp.to_stream(b, 0.6)


static func _kill() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.35)
	SynthDsp.tone(b, 0.0, 0.12, SynthDsp.note(3.0), SynthDsp.note(3.0), 0.7, 0.07, SynthDsp.SHAPE_SQUARE, 0.002)
	SynthDsp.tone(b, 0.09, 0.26, SynthDsp.note(10.0), SynthDsp.note(10.0), 0.7, 0.12, SynthDsp.SHAPE_SQUARE, 0.002)
	SynthDsp.tone(b, 0.09, 0.26, SynthDsp.note(22.0), SynthDsp.note(22.0), 0.25, 0.08, SynthDsp.SHAPE_SINE, 0.002)
	return SynthDsp.to_stream(b, 0.55)


static func _alarm() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.7)
	for i in 4:
		var f: float = 880.0 if i % 2 == 0 else 660.0
		SynthDsp.tone(b, i * 0.17, 0.15, f, f, 0.7, 0.5, SynthDsp.SHAPE_SQUARE, 0.003)
	return SynthDsp.to_stream(b, 0.5)


static func _drone() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.5)
	SynthDsp.tone(b, 0.0, 0.5, 150.0, 150.0, 0.6, 5.0, SynthDsp.SHAPE_SAW, 0.02, 90.0, 0.4)
	SynthDsp.noise(b, 0.0, 0.5, 0.15, 5.0, 0.5, 0.2, 0.02)
	return SynthDsp.to_stream(b, 0.4)
