class_name SynthAnimals
extends RefCounted
## Boar and dog voices.


static func build(out: Dictionary) -> void:
	out[&"boar_grunt"] = _grunt()
	out[&"boar_squeal"] = _squeal(0.6, 900.0, 1500.0, 700.0)
	out[&"boar_snort_alert"] = _snort()
	out[&"boar_scrape"] = _scrape()
	out[&"boar_charge_roar"] = _roar()
	out[&"boar_eat"] = _eat()
	out[&"boar_death"] = _squeal(0.9, 1300.0, 1100.0, 220.0)
	out[&"dog_bark"] = _bark()
	out[&"dog_growl"] = _growl()
	out[&"dog_yelp"] = _yelp()
	out[&"dog_whine"] = _whine()


static func _grunt() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.4)
	SynthDsp.tone(b, 0.0, 0.35, 110.0, 80.0, 0.8, 0.18, SynthDsp.SHAPE_SAW, 0.02, 0.0, 0.0, 22.0, 0.08)
	SynthDsp.tone(b, 0.0, 0.3, 220.0, 150.0, 0.3, 0.12, SynthDsp.SHAPE_SQUARE, 0.02)
	SynthDsp.noise(b, 0.0, 0.3, 0.35, 0.12, 0.25, 0.0, 0.02)
	SynthDsp.drive(b, 1.6)
	return SynthDsp.to_stream(b, 0.75)


static func _squeal(dur: float, f0: float, f_mid: float, f1: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(dur)
	SynthDsp.tone(b, 0.0, dur * 0.4, f0, f_mid, 0.8, 1.0, SynthDsp.SHAPE_SAW, 0.01, 0.0, 0.0, 30.0, 0.04)
	SynthDsp.tone(b, dur * 0.4, dur * 0.6, f_mid, f1, 0.8, dur * 0.5, SynthDsp.SHAPE_SAW, 0.005, 0.0, 0.0, 30.0, 0.04)
	SynthDsp.tone(b, 0.0, dur, f0 * 1.5, f1 * 1.5, 0.25, dur * 0.6, SynthDsp.SHAPE_SQUARE, 0.01)
	SynthDsp.noise(b, 0.0, dur, 0.25, dur * 0.5, 0.5, 0.1, 0.01)
	SynthDsp.drive(b, 1.4)
	return SynthDsp.to_stream(b, 0.7)


static func _snort() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.45)
	SynthDsp.noise(b, 0.0, 0.14, 1.0, 0.06, 0.3, 0.05, 0.01)
	SynthDsp.noise(b, 0.18, 0.2, 1.0, 0.09, 0.28, 0.05, 0.015)
	SynthDsp.tone(b, 0.0, 0.3, 120.0, 90.0, 0.25, 0.1, SynthDsp.SHAPE_SAW, 0.02)
	return SynthDsp.to_stream(b, 0.7)


static func _scrape() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.55)
	for i in 3:
		SynthDsp.noise(b, i * 0.17, 0.15, 0.9, 0.07, 0.5, 0.2, 0.01)
	SynthDsp.tone(b, 0.0, 0.5, 70.0, 60.0, 0.3, 0.3, SynthDsp.SHAPE_SINE, 0.02)
	return SynthDsp.to_stream(b, 0.65)


static func _roar() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.95)
	SynthDsp.tone(b, 0.0, 0.9, 62.0, 105.0, 0.9, 1.2, SynthDsp.SHAPE_SAW, 0.12, 26.0, 0.55, 5.0, 0.04)
	SynthDsp.tone(b, 0.0, 0.9, 124.0, 190.0, 0.35, 1.2, SynthDsp.SHAPE_SQUARE, 0.15, 26.0, 0.55)
	SynthDsp.noise(b, 0.0, 0.9, 0.5, 1.0, 0.18, 0.0, 0.15, 26.0, 0.5)
	SynthDsp.drive(b, 2.2)
	return SynthDsp.to_stream(b, 0.85)


static func _eat() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.45)
	for i in 5:
		var t: float = i * 0.085
		SynthDsp.noise(b, t, 0.06, 0.8 - i * 0.05, 0.02, 0.45, 0.1, 0.002)
		SynthDsp.tone(b, t, 0.05, 260.0, 180.0, 0.3, 0.015, SynthDsp.SHAPE_TRI, 0.001)
	return SynthDsp.to_stream(b, 0.55)


static func _bark() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.28)
	SynthDsp.tone(b, 0.0, 0.2, 520.0, 300.0, 0.8, 0.07, SynthDsp.SHAPE_SAW, 0.004, 0.0, 0.0, 12.0, 0.03)
	SynthDsp.tone(b, 0.0, 0.18, 1040.0, 600.0, 0.3, 0.05, SynthDsp.SHAPE_SQUARE, 0.004)
	SynthDsp.noise(b, 0.0, 0.12, 0.35, 0.04, 0.35, 0.05, 0.002)
	SynthDsp.drive(b, 1.6)
	return SynthDsp.to_stream(b, 0.75)


static func _growl() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.65)
	SynthDsp.tone(b, 0.0, 0.6, 85.0, 70.0, 0.8, 0.8, SynthDsp.SHAPE_SAW, 0.08, 32.0, 0.5, 6.0, 0.05)
	SynthDsp.noise(b, 0.0, 0.6, 0.35, 0.8, 0.2, 0.0, 0.08, 32.0, 0.5)
	SynthDsp.drive(b, 2.0)
	return SynthDsp.to_stream(b, 0.7)


static func _yelp() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.32)
	SynthDsp.tone(b, 0.0, 0.12, 650.0, 1250.0, 0.8, 0.3, SynthDsp.SHAPE_SAW, 0.004)
	SynthDsp.tone(b, 0.12, 0.2, 1250.0, 700.0, 0.8, 0.1, SynthDsp.SHAPE_SAW, 0.004)
	SynthDsp.noise(b, 0.0, 0.2, 0.15, 0.1, 0.5, 0.1, 0.004)
	return SynthDsp.to_stream(b, 0.65)


static func _whine() -> AudioStreamWAV:
	var b: PackedFloat32Array = SynthDsp.buf(0.65)
	SynthDsp.tone(b, 0.0, 0.62, 850.0, 520.0, 0.8, 0.6, SynthDsp.SHAPE_SINE, 0.05, 0.0, 0.0, 7.0, 0.04)
	SynthDsp.tone(b, 0.0, 0.62, 1700.0, 1040.0, 0.2, 0.5, SynthDsp.SHAPE_SINE, 0.05, 0.0, 0.0, 7.0, 0.04)
	return SynthDsp.to_stream(b, 0.5)
