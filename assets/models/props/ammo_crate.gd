extends Node3D
## Horde level 2 ammo crate (docs/plano_horda_nivel2.md section 7): a small wooden crate, ~0.6 x 0.35 x 0.4 m, olive
## green bands and brass / red cartridges standing out of the open top, readable from far away.
## Origin on the ground at the centre. No physics, no light, one MeshInstance3D, one shared material, no shadow.
## The mesh is built once and shared by every crate.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")

const SIZE_X: float = 0.6
const SIZE_Z: float = 0.4
const BODY_H: float = 0.22
const BAND_W: float = 0.09
const BAND_PAD: float = 0.012
const SHELL_ROWS: int = 3
const SHELL_COLS: int = 4
const SHELL_R: float = 0.036
const SHELL_L: float = 0.13
const SHELL_SEGS: int = 4
const OLIVE: Color = Color(0.30, 0.36, 0.16)
const BRASS: Color = Color(0.86, 0.64, 0.20)
const SHELL_RED: Color = Color(0.72, 0.16, 0.12)
const INNER: Color = Color(0.20, 0.14, 0.09)

static var _cache: Dictionary = {}


func _ready() -> void:
	if get_child_count() > 0:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = get_model()["mesh"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	# wooden body, with a slightly darker tray inside the top (the cartridges stand on it)
	m.paint(PM.WOOD_LIGHT, 0.0, 0.9, PM.GRAIN_X, PM.F_WOOD)
	m.cbox(Vector3(0.0, BODY_H * 0.5, 0.0), Vector3(SIZE_X, BODY_H, SIZE_Z), 0.015)
	m.paint(INNER, 0.0, 1.0, 0.0, PM.F_PAINT)
	m.cbox(Vector3(0.0, BODY_H + 0.002, 0.0), Vector3(SIZE_X - 0.07, 0.006, SIZE_Z - 0.07), 0.0)
	# two olive bands wrapping the crate
	m.paint(OLIVE, 0.0, 0.8, 0.0, PM.F_PAINT)
	for sx: float in [-1.0, 1.0]:
		m.cbox(Vector3(sx * (SIZE_X * 0.5 - 0.1), BODY_H * 0.5, 0.0), Vector3(BAND_W, BODY_H + BAND_PAD, SIZE_Z + BAND_PAD), 0.0)
	# cartridges: a grid of upright shells, brass with every third one red
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	var inner_x: float = SIZE_X - 0.30
	for r: int in SHELL_ROWS:
		for c: int in SHELL_COLS:
			var x: float = (float(c) / float(SHELL_COLS - 1) - 0.5) * inner_x
			var z: float = (float(r) / float(SHELL_ROWS - 1) - 0.5) * (SIZE_Z - 0.12)
			var idx: int = r * SHELL_COLS + c
			var h: float = SHELL_L * (0.9 + rng.randf() * 0.2)
			m.paint(SHELL_RED if idx % 3 == 1 else BRASS, 0.2, 0.45, 0.0, PM.F_PAINT)
			var prof: Array = [Vector3(0.0, SHELL_R, 0.0), Vector3(h * 0.7, SHELL_R, 0.0), Vector3(h, SHELL_R * 0.55, 0.0)]
			m.lathe(prof, SHELL_SEGS, Vector3(x, BODY_H, z), Vector3.UP)
	return _finish(m, t0)


static func _finish(m: HDMesh, t0: int) -> Dictionary:
	var out: Dictionary = Common.finish(m, t0, 4, 0.15, 0.6, 0.6)
	out["mesh_instances"] = 1
	return out
