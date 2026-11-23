extends Node3D
## HD procedural hunting knife: drop-point blade about 0.20 m, wooden handle about 0.12 m, steel bolster and guard.
## Knife space: s = distance forward from the pommel (z = -s), so the TIP points to -Z and the HANDLE sits at +Z;
## y up (the cutting edge is the lower one), x to the right. One mesh, two surfaces (wood, hard surface) that use
## the materials already shared by the guns. weapon-art tool contract: set_hip_pose(on), set_cast_shadows(on).
## knife_view.gd uses only the static get_model().

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const CarbineHD := preload("res://assets/models/weapons/showcase/carbine_22_hd.gd")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1

const HANDLE_LEN: float = 0.120
const TIP_S: float = 0.322
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.012
const SEGS: int = 10
const BLADE_HALF_THICK: float = 0.0016
const BLADE_BEVEL: float = 0.0013

## Hip pose of the standalone model (only used outside the weapon art tool): tilted like the in-game rest pose.
const HIP_EULER: Vector3 = Vector3(0.55, 0.25, 0.0)

static var _cache: Dictionary = {}

var _body: MeshInstance3D


func _init() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)


func _ready() -> void:
	if _body.mesh == null:
		_body.mesh = get_model()["body"]


## false = knife space (pommel at the origin, tip to -Z): the studio renders.
func set_hip_pose(on: bool) -> void:
	rotation = HIP_EULER if on else Vector3.ZERO


func set_cast_shadows(on: bool) -> void:
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## { body: ArrayMesh (2 surfaces), triangles: int, tip: Vector3, grip: Vector3 (handle centre) }
static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = _build_model()
	return _cache


static func get_materials() -> Dictionary:
	return {SURF_WOOD: CarbineHD.get_materials()[SURF_WOOD], SURF_HARD: RifleHD.get_materials()[SURF_HARD]}


static func _v(s: float, y: float, x: float = 0.0) -> Vector3:
	return Vector3(x, y, -s)


static func _build_model() -> Dictionary:
	var k: HDMesh = HDMesh.new()
	k.crease_deg = 55.0
	_handle(k)
	_metal(k)
	_blade(k)
	var built: Dictionary = k.build()
	var occluders: TriangleMesh = TriangleMesh.new()
	occluders.create_from_faces(k.get_faces())
	HDMesh.bake_ao(built, occluders, AO_RAYS, AO_RADIUS, 1.0, 0.25)
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, get_materials())
	return {
		"body": mesh, "triangles": k.triangle_count(),
		"tip": _v(TIP_S, 0.003), "grip": _v(HANDLE_LEN * 0.5, 0.0),
	}


## Oval wooden handle: swells at the palm, narrows toward the guard. Slightly flattened sideways.
static func _handle(k: HDMesh) -> void:
	k.surface(SURF_WOOD)
	k.paint(Color(0.30, 0.19, 0.11), 0.0, 0.55, 0.0, 0)
	var keep: Transform3D = k.xf
	k.xf = Transform3D(Basis.from_scale(Vector3(0.86, 1.0, 1.0)), Vector3.ZERO)
	var profile: Array = [
		Vector3(0.008, 0.0, 0.0), Vector3(0.008, 0.0100, 0.0), Vector3(0.016, 0.0124, 0.0), Vector3(0.036, 0.0140, 0.0),
		Vector3(0.060, 0.0132, 0.0), Vector3(0.084, 0.0142, 0.0), Vector3(0.104, 0.0134, 0.0), Vector3(0.112, 0.0120, 0.0),
		Vector3(0.112, 0.0, 0.0)]
	k.lathe(profile, SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	k.xf = keep


## Pommel cap, front bolster and cross guard (dark steel), plus two brass pins through the handle.
static func _metal(k: HDMesh) -> void:
	k.surface(SURF_HARD)
	k.paint(Color(0.48, 0.48, 0.50), 1.0, 0.30, 0.15, 0)
	var keep: Transform3D = k.xf
	k.xf = Transform3D(Basis.from_scale(Vector3(0.86, 1.0, 1.0)), Vector3.ZERO)
	# pommel cap
	k.lathe([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0090, 0.0), Vector3(0.003, 0.0110, 0.0), Vector3(0.008, 0.0112, 0.0),
		Vector3(0.008, 0.0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	# bolster between the handle and the guard
	k.lathe([Vector3(0.112, 0.0, 0.0), Vector3(0.112, 0.0122, 0.0), Vector3(0.116, 0.0128, 0.0), Vector3(0.120, 0.0118, 0.0),
		Vector3(0.120, 0.0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	k.xf = keep
	# cross guard: a small flat box, wider than tall
	k.cbox(_v(0.1225, 0.0), Vector3(0.017, 0.040, 0.005), 0.0014)
	# pins
	k.paint(Color(0.70, 0.52, 0.22), 1.0, 0.35, 0.0, 0)
	for s: float in [0.040, 0.086]:
		k.sphere(_v(s, 0.0, 0.0118), Vector3(0.0016, 0.0016, 0.0016), 6, 4)


## Drop-point blade as a side profile extruded across its thickness; both faces taper to the edge (bevel).
static func _blade(k: HDMesh) -> void:
	k.surface(SURF_HARD)
	# satin steel painted as a lit, non-metal grey: a flat metallic blade only mirrors the dark sky of the portrait
	# studio and of the game's low sun, and would read as a black plank
	k.paint(Color(0.350, 0.365, 0.400), 0.0, 0.30, 0.0, 0)
	k.bevel_wear = 1.0   # the ground bevels and the spine corner wear to bright steel
	# (s, y): spine on top, cutting edge below; the tip sits a little above the axis
	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(0.120, 0.0172), Vector2(0.255, 0.0172), Vector2(0.282, 0.0152), Vector2(0.304, 0.0100), Vector2(TIP_S, 0.0030),
		Vector2(0.316, -0.0030), Vector2(0.298, -0.0105), Vector2(0.268, -0.0165), Vector2(0.226, -0.0202),
		Vector2(0.180, -0.0214), Vector2(0.140, -0.0208), Vector2(0.120, -0.0190)])
	# frame: x -> forward (-Z), y -> up, z -> right (x): a proper right-handed basis
	var frame: Transform3D = Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3.RIGHT), Vector3.ZERO)
	k.extrude(poly, frame, -BLADE_HALF_THICK, BLADE_HALF_THICK, BLADE_BEVEL)
	k.bevel_wear = 0.0
	# fuller: a darker groove along the upper half of the flat
	k.paint(Color(0.10, 0.105, 0.12), 0.0, 0.45, 0.0, 0)
	var fuller: PackedVector2Array = PackedVector2Array([Vector2(0.150, 0.0090), Vector2(0.262, 0.0090), Vector2(0.272, 0.0070),
		Vector2(0.262, 0.0050), Vector2(0.150, 0.0050)])
	k.extrude(fuller, frame, -BLADE_HALF_THICK - 0.00006, BLADE_HALF_THICK + 0.00006, 0.0)
