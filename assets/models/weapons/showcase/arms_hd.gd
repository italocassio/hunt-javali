extends RefCounted
## HD first-person arms for the showcase guns: khaki field-shirt sleeves with a buttoned cuff and folds,
## a strip of skin at the wrist and gloved hands closed around the pistol grip (right, index at the trigger)
## and under the fore-end (left, thumb along the left flank). 100% procedural, ONE material for both arms
## (hd_arms.gdshader: albedo by vertex colour, fabric / glove / skin told apart by the feature id in UV2.y).
##
## Authored in gun space (s forward from the butt plate, y up from the bore axis, x right; z = -s) from a
## small spec per gun, then shifted by the gun's hip origin, so the meshes are in the same camera space as
## RHAND / LHAND and drop into weapon_view.gd as the RightArm / LeftArm meshes (children of Gun).
##
## Rigid arms, no skeleton: an animation moves a whole arm. reach() swings it about its (off-screen)
## shoulder so a point of the hand lands on a target (bolt knob, magazine); the sleeve follows out of view.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const CarbineHD := preload("res://assets/models/weapons/showcase/carbine_22_hd.gd")
const ShotgunHD := preload("res://assets/models/weapons/showcase/shotgun_12_hd.gd")
const Rifle3006HD := preload("res://assets/models/weapons/showcase/rifle_3006_hd.gd")
const Rifle338HD := preload("res://assets/models/weapons/showcase/rifle_338_hd.gd")
const SHADER: Shader = preload("res://assets/models/weapons/showcase/hd_arms.gdshader")

const RING_POINTS: int = 12
const FINGER_SIDES: int = 6
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.05
## Where the left knuckle row sits around the fore-end (degrees: 0 = straight under it, 90 = far flank,
## -90 = near flank). The wrist comes in from the lower left, so the knuckles land about 90 degrees
## round from it, on the lower far side; the fingers climb from there and break the top edge.
const KNUCKLE_DEG: float = -68.0
## Where the base joints of the four fingers sit. They ride on the outer face of the paddle, a good deal
## nearer than its far edge, because that face is the part of the hand the eye actually has in view.
const FINGER_DEG: float = -14.0

# brushes: [albedo sRGB, roughness, feature]   feature: 0 shirt twill, 1 glove, 2 glove cuff, 3 skin, 4 button
const SHIRT: Array = [Color(0.50, 0.49, 0.36), 0.92, 0]
const SHIRT_CUFF: Array = [Color(0.45, 0.44, 0.32), 0.90, 0]
const GLOVE: Array = [Color(0.34, 0.33, 0.24), 0.72, 1]
## Fingers and thumb: the same glove rubbed pale by use. Reads against the dark stock, where a hand in the
## flat GLOVE tone disappears.
const GLOVE_WORN: Array = [Color(0.60, 0.57, 0.45), 0.62, 1]
const GLOVE_CUFF: Array = [Color(0.105, 0.105, 0.100), 0.88, 2]
const SKIN: Array = [Color(0.56, 0.45, 0.38), 0.55, 3]
const BUTTON: Array = [Color(0.30, 0.25, 0.18), 0.40, 4]

## Per-gun spec in gun space (metres). Hands: `grip` = centre of the right fist on the pistol grip,
## `grip_axis` = down the grip, `grip_half` = half width (x) / half depth (fore-aft) of the grip,
## `trigger` = right index path ending on the trigger blade, `thumb_r` = right thumb path over the wrist.
## `fore` = centre of the fore-end section under the left palm, `fore_half` = half height / half width.
## Elbows and shoulders are in camera space (hip pose, before the depth compression) and sit outside the view. `knob` = bolt knob,
## `mag` = where the left palm goes on a reload.
const SPECS: Dictionary = {
	&"rifle_308": {
		"origin": RifleHD.HIP_ORIGIN,
		"grip": Vector3(0.0, -0.083, -0.284),
		"grip_axis": Vector3(0.0, -0.81, 0.58),
		"grip_half": Vector2(0.0185, 0.023),
		"trigger": [Vector3(0.026, -0.060, -0.300), Vector3(0.017, -0.062, -0.322), Vector3(0.010, -0.065, -0.341),
			Vector3(0.004, -0.071, -0.353), Vector3(0.000, -0.080, -0.356)],
		"thumb_r": [Vector3(0.027, -0.050, -0.258), Vector3(0.024, -0.038, -0.272), Vector3(0.018, -0.026, -0.288),
			Vector3(0.014, -0.017, -0.304), Vector3(0.012, -0.010, -0.316)],
		"fore": Vector3(0.0, -0.0235, -0.640),
		"fore_half": Vector2(0.019, 0.0225),
		# viewmodel pose (weapon_view.gd compresses depth by RifleHD.VIEW_DEPTH): the left forearm rises from the
		# bottom of the screen to the fore-end instead of crossing it; the right one leaves by the lower right corner
		"r_elbow": RifleHD.HIP_ORIGIN + Vector3(0.24, -0.23, -0.03),
		"r_shoulder": RifleHD.HIP_ORIGIN + Vector3(0.20, -0.42, 0.37),
		"l_elbow": RifleHD.HIP_ORIGIN + Vector3(-0.0260, -0.4395, -0.4600),
		"l_shoulder": RifleHD.HIP_ORIGIN + Vector3(-0.0660, -0.7995, -0.2300),
		"knob": Vector3(0.0535, -0.0375, -0.3335),
		"mag": Vector3(0.0, -0.090, -0.470),
	},
	# The other guns: grip / fore measured on each stock section at RHAND / LHAND; the left elbow and shoulder
	# move with the fore-end (same forearm direction as the .308), the right ones stay with the grip.
	&"carbine_22": {
		"origin": CarbineHD.HIP_ORIGIN,
		# straight sporter wrist: the fist sits in its lower half, the thumb stays on the right flank (bolt shroud on top)
		"grip": Vector3(0.0, -0.0785, -0.284),
		"grip_axis": Vector3(0.0, -0.81, 0.58),
		"grip_half": Vector2(0.0163, 0.023),
		"trigger": [Vector3(0.026, -0.0555, -0.300), Vector3(0.017, -0.0545, -0.323), Vector3(0.010, -0.0535, -0.343),
			Vector3(0.004, -0.0560, -0.3565), Vector3(0.000, -0.0610, -0.3605)],
		"thumb_r": [Vector3(0.026, -0.058, -0.256), Vector3(0.026, -0.046, -0.270), Vector3(0.025, -0.035, -0.284),
			Vector3(0.024, -0.027, -0.296), Vector3(0.023, -0.022, -0.305)],
		"fore": Vector3(0.0, -0.0195, -0.500),
		"fore_half": Vector2(0.0148, 0.0172),
		"r_elbow": CarbineHD.HIP_ORIGIN + Vector3(0.24, -0.23, -0.03),
		"r_shoulder": CarbineHD.HIP_ORIGIN + Vector3(0.20, -0.42, 0.37),
		"l_elbow": CarbineHD.HIP_ORIGIN + Vector3(-0.0260, -0.4355, -0.3200),
		"l_shoulder": CarbineHD.HIP_ORIGIN + Vector3(-0.0660, -0.7955, -0.0900),
		"knob": Vector3(0.0418, -0.0298, -0.313),
		"mag": Vector3(0.0, -0.060, -0.448),
	},
	&"shotgun_12": {
		"origin": ShotgunHD.HIP_ORIGIN,
		"grip": Vector3(0.0, -0.083, -0.284),
		"grip_axis": Vector3(0.0, -0.81, 0.58),
		"grip_half": Vector2(0.0185, 0.023),
		# the trigger sits far forward under the receiver: the index rests straight along the right flank
		"trigger": [Vector3(0.026, -0.060, -0.300), Vector3(0.0245, -0.055, -0.318), Vector3(0.0235, -0.050, -0.336),
			Vector3(0.0228, -0.047, -0.354), Vector3(0.0222, -0.046, -0.370)],
		"thumb_r": [Vector3(0.027, -0.052, -0.258), Vector3(0.024, -0.041, -0.272), Vector3(0.018, -0.031, -0.288),
			Vector3(0.014, -0.023, -0.304), Vector3(0.012, -0.017, -0.316)],
		"fore": Vector3(0.0, -0.0275, -0.683),
		"fore_half": Vector2(0.0237, 0.0227),
		"r_elbow": ShotgunHD.HIP_ORIGIN + Vector3(0.24, -0.23, -0.03),
		"r_shoulder": ShotgunHD.HIP_ORIGIN + Vector3(0.20, -0.42, 0.37),
		"l_elbow": ShotgunHD.HIP_ORIGIN + Vector3(-0.0260, -0.4435, -0.5030),
		"l_shoulder": ShotgunHD.HIP_ORIGIN + Vector3(-0.0660, -0.8035, -0.2730),
		# no bolt: `knob` unused; `mag` = under the loading port (shells are pushed in from below)
		"knob": Vector3(0.0, -0.0305, -0.512),
		"mag": Vector3(0.0, -0.062, -0.512),
	},
	&"rifle_3006": {
		"origin": Rifle3006HD.HIP_ORIGIN,
		"grip": Vector3(0.0, -0.083, -0.284),
		"grip_axis": Vector3(0.0, -0.81, 0.58),
		"grip_half": Vector2(0.0185, 0.023),
		"trigger": [Vector3(0.026, -0.060, -0.300), Vector3(0.017, -0.062, -0.325), Vector3(0.010, -0.065, -0.347),
			Vector3(0.004, -0.071, -0.362), Vector3(0.000, -0.080, -0.368)],
		# the receiver starts right behind the trigger: the thumb ends on its right flank
		"thumb_r": [Vector3(0.027, -0.050, -0.258), Vector3(0.025, -0.039, -0.272), Vector3(0.0235, -0.030, -0.286),
			Vector3(0.0225, -0.024, -0.298), Vector3(0.022, -0.020, -0.306)],
		"fore": Vector3(0.0, -0.027, -0.600),
		"fore_half": Vector2(0.0257, 0.025),
		"r_elbow": Rifle3006HD.HIP_ORIGIN + Vector3(0.24, -0.23, -0.03),
		"r_shoulder": Rifle3006HD.HIP_ORIGIN + Vector3(0.20, -0.42, 0.37),
		"l_elbow": Rifle3006HD.HIP_ORIGIN + Vector3(-0.0260, -0.4430, -0.4200),
		"l_shoulder": Rifle3006HD.HIP_ORIGIN + Vector3(-0.0660, -0.8030, -0.1900),
		"knob": Vector3(0.0345, 0.0016, -0.434),   # operating handle (semi-auto: not worked by the hands)
		"mag": Vector3(0.0, -0.088, -0.503),      # lower half of the detachable box
	},
	&"rifle_338": {
		"origin": Rifle338HD.HIP_ORIGIN,
		"grip": Vector3(0.0, -0.086, -0.284),
		"grip_axis": Vector3(0.0, -0.81, 0.58),
		"grip_half": Vector2(0.0195, 0.024),
		# long action: the trigger is 3 cm further forward than on the .308
		"trigger": [Vector3(0.026, -0.062, -0.302), Vector3(0.017, -0.068, -0.331), Vector3(0.010, -0.070, -0.356),
			Vector3(0.004, -0.074, -0.376), Vector3(0.000, -0.081, -0.386)],
		"thumb_r": [Vector3(0.028, -0.054, -0.258), Vector3(0.025, -0.044, -0.272), Vector3(0.019, -0.035, -0.288),
			Vector3(0.015, -0.027, -0.304), Vector3(0.013, -0.020, -0.316)],
		"fore": Vector3(0.0, -0.034, -0.620),
		"fore_half": Vector2(0.0187, 0.028),
		"r_elbow": Rifle338HD.HIP_ORIGIN + Vector3(0.24, -0.23, -0.03),
		"r_shoulder": Rifle338HD.HIP_ORIGIN + Vector3(0.20, -0.42, 0.37),
		"l_elbow": Rifle338HD.HIP_ORIGIN + Vector3(-0.0260, -0.4500, -0.4400),
		"l_shoulder": Rifle338HD.HIP_ORIGIN + Vector3(-0.0660, -0.8100, -0.2100),
		# the .308 bolt scaled 1.1 across and moved back by BOLT_SHIFT
		"knob": Vector3(0.0535 * 1.1, -0.0375 * 1.1, -0.3335 - Rifle338HD.BOLT_SHIFT),
		"mag": Vector3(0.0, -0.094, -0.500),
	},
}

static var _cache: Dictionary = {}
static var _material: ShaderMaterial = null


## { right: ArrayMesh, left: ArrayMesh, triangles: int, right_tris, left_tris, build_ms,
##   right_hand / left_hand / right_shoulder / left_shoulder / knob / mag: Vector3 (camera space, hip pose) }
## `occluders` = gun triangles in gun space (for the baked contact shadow of the hands); optional.
## `gun_bounds` = bounding box of those triangles (gun space); computed from them when empty.
static func get_arms(id: StringName, occluders: PackedVector3Array = PackedVector3Array(), gun_bounds: AABB = AABB()) -> Dictionary:
	if not _cache.has(id):
		_cache[id] = build(SPECS[id], occluders, gun_bounds)
	return _cache[id]


static func get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		var wood: ShaderMaterial = RifleHD.get_materials()[RifleHD.SURF_WOOD]
		_material.set_shader_parameter(&"noise_tex", wood.get_shader_parameter(&"noise_tex"))
	return _material


static func build(spec: Dictionary, occluders: PackedVector3Array = PackedVector3Array(), gun_bounds: AABB = AABB()) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var o: Vector3 = spec["origin"]
	var right: HDMesh = HDMesh.new()
	var left: HDMesh = HDMesh.new()
	right.xf = Transform3D(Basis.IDENTITY, o)
	left.xf = Transform3D(Basis.IDENTITY, o)
	_right_arm(right, spec)
	_left_arm(left, spec)
	var built_r: Dictionary = right.build()
	var built_l: Dictionary = left.build()
	var faces: PackedVector3Array = right.get_faces().duplicate()
	faces.append_array(left.get_faces())
	for p: Vector3 in occluders:
		faces.push_back(p + o)
	var tm: TriangleMesh = TriangleMesh.new()
	tm.create_from_faces(faces)
	if not gun_bounds.has_surface():
		gun_bounds = AABB(occluders[0], Vector3.ZERO) if not occluders.is_empty() else AABB()
		for p: Vector3 in occluders:
			gun_bounds = gun_bounds.expand(p)
	# the gun can only shade the vertices within the AO radius of its bounding box; the rest of the sleeve only shades itself
	var near: AABB = AABB(gun_bounds.position + o, gun_bounds.size).grow(AO_RADIUS) if gun_bounds.has_surface() else AABB()
	HDMesh.bake_ao(built_r, tm, AO_RAYS, AO_RADIUS, 0.6, 0.6, near)
	HDMesh.bake_ao(built_l, tm, AO_RAYS, AO_RADIUS, 0.6, 0.6, near)
	var mats: Dictionary = {0: get_material()}
	var mesh_r: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_r, mesh_r, mats)
	var mesh_l: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_l, mesh_l, mats)
	return {
		"right": mesh_r, "left": mesh_l,
		"triangles": right.triangle_count() + left.triangle_count(),
		"right_tris": right.triangle_count(), "left_tris": left.triangle_count(),
		"right_hand": (spec["grip"] as Vector3) + o, "left_hand": (spec["fore"] as Vector3) + o,
		"right_shoulder": spec["r_shoulder"], "left_shoulder": spec["l_shoulder"],
		"right_elbow": spec["r_elbow"], "left_elbow": spec["l_elbow"],
		"knob": (spec["knob"] as Vector3) + o, "knob_gun": spec["knob"], "mag": (spec["mag"] as Vector3) + o,
		"build_ms": Time.get_ticks_msec() - t0,
	}


# --- poses ------------------------------------------------------------------------------------------

## Rigid swing of an arm about a pivot (elbow or shoulder) so that the hand point `hand` lands on `target` (both in the
## arm's parent space at rest), blended by `weight`. `roll` turns the arm about its own axis (radians).
## The residual length change slides the arm along that axis. Returns the arm node transform.
static func reach(pivot: Vector3, hand: Vector3, target: Vector3, weight: float, roll: float = 0.0) -> Transform3D:
	var goal: Vector3 = hand.lerp(target, clampf(weight, 0.0, 1.0))
	var from: Vector3 = hand - pivot
	var to: Vector3 = goal - pivot
	var b: Basis = Basis(Quaternion(from.normalized(), to.normalized()))
	if roll != 0.0:
		b = Basis(to.normalized(), roll) * b
	var xf: Transform3D = Transform3D(b, pivot - b * pivot)
	xf.origin += to.normalized() * (to.length() - from.length())
	return xf


# --- arms -------------------------------------------------------------------------------------------

## Point on the ellipse wrapped by a hand: frame x = theta 0, y = theta 90, z = along the held part.
static func _wrap(fr: Transform3D, half: Vector2, theta_deg: float, h: float, rho: float) -> Vector3:
	var t: float = deg_to_rad(theta_deg)
	return fr * Vector3(cos(t) * (half.x + rho), sin(t) * (half.y + rho), h)


static func _right_arm(k: HDMesh, spec: Dictionary) -> void:
	var a: Vector3 = (spec["grip_axis"] as Vector3).normalized()
	var e0: Vector3 = Vector3.RIGHT
	# front strap direction: perpendicular to the grip axis, toward the muzzle
	var e1: Vector3 = (Vector3.FORWARD - a * Vector3.FORWARD.dot(a)).normalized()
	var g: Vector3 = spec["grip"]
	var half: Vector2 = spec["grip_half"]
	var fr: Transform3D = Transform3D(Basis(e0, e1, a), g)
	var o: Vector3 = spec["origin"]
	var wrist: Vector3 = g + e0 * 0.046 - e1 * 0.058 + a * 0.006
	var elbow: Vector3 = (spec["r_elbow"] as Vector3) - o
	var shoulder: Vector3 = (spec["r_shoulder"] as Vector3) - o
	var palm: Array = [
		[_wrap(fr, half, 32.0, 0.010, 0.012), 0.050, 0.020],
		[_wrap(fr, half, -5.0, 0.008, 0.015), 0.051, 0.023],
		[_wrap(fr, half, -42.0, 0.002, 0.018), 0.044, 0.022],
		[(_wrap(fr, half, -42.0, 0.002, 0.018) + wrist) * 0.5 + e0 * 0.005, 0.033, 0.019],
	]
	_arm_tube(k, palm, wrist, elbow, shoulder, a, 1.0, GLOVE_WORN, 0.032, Vector2(0.023, 0.018))
	# fingers wrap the front strap and end on the left flank; thick, with clear gaps, as on the reference
	k.surface(0)
	_paint(k, GLOVE_WORN)
	for f: Array in [[-0.009, 0.0118, 200.0], [0.0145, 0.0115, 196.0], [0.0345, 0.0104, 186.0]]:
		var h: float = f[0]
		var r: float = f[1]
		var pts: Array = []
		for key: Vector2 in [Vector2(26.0, r + 0.009), Vector2(72.0, r + 0.001), Vector2(122.0, r), Vector2(166.0, r * 0.96), Vector2(f[2], r * 0.9)]:
			pts.append(_wrap(fr, half, key.x, h + (key.x - 26.0) * 0.00002, key.y))
		_finger(k, pts, r, a, 0.7)
	# inside of the fist (hidden in the grip): fills the hole when the hand lets go to work the bolt
	_filler(k, Basis(e0, e1, a), g + a * 0.012, Vector3(0.016, 0.020, 0.028), o)
	# index along the right side of the guard to the trigger blade, thumb over the wrist of the stock
	_paint(k, GLOVE_WORN)
	_finger(k, spec["trigger"], 0.0112, Vector3.UP, 0.7)
	_finger(k, spec["thumb_r"], 0.0135, Vector3.FORWARD, 0.7)


static func _left_arm(k: HDMesh, spec: Dictionary) -> void:
	var a: Vector3 = Vector3.FORWARD
	var e0: Vector3 = Vector3.DOWN
	var e1: Vector3 = Vector3.RIGHT
	var c: Vector3 = spec["fore"]
	var half: Vector2 = spec["fore_half"]
	var fr: Transform3D = Transform3D(Basis(e0, e1, a), c)
	var o: Vector3 = spec["origin"]
	# The eye looks almost straight down the barrel, so whichever part of the hand is on the near flank hides
	# everything behind it. With the wrist coming up from straight below, the knuckle row lands on that near
	# flank (theta 0 = under, 90 = far, -90 = near): the back of the hand faces the eye, and the fingers climb
	# the near face and over the top, where they are the nearest thing to the camera instead of the furthest.
	var wrist: Vector3 = c + e0 * 0.076 + e1 * 0.004 - a * 0.010
	var elbow: Vector3 = (spec["l_elbow"] as Vector3) - o
	var shoulder: Vector3 = (spec["l_shoulder"] as Vector3) - o
	var knuck: Vector3 = _wrap(fr, half, KNUCKLE_DEG, 0.008, 0.010)
	var palm: Array = [
		[knuck, 0.055, 0.021],
		[knuck.lerp(wrist, 0.28), 0.054, 0.023],
		[knuck.lerp(wrist, 0.58), 0.045, 0.023],
		[knuck.lerp(wrist, 0.84), 0.033, 0.020],
	]
	_arm_tube(k, palm, wrist, elbow, shoulder, a, 1.0, GLOVE_WORN, 0.032, Vector2(0.023, 0.018))
	k.surface(0)
	_paint(k, GLOVE_WORN)
	# [h along the fore-end (index the most forward), radius, angle of the tip, rake of the base joint].
	# Short and thick, base joint the widest, rounded tip; they wrap toward -180, i.e. up the near face and
	# over the top edge, so the whole second half of each one is in open view.
	for f: Array in [[0.0500, 0.0150, -198.0, -7.0], [0.0170, 0.0156, -192.0, -2.0],
			[-0.0160, 0.0150, -186.0, 4.0], [-0.0490, 0.0136, -178.0, 9.0]]:
		var h: float = f[0]
		var r: float = f[1]
		var base: float = KNUCKLE_DEG + float(f[3])
		var span: float = (float(f[2]) - base) / 112.0
		var pts: Array = []
		for key: Vector2 in [Vector2(0.0, r + 0.005), Vector2(28.0, r + 0.001), Vector2(56.0, r * 0.98),
				Vector2(84.0, r * 0.96), Vector2(112.0, r * 0.94)]:
			pts.append(_wrap(fr, half, base + key.x * span, h, key.y))
		_finger(k, pts, r, a, 0.9)
	_filler(k, Basis(e0, e1, a), c + a * 0.002, Vector3(0.016, 0.019, 0.044), o)
	# thumb: wrapped across the underside toward the far flank, where a real support thumb goes on a slim
	# fore-end; it keeps the near face clear for the fingers
	_paint(k, GLOVE_WORN)
	_finger(k, [_wrap(fr, half, -46.0, 0.062, 0.028), _wrap(fr, half, -18.0, 0.050, 0.024), _wrap(fr, half, 14.0, 0.032, 0.0195),
		_wrap(fr, half, 40.0, 0.010, 0.0170), _wrap(fr, half, 56.0, -0.014, 0.0160)], 0.0170, Vector3.UP, 0.9)


## Glove-coloured ellipsoid in the hole of a closed hand (frame basis = the hand's wrap frame).
static func _filler(k: HDMesh, basis: Basis, center: Vector3, radii: Vector3, origin: Vector3) -> void:
	var keep: Transform3D = k.xf
	k.xf = Transform3D(Basis.IDENTITY, origin) * Transform3D(basis, center)
	_paint(k, GLOVE)
	k.sphere(Vector3.ZERO, radii, 8, 5)
	k.xf = keep


static func _paint(k: HDMesh, brush: Array, wear: float = 0.0) -> void:
	k.paint(brush[0], 0.0, brush[1], wear, brush[2])


## Palm + wrist + glove cuff + skin + shirt cuff + sleeve, one smooth tube from the knuckles to the
## shoulder. `palm` = [[point, half width, half thickness], ...] from the knuckles to the wrist.
static func _arm_tube(k: HDMesh, palm: Array, wrist: Vector3, elbow: Vector3, shoulder: Vector3, width_axis: Vector3, side: float, hand_brush: Array = GLOVE, cuff_at: float = 0.032,
		wrist_half: Vector2 = Vector2(0.028, 0.020)) -> void:
	var fdir: Vector3 = (elbow - wrist).normalized()
	# [point, half width, half thickness, brush, folds]
	var keys: Array = []
	for p: Array in palm:
		keys.append([p[0], p[1], p[2], hand_brush, 0.0])
	# `hand_brush` stops at the wrist: the tone break between a pale hand and a dark sleeve is what cuts the
	# hand out of the stock behind it. A segment takes the brush of the key it ENDS on.
	keys.append([wrist, wrist_half.x, wrist_half.y, hand_brush, 0.0])
	keys.append([wrist + fdir * 0.018, 0.029, 0.021, GLOVE, 0.0])
	var cu: float = cuff_at
	keys.append([wrist + fdir * (cu - 0.004), 0.0300, 0.0220, GLOVE, 0.0])
	keys.append([wrist + fdir * cu, 0.031, 0.0235, GLOVE_CUFF, 0.0])
	keys.append([wrist + fdir * (cu + 0.002), 0.027, 0.020, SKIN, 0.0])
	keys.append([wrist + fdir * (cu + 0.008), 0.0275, 0.0205, SKIN, 0.0])
	# buttoned shirt cuff with a rolled rim at both ends
	keys.append([wrist + fdir * (cu + 0.008), 0.0275, 0.0205, SHIRT_CUFF, 0.0])
	keys.append([wrist + fdir * (cu + 0.011), 0.0355, 0.0285, SHIRT_CUFF, 0.0])
	keys.append([wrist + fdir * (cu + 0.020), 0.0340, 0.0270, SHIRT_CUFF, 0.0])
	keys.append([wrist + fdir * (cu + 0.054), 0.0350, 0.0280, SHIRT_CUFF, 0.02])
	keys.append([wrist + fdir * (cu + 0.059), 0.0365, 0.0295, SHIRT_CUFF, 0.0])
	# sleeve: pinched at the cuff seam, two bunched volume folds, widening to the elbow
	keys.append([wrist + fdir * (cu + 0.062), 0.031, 0.025, SHIRT, 0.0])
	keys.append([wrist + fdir * (cu + 0.086), 0.043, 0.033, SHIRT, 0.10])
	keys.append([wrist + fdir * (cu + 0.118), 0.038, 0.030, SHIRT, 0.04])
	keys.append([wrist + fdir * (cu + 0.158), 0.046, 0.035, SHIRT, 0.12])
	var fore_len: float = wrist.distance_to(elbow)
	keys.append([wrist + fdir * maxf(fore_len * 0.70, 0.24), 0.046, 0.036, SHIRT, 0.06])
	keys.append([elbow, 0.050, 0.040, SHIRT, 0.09])
	keys.append([shoulder, 0.056, 0.048, SHIRT, 0.0])
	var n: int = keys.size()
	# tangents (central differences; repeated points borrow their neighbour's direction)
	var tans: Array[Vector3] = []
	for i in n:
		var prev: Vector3 = keys[maxi(i - 1, 0)][0]
		var next: Vector3 = keys[mini(i + 1, n - 1)][0]
		var t: Vector3 = next - prev
		if t.length_squared() < 1e-10:
			t = fdir
		tans.append(t.normalized())
	# rings with a parallel-transported frame (no twist flips through the bent wrist)
	var u: Vector3 = (width_axis - tans[0] * width_axis.dot(tans[0])).normalized()
	var rings: Array = []
	var centers: Array[Vector3] = []
	var along: PackedFloat32Array = PackedFloat32Array()
	var perim: PackedFloat32Array = PackedFloat32Array()
	var dist: float = 0.0
	for i in n:
		if i > 0:
			u = Quaternion(tans[i - 1], tans[i]) * u
			u = (u - tans[i] * u.dot(tans[i])).normalized()
			dist += (keys[i][0] as Vector3).distance_to(keys[i - 1][0])
		var v: Vector3 = tans[i].cross(u).normalized() * side
		var p: Vector3 = keys[i][0]
		var w: float = keys[i][1]
		var d: float = keys[i][2]
		var fold: float = keys[i][4]
		var exp_n: float = 2.25 if i < palm.size() else 2.0
		var ring: PackedVector3Array = PackedVector3Array()
		for j in RING_POINTS:
			var ang: float = TAU * float(j) / float(RING_POINTS)
			var cs: float = cos(ang)
			var sn: float = sin(ang)
			var x: float = w * signf(cs) * pow(absf(cs), 2.0 / exp_n)
			var y: float = d * signf(sn) * pow(absf(sn), 2.0 / exp_n)
			# cloth folds: a few soft lobes that drift from ring to ring
			var f: float = 1.0 + fold * (0.55 * sin(ang * 3.0 + float(i) * 1.9) + 0.45 * sin(ang * 2.0 - float(i) * 1.3 + 0.7))
			ring.push_back(p + (u * x + v * y) * f)
		rings.append(ring)
		centers.append(p)
		along.push_back(dist)
		perim.push_back(PI * (w + d))
	k.surface(0)
	k.begin_part()
	# knuckle end: domed cap (two rings on a quarter ellipse, then a fan) instead of a flat wedge
	_paint(k, hand_brush)
	var dome: float = keys[0][2] * 1.2
	var caps: Array = []
	var cap_c: Array[Vector3] = []
	var cap_a: PackedFloat32Array = PackedFloat32Array()
	var cap_p: PackedFloat32Array = PackedFloat32Array()
	for step: Vector2 in [Vector2(0.60, 0.80), Vector2(0.88, 0.47)]:
		var ring: PackedVector3Array = PackedVector3Array()
		var off: Vector3 = tans[0] * (dome * step.y)
		for q: Vector3 in rings[0]:
			ring.push_back(centers[0] + (q - centers[0]) * step.x - off)
		caps.append(ring)
		cap_c.append(centers[0] - off)
		cap_a.push_back(dome * (1.0 - step.y))
		cap_p.push_back(perim[0] * step.x)
	caps.append(rings[0])
	cap_c.append(centers[0])
	cap_a.push_back(dome)
	cap_p.push_back(perim[0])
	_skin(k, caps, cap_c, cap_a, cap_p)
	var tip: Vector3 = centers[0] - tans[0] * dome
	for q in RING_POINTS:
		k.tri(tip, caps[0][q], caps[0][(q + 1) % RING_POINTS], -tans[0])
	for i in n - 1:
		_paint(k, keys[i + 1][3])
		_skin(k, [rings[i], rings[i + 1]], [centers[i], centers[i + 1]], along.slice(i, i + 2), perim.slice(i, i + 2))
	# cuff button on the outer side of the shirt cuff
	_paint(k, BUTTON)
	var bi: int = 0
	for i in n:
		if keys[i][3] == SHIRT_CUFF:
			bi = i
	var bc: Vector3 = (centers[bi] + centers[bi - 1]) * 0.5
	var bring: PackedVector3Array = rings[bi]
	var bdir: Vector3 = (bring[RING_POINTS >> 2] - centers[bi]).normalized()
	k.sphere(bc + bdir * (0.027 + 0.002), Vector3(0.004, 0.004, 0.004), 6, 4)


## Quads between consecutive rings, UV = (around, along) in metres for the fabric weave.
static func _skin(k: HDMesh, rings: Array, centers: Array, along: PackedFloat32Array, perim: PackedFloat32Array) -> void:
	for i in rings.size() - 1:
		var ra: PackedVector3Array = rings[i]
		var rb: PackedVector3Array = rings[i + 1]
		var cmid: Vector3 = ((centers[i] as Vector3) + (centers[i + 1] as Vector3)) * 0.5
		for j in RING_POINTS:
			var jn: int = (j + 1) % RING_POINTS
			var fa: float = float(j) / float(RING_POINTS)
			var fb: float = float(j + 1) / float(RING_POINTS)
			var mid: Vector3 = (ra[j] + ra[jn] + rb[j] + rb[jn]) * 0.25
			var out: Vector3 = mid - cmid
			if out.length_squared() < 1e-12:
				out = (ra[j] - (centers[i] as Vector3))
			k.quad(ra[j], ra[jn], rb[jn], rb[j], out,
				Vector2(fa * perim[i], along[i]), Vector2(fb * perim[i], along[i]),
				Vector2(fb * perim[i + 1], along[i + 1]), Vector2(fa * perim[i + 1], along[i + 1]))


## Gaussian bump of width `w` centred on `c`, for the joint profile of a finger.
static func _bump(t: float, c: float, w: float) -> float:
	var x: float = (t - c) / w
	return exp(-x * x)


## Gloved finger: tube through `pts` (smoothed), tapering, rounded tip. `knuckles` (0..1) swells the three
## joints and pinches the shafts between them, so a curled finger reads as a finger instead of a smooth rod.
static func _finger(k: HDMesh, pts: Array, radius: float, right_ref: Vector3, knuckles: float = 0.0) -> void:
	var path: Array = HDMesh.smooth_path(pts, 2)
	var n: int = path.size()
	var last: Vector3 = path[n - 1]
	var dir: Vector3 = (last - (path[n - 2] as Vector3)).normalized()
	path.append(last + dir * radius * 0.55)
	var scales: PackedFloat32Array = PackedFloat32Array()
	for i in n:
		var t: float = float(i) / float(n - 1)
		var s: float = lerpf(1.0, 0.86, t)
		if knuckles > 0.0:
			# base joint, middle joint, last joint; the two shafts between them are slightly waisted
			s *= 1.0 + knuckles * (0.24 * _bump(t, 0.05, 0.14) + 0.19 * _bump(t, 0.47, 0.13)
				+ 0.12 * _bump(t, 0.79, 0.10) - 0.11 * _bump(t, 0.26, 0.11) - 0.08 * _bump(t, 0.64, 0.10))
		scales.push_back(s)
	scales.push_back(0.5)
	k.crease_deg = 70.0
	k.sweep(path, HDMesh.circle_section(radius, FINGER_SIDES), right_ref, scales)
	k.crease_deg = 50.0


## Where the centre of the right fist sits relative to the bolt knob while working the bolt.
const KNOB_GRAB: Vector3 = Vector3(-0.004, -0.0185, 0.0255)


## Arm transforms of a bolt gun for the current animation state: [RightArm, LeftArm] (parent = Gun).
## `cycle_t` / `reload_t` are normalised 0..1 (negative = not playing). `knob_now` = bolt knob in Gun
## space right now (Mover transform * arms["knob_gun"]). Bolt cycle: the right fist leaves the grip, rides
## the knob up, back, forward and down, and returns. Reload: the right fist holds the open bolt while the
## left hand leaves the fore-end, drops to the magazine, pulls it down, brings it back and returns.
static func bolt_pose(arms: Dictionary, cycle_t: float, reload_t: float, knob_now: Vector3) -> Array[Transform3D]:
	var w_r: float = 0.0
	if cycle_t >= 0.0:
		w_r = smoothstep(0.0, 0.14, cycle_t) * (1.0 - smoothstep(0.86, 1.0, cycle_t))
	if reload_t >= 0.0:
		w_r = maxf(w_r, smoothstep(0.0, 0.12, reload_t) * (1.0 - smoothstep(0.88, 1.0, reload_t)))
	# pivot at the elbows (just outside the view): the forearm tilts toward the target instead of
	# translating with the hand, the way a real forearm does
	var r: Transform3D = reach(arms["right_elbow"], arms["right_hand"], knob_now + KNOB_GRAB, w_r, 0.6 * w_r)
	return [r, mag_reach(arms, reload_t)]


## LeftArm transform of a magazine swap (`reload_t` 0..1, negative = at rest on the fore-end): the hand leaves
## the fore-end, drops to the magazine, pulls it down, brings it back and returns.
static func mag_reach(arms: Dictionary, reload_t: float) -> Transform3D:
	if reload_t < 0.0:
		return Transform3D.IDENTITY
	var w_l: float = smoothstep(0.08, 0.28, reload_t) * (1.0 - smoothstep(0.72, 0.92, reload_t))
	var dip: float = sin(clampf((reload_t - 0.32) / 0.36, 0.0, 1.0) * PI)
	var target: Vector3 = (arms["mag"] as Vector3) + Vector3(-0.01, -0.08 * dip, 0.01 * dip)
	return reach(arms["left_elbow"], arms["left_hand"], target, w_l)


## Pump gun: [RightArm, LeftArm]. The right fist stays on the grip. Cycle: the left hand rides the fore-end
## (`pump_z` = the Mover's travel toward the shooter). Reload: the left hand leaves the fore-end for the
## loading port and pushes `feeds` shells in from below, one dip per shell.
static func pump_pose(arms: Dictionary, pump_z: float, reload_t: float, feeds: int = 4) -> Array[Transform3D]:
	var l: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, pump_z))
	if reload_t >= 0.0:
		var w_l: float = smoothstep(0.04, 0.18, reload_t) * (1.0 - smoothstep(0.84, 0.98, reload_t))
		var f: float = clampf((reload_t - 0.18) / 0.64, 0.0, 1.0) * float(feeds)
		var dip: float = 0.5 - 0.5 * cos(fposmod(f, 1.0) * TAU) if f < float(feeds) else 0.0
		var target: Vector3 = (arms["mag"] as Vector3) + Vector3(-0.004, -0.075 * dip, 0.012 * dip)
		l = reach(arms["left_elbow"], arms["left_hand"], target, w_l)
	return [Transform3D.IDENTITY, l]
