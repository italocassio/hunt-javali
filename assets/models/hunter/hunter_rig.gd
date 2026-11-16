extends RefCounted
## Shared skeleton-free rig of the third-person hunter: joint positions, segment lengths and the pose math
## used both by the mesh builders (hunter_body.gd, hunter_held.gd) and by hunter_visual.gd.
##
## Spaces (metres, forward -Z, right +X):
##   root  = ground between the feet (gameplay owns its position and yaw)
##   hips  = hip joint centre, HIP_Y above the ground when standing; carries the stance yaw (bladed when aiming)
##   torso = same origin as hips; pitches/rolls for lean, breathing, recoil
##   gun   = held item space: origin on the butt plate at the bore axis, barrel along -Z (s = -z)

const HIP_Y: float = 0.92
const HIP_X: float = 0.092
const LEG_UPPER: float = 0.46          # hip joint -> knee
const LEG_LOWER: float = 0.46          # knee -> sole
const NECK_Y: float = 0.60             # head pivot in torso space
const SHOULDER: Vector3 = Vector3(0.19, 0.49, 0.0)   # right shoulder joint in torso space (x mirrored)
const UPPER_ARM: float = 0.29          # shoulder -> elbow
const FOREARM: float = 0.27            # elbow -> wrist
const ANCHOR_UP: float = 0.53          # NameAnchor above the head pivot
const EYE: Vector3 = Vector3(0.0, 0.135, -0.085)       # eyes (between them) in head space

## Shouldered aim: the butt plate sits in the pocket inside the right shoulder; the stance turns right (left
## shoulder forward) and the torso leans into the gun.
const POCKET: Vector3 = Vector3(0.065, 0.515, -0.105)
const BLADE: float = -0.55
const AIM_LEAN: float = -0.10


static func shoulder(side: int) -> Vector3:   # 0 = left, 1 = right
	return Vector3(SHOULDER.x * (1.0 if side == 1 else -1.0), SHOULDER.y, SHOULDER.z)


## Gun transform (torso space) for a shouldered aim. `torso_basis` = torso rotation relative to the hips,
## `stance_yaw` = hips yaw relative to the root, `pitch` = look pitch (root space, + up). `anchor` = the point
## of the item that goes to `target` (torso space): butt contact -> POCKET, binocular eyepieces -> the eyes.
static func aim_xf(torso_basis: Basis, stance_yaw: float, pitch: float, anchor: Vector3, target: Vector3) -> Transform3D:
	var b: Basis = torso_basis.inverse() * Basis(Vector3.UP, -stance_yaw) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(b, target - b * anchor)


## Two-bone IK: elbow position for a shoulder `s` and wrist `w`, bending toward `pole`.
static func elbow(s: Vector3, w: Vector3, pole: Vector3, upper: float = UPPER_ARM, fore: float = FOREARM) -> Vector3:
	var d: Vector3 = w - s
	var dist: float = clampf(d.length(), 0.05, upper + fore - 0.002)
	var ax: Vector3 = d.normalized()
	var a: float = (upper * upper + dist * dist - fore * fore) / (2.0 * dist)
	var h: float = sqrt(maxf(upper * upper - a * a, 0.0))
	var perp: Vector3 = pole - ax * pole.dot(ax)
	if perp.length_squared() < 1e-8:
		perp = Vector3.DOWN - ax * ax.y
	return s + ax * a + perp.normalized() * h
