extends RefCounted
## HD scout drone (prop `scout_drone`, drone batedor): a small quadcopter, ~0.36 m motor to motor, origin at the
## centre of the body, front = -Z (camera pod). Two meshes on the shared prop material (prop_materials.gd): the
## airframe, and ONE rotor (hub + two blades, centred on its own axis) that scout_drone.gd instances four times
## through a MultiMesh so each rotor can spin on its own axis. 100% procedural.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")

const ARM: float = 0.105              # motor offset on X and Z
const MOTOR_Y: float = 0.012          # motor base height
const MOTOR_H: float = 0.034
const BLADE_LEN: float = 0.15
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.04

const SHELL: Color = Color(0.36, 0.40, 0.27)      # cerrado olive
const DARK: Color = Color(0.13, 0.14, 0.13)
const ACCENT: Color = Color(0.86, 0.42, 0.10)     # orange: readable against the sky
const LENS: Color = Color(0.05, 0.07, 0.09)

static var _cache: Dictionary = {}


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


## Rotor centres (body space), in the order of the MultiMesh instances.
static func rotor_positions() -> Array[Vector3]:
	var y: float = MOTOR_Y + MOTOR_H + 0.004
	return [Vector3(-ARM, y, -ARM), Vector3(ARM, y, -ARM), Vector3(-ARM, y, ARM), Vector3(ARM, y, ARM)]


## { mesh, rotor_mesh, triangles (airframe), rotor_triangles, vertices, materials, ... }
static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	# fuselage
	Common.paint(m, SHELL, 0.55, PM.F_PAINT, PM.GRAIN_Y)
	m.cbox(Vector3(0.0, 0.0, 0.0), Vector3(0.085, 0.04, 0.13), 0.008)
	# battery hump on top, darker
	Common.paint(m, DARK, 0.7, PM.F_PAINT, PM.GRAIN_Y)
	m.cbox(Vector3(0.0, 0.03, 0.012), Vector3(0.06, 0.02, 0.07), 0.004)
	# orange nose stripe on top-front
	Common.paint(m, ACCENT, 0.6, PM.F_PAINT, PM.GRAIN_Y)
	m.cbox(Vector3(0.0, 0.0215, -0.052), Vector3(0.05, 0.004, 0.016), 0.0)
	# camera gimbal under the nose
	Common.paint(m, DARK, 0.5, PM.F_PAINT, PM.GRAIN_Y)
	m.sphere(Vector3(0.0, -0.026, -0.05), Vector3(0.024, 0.022, 0.024), 8, 5)
	Common.paint(m, LENS, 0.2, PM.F_PAINT, PM.GRAIN_Y)
	m.sphere(Vector3(0.0, -0.028, -0.07), Vector3(0.012, 0.012, 0.007), 6, 3)
	# arms and motors
	var rp: Array[Vector3] = rotor_positions()
	for i: int in 4:
		var c: Vector3 = rp[i]
		var base: Vector3 = Vector3(c.x, MOTOR_Y + 0.004, c.z)
		Common.paint(m, DARK, 0.6, PM.F_PAINT, PM.GRAIN_Y)
		Common.beam(m, Vector3(c.x * 0.3, 0.004, c.z * 0.3), base, 0.016, 0.012, 0.0)
		Common.paint(m, ACCENT if i < 2 else SHELL.darkened(0.25), 0.5, PM.F_PAINT, PM.GRAIN_Y)
		m.lathe([Vector3(0.0, 0.017, 0.0), Vector3(MOTOR_H, 0.015, 0.0), Vector3(MOTOR_H, 0.0, 0.0)], 8, Vector3(c.x, MOTOR_Y, c.z), Vector3.UP)
		# landing foot under each motor
		Common.paint(m, DARK, 0.8, PM.F_PAINT, PM.GRAIN_Y)
		m.cbox(Vector3(c.x, -0.016, c.z), Vector3(0.012, 0.03, 0.012), 0.0)
	var out: Dictionary = Common.finish(m, t0, AO_RAYS, AO_RADIUS, 0.8, 0.55)
	# one rotor
	var r: HDMesh = HDMesh.new()
	Common.paint(r, DARK.lightened(0.05), 0.5, PM.F_PAINT, PM.GRAIN_Y)
	r.lathe([Vector3(-0.004, 0.0, 0.0), Vector3(-0.004, 0.009, 0.0), Vector3(0.008, 0.007, 0.0), Vector3(0.008, 0.0, 0.0)], 6, Vector3.ZERO, Vector3.UP)
	Common.paint(r, Color(0.20, 0.21, 0.20), 0.45, PM.F_PAINT, PM.GRAIN_Y)
	r.cbox(Vector3(0.0, 0.001, 0.0), Vector3(BLADE_LEN, 0.003, 0.016), 0.0)
	var ro: Dictionary = Common.finish(r, Time.get_ticks_usec(), 1, 0.01, 0.0, 1.0)
	out["rotor_mesh"] = ro["mesh"]
	out["rotor_triangles"] = ro["triangles"]
	return out
