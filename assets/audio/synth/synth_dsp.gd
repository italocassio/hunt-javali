class_name SynthDsp
extends RefCounted
## Tiny additive synth toolkit. Everything renders into a PackedFloat32Array at `RATE`.
## Cheap by design: one-pole filters, exponential envelopes, no allocations in inner loops.

const RATE: int = 22050
const SHAPE_SINE: int = 0
const SHAPE_SAW: int = 1
const SHAPE_SQUARE: int = 2
const SHAPE_TRI: int = 3

static var _seed: int = 1234567


static func rnd() -> float:
	_seed = (_seed * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(_seed) / 2147483648.0 - 1.0


static func buf(seconds: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(int(seconds * float(RATE)))
	return b


## Filtered noise. lp: one-pole low-pass coefficient (1 = white, 0.05 = rumble). hp: high-pass
## coefficient (0 = off). tau: exponential decay time constant (s). am_hz/am_d: amplitude modulation.
static func noise(b: PackedFloat32Array, t0: float, dur: float, amp: float, tau: float, lp: float = 1.0, hp: float = 0.0, att: float = 0.002, am_hz: float = 0.0, am_d: float = 0.0) -> void:
	var i0: int = int(t0 * RATE)
	var n: int = mini(int(dur * RATE), b.size() - i0)
	var dec: float = exp(-1.0 / (maxf(tau, 0.0005) * RATE))
	var env: float = amp
	var y: float = 0.0
	var z: float = 0.0
	var att_n: float = maxf(att * RATE, 1.0)
	var rel_n: int = int(0.004 * RATE)
	var am_w: float = TAU * am_hz / RATE
	for i in n:
		y += lp * (rnd() - y)
		var v: float = y
		if hp > 0.0:
			z += hp * (y - z)
			v = y - z
		var g: float = env
		if i < att_n:
			g *= float(i) / att_n
		if i > n - rel_n:
			g *= float(n - i) / float(rel_n)
		if am_d > 0.0:
			g *= 1.0 - am_d + am_d * (0.5 + 0.5 * sin(am_w * i))
		b[i0 + i] += v * g
		env *= dec


## Oscillator with exponential frequency sweep f0 -> f1 over `dur`.
static func tone(b: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, amp: float, tau: float, shape: int = 0, att: float = 0.003, am_hz: float = 0.0, am_d: float = 0.0, vib_hz: float = 0.0, vib_d: float = 0.0) -> void:
	var i0: int = int(t0 * RATE)
	var n: int = mini(int(dur * RATE), b.size() - i0)
	if n <= 0:
		return
	var dec: float = exp(-1.0 / (maxf(tau, 0.0005) * RATE))
	var env: float = amp
	var ph: float = 0.0
	var ratio: float = f1 / f0
	var att_n: float = maxf(att * RATE, 1.0)
	var rel_n: int = int(0.006 * RATE)
	var am_w: float = TAU * am_hz / RATE
	var vib_w: float = TAU * vib_hz / RATE
	var inv_n: float = 1.0 / float(n)
	for i in n:
		var f: float = f0 * pow(ratio, float(i) * inv_n)
		if vib_d > 0.0:
			f *= 1.0 + vib_d * sin(vib_w * i)
		ph += f / RATE
		var p: float = ph - floorf(ph)
		var v: float
		match shape:
			1: v = 2.0 * p - 1.0
			2: v = 1.0 if p < 0.5 else -1.0
			3: v = 4.0 * absf(p - 0.5) - 1.0
			_: v = sin(p * TAU)
		var g: float = env
		if i < att_n:
			g *= float(i) / att_n
		if i > n - rel_n:
			g *= float(n - i) / float(rel_n)
		if am_d > 0.0:
			g *= 1.0 - am_d + am_d * (0.5 + 0.5 * sin(am_w * i))
		b[i0 + i] += v * g
		env *= dec


## Soft clip (amount > 1 saturates).
static func drive(b: PackedFloat32Array, amount: float) -> void:
	for i in b.size():
		var x: float = b[i] * amount
		b[i] = x / (1.0 + absf(x))


## Crossfades the tail into the head so the buffer loops seamlessly; returns a shorter buffer.
static func make_loop(b: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var f: int = int(fade_s * RATE)
	var n: int = b.size() - f
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = b[i]
	for i in f:
		var t: float = float(i) / float(f)
		out[i] = b[i] * t + b[n + i] * (1.0 - t)
	return out


## Normalizes to `peak` (0..1) and packs 16-bit mono PCM.
static func to_stream(b: PackedFloat32Array, peak: float = 0.8, loop: bool = false, rate: int = RATE) -> AudioStreamWAV:
	var m: float = 0.0001
	for i in b.size():
		m = maxf(m, absf(b[i]))
	var k: float = peak / m
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i] * k, -1.0, 1.0) * 32767.0))
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = b.size()
	return s


static func note(semitones_from_a4: float) -> float:
	return 440.0 * pow(2.0, semitones_from_a4 / 12.0)
