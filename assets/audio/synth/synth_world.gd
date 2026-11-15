class_name SynthWorld
extends RefCounted
## Procedural fallback for world ambience, stings and UI sounds (used only when the recorded file is missing,
## see Sfx). Loops are built lazily (LAZY_IDS).

## Synthesized on first use (loops and the horde stings), never at startup.
const LAZY_IDS: Array[StringName] = [&"amb_cerrado_loop", &"amb_wind_loop", &"horde_wave_start", &"horde_wave_clear"]
## Ids written by build().
const IDS: Array[StringName] = [&"bait_drop", &"victory_sting", &"defeat_sting", &"ui_click", &"ui_buy",
	&"ui_error", &"ui_coin"]


static func build(out: Dictionary) -> void:
	out[&"bait_drop"] = _bait()
	out[&"victory_sting"] = _victory()
	out[&"defeat_sting"] = _defeat()
	out[&"ui_click"] = _click()
	out[&"ui_buy"] = _buy()
	out[&"ui_error"] = _error()
	out[&"ui_coin"] = _coin()


static func build_lazy(id: StringName) -> AudioStreamWAV:
	match id:
		&"amb_cerrado_loop": return _cerrado()
		&"amb_wind_loop": return _wind()
		&"horde_wave_start": return _horde_wave_start()
		&"horde_wave_clear": return _horde_wave_clear()
	return null


static func _bait() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.45)
	SynthDsp.noise(b, 0.0, 0.35, 0.8, 0.12, 0.3, 0.05, 0.01)
	SynthDsp.tone(b, 0.0, 0.2, 100.0, 55.0, 0.8, 0.06, SynthDsp.SHAPE_SINE, 0.002)
	for i in 5:
		SynthDsp.noise(b, 0.1 + i * 0.05, 0.03, 0.5, 0.01, 0.7, 0.2, 0.001)
	return SynthDsp.to_stream(b, 0.65)


static func _chord(b: PackedFloat32Array, t: float, notes: Array, dur: float, amp: float, shape: int) -> void:
	for s: float in notes:
		var f: float = SynthDsp.note(s)
		SynthDsp.tone(b, t, dur, f, f, amp, dur * 0.5, shape, 0.01)


static func _victory() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(1.3)
	var seq: Array = [-9.0, -5.0, -2.0, 3.0]
	for i in 4:
		var f: float = SynthDsp.note(seq[i])
		SynthDsp.tone(b, i * 0.14, 0.5, f, f, 0.5, 0.2, SynthDsp.SHAPE_TRI, 0.006)
	_chord(b, 0.6, [3.0, 7.0, 10.0, 15.0], 0.7, 0.28, SynthDsp.SHAPE_TRI)
	return SynthDsp.to_stream(b, 0.6)


static func _defeat() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(1.3)
	var seq: Array = [0.0, -2.0, -5.0, -9.0]
	for i in 4:
		var f: float = SynthDsp.note(seq[i] - 12.0)
		SynthDsp.tone(b, i * 0.25, 0.7, f, f * 0.97, 0.5, 0.35, SynthDsp.SHAPE_SAW, 0.01)
	SynthDsp.drive(b, 1.3)
	return SynthDsp.to_stream(b, 0.55)


## Low horn (berrante), ~1.5 s: a short pickup note, then a long one that bends up a little.
static func _horde_wave_start() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(1.6)
	var low: float = SynthDsp.note(-26.0)   # ~98 Hz
	var high: float = SynthDsp.note(-21.0)
	SynthDsp.tone(b, 0.0, 0.32, low, low * 1.02, 0.6, 0.6, SynthDsp.SHAPE_SAW, 0.05, 0.0, 0.0, 5.5, 0.006)
	SynthDsp.tone(b, 0.0, 0.32, low * 2.0, low * 2.04, 0.25, 0.4, SynthDsp.SHAPE_TRI, 0.05)
	SynthDsp.tone(b, 0.38, 1.2, high * 0.96, high, 0.6, 0.9, SynthDsp.SHAPE_SAW, 0.07, 0.0, 0.0, 5.5, 0.008)
	SynthDsp.tone(b, 0.38, 1.2, high * 1.92, high * 2.0, 0.25, 0.7, SynthDsp.SHAPE_TRI, 0.07)
	SynthDsp.noise(b, 0.38, 1.0, 0.05, 0.6, 0.15, 0.0, 0.1)
	SynthDsp.drive(b, 1.4)
	return SynthDsp.to_stream(b, 0.65)


## Relief vinette, ~1 s: soft rising three-note arpeggio, lighter than the victory sting.
static func _horde_wave_clear() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(1.1)
	var seq: Array = [-5.0, -1.0, 2.0]
	for i in 3:
		var f: float = SynthDsp.note(seq[i])
		SynthDsp.tone(b, i * 0.16, 0.5, f, f, 0.45, 0.18, SynthDsp.SHAPE_SINE, 0.008)
	_chord(b, 0.5, [2.0, 7.0, 11.0], 0.55, 0.25, SynthDsp.SHAPE_SINE)
	return SynthDsp.to_stream(b, 0.5)


static func _click() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.07)
	SynthDsp.tone(b, 0.0, 0.06, 900.0, 600.0, 0.8, 0.02, SynthDsp.SHAPE_SINE, 0.0005)
	SynthDsp.noise(b, 0.0, 0.015, 0.25, 0.005, 0.6, 0.2, 0.0003)
	return SynthDsp.to_stream(b, 0.5)


static func _coin() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.35)
	SynthDsp.tone(b, 0.0, 0.08, 1568.0, 1568.0, 0.7, 0.05, SynthDsp.SHAPE_SQUARE, 0.001)
	SynthDsp.tone(b, 0.07, 0.28, 2093.0, 2093.0, 0.7, 0.1, SynthDsp.SHAPE_SQUARE, 0.001)
	return SynthDsp.to_stream(b, 0.45)


static func _buy() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.3)
	SynthDsp.tone(b, 0.0, 0.1, SynthDsp.note(0.0), SynthDsp.note(0.0), 0.6, 0.06, SynthDsp.SHAPE_TRI, 0.002)
	SynthDsp.tone(b, 0.08, 0.1, SynthDsp.note(4.0), SynthDsp.note(4.0), 0.6, 0.06, SynthDsp.SHAPE_TRI, 0.002)
	SynthDsp.tone(b, 0.16, 0.14, SynthDsp.note(7.0), SynthDsp.note(7.0), 0.7, 0.08, SynthDsp.SHAPE_TRI, 0.002)
	return SynthDsp.to_stream(b, 0.5)


static func _error() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.25)
	SynthDsp.tone(b, 0.0, 0.1, 220.0, 220.0, 0.7, 0.2, SynthDsp.SHAPE_SQUARE, 0.002)
	SynthDsp.tone(b, 0.11, 0.13, 165.0, 165.0, 0.7, 0.2, SynthDsp.SHAPE_SQUARE, 0.002)
	return SynthDsp.to_stream(b, 0.45)


## 3 s of wind, cicadas and a few bird calls. Seamless loop.
static func _cerrado() -> AudioStreamWAV:
	var total: float = 3.3
	var b: PackedFloat32Array = SynthDsp.buf(total)
	SynthDsp.noise(b, 0.0, total, 0.22, 100.0, 0.05, 0.0, 0.05, 0.4, 0.5)
	# cicadas: high noise gated at ~38 Hz in slow swells
	SynthDsp.noise(b, 0.0, total, 0.09, 100.0, 0.9, 0.55, 0.05, 38.0, 0.9)
	SynthDsp.tone(b, 0.0, total, 4300.0, 4300.0, 0.03, 100.0, SynthDsp.SHAPE_SINE, 0.05, 45.0, 0.9)
	# birds
	for t: float in [0.6, 0.72, 0.84, 2.1, 2.25]:
		SynthDsp.tone(b, t, 0.09, 2400.0, 3300.0, 0.18, 0.05, SynthDsp.SHAPE_SINE, 0.005)
	SynthDsp.tone(b, 1.5, 0.35, 1400.0, 900.0, 0.12, 0.2, SynthDsp.SHAPE_SINE, 0.02, 0.0, 0.0, 9.0, 0.06)
	return SynthDsp.to_stream(SynthDsp.make_loop(b, 0.3), 0.6, true)


static func _wind() -> AudioStreamWAV:
	var total: float = 3.4
	var b: PackedFloat32Array = SynthDsp.buf(total)
	SynthDsp.noise(b, 0.0, total, 0.7, 100.0, 0.07, 0.0, 0.05, 0.5, 0.6)
	SynthDsp.noise(b, 0.0, total, 0.25, 100.0, 0.2, 0.05, 0.05, 0.9, 0.7)
	return SynthDsp.to_stream(SynthDsp.make_loop(b, 0.4), 0.6, true)
