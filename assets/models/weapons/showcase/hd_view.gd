extends WeaponViewBase
## Shared shell of the HD gun scripts (carbine_22_hd.gd, shotgun_12_hd.gd): Gun > Body + Mover, Muzzle, AdsAnchor,
## hip pose with toe-in and recoil, studio mode (gun space). No arms. weapon_view.gd uses only the static
## get_model() of the subclasses; this class exists for the studio renders and standalone use.
## Subclasses set the fields in _init() and override _model() / _animate_mover().

var hip_origin: Vector3 = Vector3.ZERO
var hip_yaw: float = 0.19
var hip_pivot: Vector3 = Vector3(0.20, -0.22, -0.30)
## Viewmodel depth scale (see weapon_view.gd); 1.0 = off.
var view_depth: float = 1.0
var muzzle_s: float = 1.0
## AdsAnchor in gun space: (s, y).
var ads_gun: Vector2 = Vector2.ZERO

var _gun: Node3D
var _body: MeshInstance3D
var _mover: MeshInstance3D
var _muzzle: Marker3D
var _ads: Marker3D
var _hip: bool = true
var _recoil: float = 0.0
var _cycle_t: float = -1.0
var _cycle_d: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_gun = Node3D.new()
	_gun.name = "Gun"
	add_child(_gun)
	_body = _mesh_instance("Body")
	_mover = _mesh_instance("Mover")
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	add_child(_muzzle)
	_ads = Marker3D.new()
	_ads.name = "AdsAnchor"
	add_child(_ads)


func _ready() -> void:
	if _body.mesh == null:
		setup(&"")


func _mesh_instance(node_name: String) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(m)
	return m


## Override: the cached model dictionary { body, mover, stats }.
func _model() -> Dictionary:
	return {}


## Override: t in 0..1 over the cycle, -1 when idle. Moves `_mover`.
func _animate_mover(_t: float) -> void:
	pass


func setup(_weapon_id: StringName) -> void:
	var model: Dictionary = _model()
	_body.mesh = model["body"]
	_mover.mesh = model["mover"]
	_apply_pose()


## false = gun space (butt plate at the origin, bore along -Z): used by the studio renders.
func set_hip_pose(enabled: bool) -> void:
	_hip = enabled
	_apply_pose()


func set_cast_shadows(enabled: bool) -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.cast_shadow = mode
	_mover.cast_shadow = mode


func play_fire() -> void:
	_recoil = 1.0


func play_cycle(duration_s: float) -> void:
	_cycle_d = maxf(duration_s, 0.05)
	_cycle_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	_recoil = maxf(_recoil - delta * 5.0, 0.0)
	if _cycle_t >= 0.0:
		_cycle_t += delta
		if _cycle_t >= _cycle_d:
			_cycle_t = -1.0
	_apply_pose()


func _apply_pose() -> void:
	var base: Transform3D = Transform3D.IDENTITY
	if _hip:
		var hip: float = clampf(1.0 - absf(position.x) / hip_origin.x, 0.0, 1.0)
		var rec: float = _recoil * _recoil
		var rot: Basis = Basis.from_euler(Vector3(rec * 0.15, hip_yaw * hip + rec * 0.01, 0.0))
		var sway: Vector3 = Vector3(0.0, sin(_time * 1.7) * 0.0015 + rec * 0.018, rec * 0.07)
		base = Transform3D(Basis.IDENTITY, hip_pivot + sway) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis.IDENTITY, hip_origin - hip_pivot)
		base = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, view_depth)), Vector3.ZERO) * base
	_gun.transform = base
	_muzzle.position = base * Vector3(0.0, 0.0, -muzzle_s)
	_ads.position = base * Vector3(0.0, ads_gun.y, -ads_gun.x)
	_animate_mover(_cycle_t / _cycle_d if _cycle_t >= 0.0 else -1.0)
