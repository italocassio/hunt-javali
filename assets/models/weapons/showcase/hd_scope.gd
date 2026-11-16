extends RefCounted
## Parametric HD riflescope for the showcase rifles (same look as the .308 scope, lighter: fewer segments, no
## cap screws on the flanges). Gun space: s = distance forward from the butt plate (z = -s), y up from the bore
## axis, x to the shooter's right. Uses surface 1 (hard) and 2 (lens) of the shared showcase materials.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const SURF_HARD: int = 1
const SURF_LENS: int = 2
const EYE_RATIO: float = 1.36     # eyepiece radius / tube radius


static func _fin(k: HDMesh, finish: Array, wear: float = 0.0, feature: int = 0) -> void:
	k.surface(SURF_HARD)
	k.paint(finish[0], finish[1], finish[2], wear, feature)


static func _v(s: float, y: float, x: float) -> Vector3:
	return Vector3(x, y, -s)


## s0 = rear of the eye cup, y = scope axis height, rt = tube radius, rb = objective bell radius,
## mounts = ring stations relative to s0, rail_top = y of the base under the rings, ts = turret station relative to s0.
static func build(k: HDMesh, s0: float, y: float, length: float, rt: float, rb: float, mounts: Array, rail_top: float, ts: float, segs: int = 18) -> void:
	var o: Vector3 = _v(0.0, y, 0.0)
	var e: float = rt * EYE_RATIO
	var end: float = s0 + length
	var bs: float = rb / 0.0295            # bell scale against the .308 scope
	k.bevel_wear = 0.0
	# rubber eye cup
	_fin(k, RifleHD.RUBBER)
	k.lathe([
		Vector3(s0 + 0.0070, e * 0.86, 0), Vector3(s0 + 0.0007, e * 0.89, 0), Vector3(s0, e * 0.93, 0), Vector3(s0, e * 1.01, 0),
		Vector3(s0 + 0.0012, e * 1.05, 0), Vector3(s0 + 0.0127, e * 1.05, 0), Vector3(s0 + 0.0133, e, 0)], segs, o, FWD)
	# main body: eyepiece, zoom section, tube with turret housing, objective bell
	k.bevel_wear = 0.55
	_fin(k, RifleHD.SCOPE_BLACK)
	var th: float = 0.0225
	var housing_r: float = rt * 1.27
	k.lathe([
		Vector3(s0 + 0.0133, e, 0), Vector3(s0 + 0.0515, e, 0), Vector3(s0 + 0.0540, e * 0.96, 0), Vector3(s0 + 0.0645, e * 0.89, 0),
		Vector3(s0 + 0.0835, e * 0.89, 0), Vector3(s0 + 0.0920, rt * 1.02, 0), Vector3(s0 + 0.0945, rt, 0),
		Vector3(s0 + ts - th, rt, 0), Vector3(s0 + ts - th + 0.0012, rt * 1.12, 0), Vector3(s0 + ts - th + 0.0035, housing_r * 0.96, 0),
		Vector3(s0 + ts - th + 0.0070, housing_r, 0), Vector3(s0 + ts + th - 0.0070, housing_r, 0), Vector3(s0 + ts + th - 0.0035, housing_r * 0.96, 0),
		Vector3(s0 + ts + th - 0.0012, rt * 1.12, 0), Vector3(s0 + ts + th, rt, 0),
		Vector3(end - 0.0908 * bs, rt, 0), Vector3(end - 0.0848 * bs, rt * 1.07, 0), Vector3(end - 0.0508 * bs, rb * 0.95, 0),
		Vector3(end - 0.0458 * bs, rb, 0), Vector3(end - 0.0028, rb, 0), Vector3(end, rb * 0.976, 0), Vector3(end, rb * 0.915, 0),
		Vector3(end - 0.0118, rb * 0.905, 0)], segs, o, FWD, Vector3.UP, Callable(), 0.0, false)
	# serrated zoom ring
	k.crease_deg = 35.0
	_fin(k, RifleHD.SCOPE_GLOSS)
	k.lathe([Vector3(s0 + 0.0647, e * 0.887, 0), Vector3(s0 + 0.0653, e * 0.96, 0.0009), Vector3(s0 + 0.0827, e * 0.96, 0.0009), Vector3(s0 + 0.0833, e * 0.887, 0)], segs + 6, o, FWD)
	k.crease_deg = 50.0
	# turrets: elevation on top, windage on the right, parallax on the left
	var tc: Vector3 = _v(s0 + ts, y, 0.0)
	_turret(k, tc, Vector3.UP, housing_r, rt * 0.84, rt * 1.10)
	_turret(k, tc, Vector3.RIGHT, housing_r, rt * 0.84, rt * 1.10)
	_turret(k, tc, Vector3.LEFT, housing_r, rt * 0.98, rt * 0.70)
	# ring mounts: ring, base block down to the rail, cross bolt
	for m: float in mounts:
		var sc: float = s0 + m
		k.bevel_wear = 0.75
		_fin(k, RifleHD.BLUED_SATIN)
		k.lathe([
			Vector3(sc - 0.008, rt, 0), Vector3(sc - 0.008, rt + 0.0037, 0), Vector3(sc - 0.0069, rt + 0.0047, 0),
			Vector3(sc + 0.0069, rt + 0.0047, 0), Vector3(sc + 0.008, rt + 0.0037, 0), Vector3(sc + 0.008, rt, 0)], 14, o, FWD)
		var hb: float = (y - rt) - rail_top + 0.004
		if hb > 0.003:
			k.cbox(_v(sc, rail_top + hb * 0.5 - 0.002, 0.0), Vector3(0.0245, hb, 0.0150), 0.0016)
		for sx: float in [-1.0, 1.0]:
			k.cbox(_v(sc, y + 0.0004, sx * (rt + 0.0072)), Vector3(0.0100, 0.0070, 0.0140), 0.0012)
		RifleHD._screw(k, _v(sc, y - rt * 0.1, rt + 0.0120), Vector3.RIGHT, 0.0024, 0.0014)
	# lenses
	k.surface(SURF_LENS)
	k.paint(Color.WHITE, 0.0, 0.05)
	var ocular: Array = []
	var objective: Array = []
	for j in 4:
		var f: float = float(j) / 3.0
		ocular.append(Vector3(s0 + 0.0067 - 0.0018 * (1.0 - f * f), e * 0.868 * f, 0))
		objective.append(Vector3(-(end - 0.0118 + 0.0036 * (1.0 - f * f)), rb * 0.905 * f, 0))
	k.lathe(ocular, segs, o, FWD)
	k.lathe(objective, segs, o, -FWD)


## Dial turret growing from `origin` (on the scope axis) along `axis`, starting at the housing radius `from_r`.
static func _turret(k: HDMesh, origin: Vector3, axis: Vector3, from_r: float, radius: float, height: float) -> void:
	var up_ref: Vector3 = Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.5 else Vector3.UP
	k.bevel_wear = 0.6
	k.crease_deg = 35.0
	var base: float = from_r - 0.001
	_fin(k, RifleHD.SCOPE_BLACK)
	k.lathe([Vector3(base, radius * 0.82, 0), Vector3(base + 0.0045, radius * 0.82, 0)], 12, origin, axis, up_ref)
	_fin(k, RifleHD.SCOPE_GLOSS)
	var top: float = base + 0.0045 + height * 0.55
	k.lathe([
		Vector3(base + 0.0045, radius * 0.82, 0), Vector3(base + 0.0050, radius, 0.0008), Vector3(top - 0.0012, radius, 0.0008),
		Vector3(top, radius * 0.88, 0), Vector3(top, radius * 0.55, 0), Vector3(top + 0.0005, 0.0, 0)], 20, origin, axis, up_ref)
	k.crease_deg = 50.0
