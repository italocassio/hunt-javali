class_name WeaponHolder
extends Node3D
## Child of the camera. Owns the first-person weapon views and animates the holder:
## aim offset, recoil kick, walk bob, look sway, draw and reload dip. Falls back to a plain
## box weapon when the art asset is missing (docs §7.3).

const ADS_KICK_MULT: float = 0.5
const KICK_Z_PER_DEG: float = 0.018          # m pushed back per degree of recoil
const KICK_RISE_PER_DEG: float = 0.006       # m raised per degree of recoil
const KICK_PITCH_PER_DEG: float = 0.9        # degrees of weapon pitch per degree of recoil
const KICK_RECOVER_RATE: float = 14.0        # 1/s, exponential return of the kick
const BOB_FREQUENCY: float = 9.0             # rad/s at walking speed
const BOB_AMPLITUDE_M: float = 0.012
const BOB_ADS_MULT: float = 0.15
const SWAY_LAG_RATE: float = 10.0
const SWAY_PER_RAD: float = 0.08             # m of lateral lag per radian of look
const SWAY_MAX_M: float = 0.04
const DRAW_START_DROP_M: float = 0.35
const RELOAD_DIP_M: float = 0.10
const RELOAD_DIP_TILT_DEG: float = 18.0
const FLASH_TIME_S: float = 0.06
const FLASH_SIZE_M: float = 0.12

## 0 hip .. 1 aimed. Set by the Player every frame.
var ads_t: float = 0.0
## Horizontal speed relative to walking speed (0..~1.6).
var move_frac: float = 0.0

var _views: Array[WeaponViewBase] = []
var _fallback: Array[bool] = []
var _current: int = -1
var _hidden_by_scope: bool = false
var _kick: float = 0.0              # recoil strength in degrees, decays
var _bob_t: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _draw_left: float = 0.0
var _draw_total: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _flash: MeshInstance3D = null
var _flash_left: float = 0.0
var _base_rotation: Vector3 = Vector3.ZERO


func add_view(weapon_id: StringName) -> int:
	var node: Node = AssetLoader.instantiate(ScenePaths.weapon_view(weapon_id))
	var view: WeaponViewBase = node as WeaponViewBase
	var is_fallback: bool = false
	if view == null:
		if node != null:
			node.queue_free()
		view = WeaponViewBase.create_fallback()
		is_fallback = true
	view.name = "View_%s" % weapon_id
	add_child(view)
	view.setup(weapon_id)
	view.visible = false
	_views.append(view)
	_fallback.append(is_fallback)
	return _views.size() - 1


func select(index: int) -> void:
	if index < 0 or index >= _views.size():
		return
	if _current >= 0:
		_views[_current].visible = false
	_current = index
	_views[_current].visible = not _hidden_by_scope
	_reload_left = 0.0
	_ensure_flash()


func get_current_view() -> WeaponViewBase:
	if _current < 0:
		return null
	return _views[_current]


func is_current_fallback() -> bool:
	return _current >= 0 and _fallback[_current]


## Hides or shows the whole weapon (scope overlay, binoculars, death).
func set_weapon_hidden(hidden: bool) -> void:
	_hidden_by_scope = hidden
	if _current >= 0:
		_views[_current].visible = not hidden


func play_fire(recoil_deg: float) -> void:
	var view: WeaponViewBase = get_current_view()
	if view == null:
		return
	view.play_fire()
	_kick += recoil_deg * lerpf(1.0, ADS_KICK_MULT, ads_t)
	if is_current_fallback() and _flash != null:
		_flash_left = FLASH_TIME_S
		_flash.visible = true


func play_cycle(duration_s: float) -> void:
	var view: WeaponViewBase = get_current_view()
	if view != null:
		view.play_cycle(duration_s)


func play_reload(duration_s: float) -> void:
	var view: WeaponViewBase = get_current_view()
	if view != null:
		view.play_reload(duration_s)
	_reload_total = duration_s
	_reload_left = duration_s


func stop_reload() -> void:
	_reload_left = 0.0


func play_draw(duration_s: float) -> void:
	var view: WeaponViewBase = get_current_view()
	if view != null:
		view.play_draw(duration_s)
	_draw_total = maxf(duration_s, 0.01)
	_draw_left = duration_s


## Look input in radians (x = yaw delta, y = pitch delta) for weapon sway.
func add_look(delta_rad: Vector2) -> void:
	_sway += delta_rad


func _process(delta: float) -> void:
	var view: WeaponViewBase = get_current_view()
	if view == null:
		return
	# Aim offset moves the view root so the AdsAnchor lands on the camera axis.
	var anchor: Node3D = view.get_ads_anchor()
	var ads_offset: Vector3 = Vector3.ZERO
	if anchor != null:
		ads_offset = Vector3(-anchor.position.x, -anchor.position.y, 0.0)
	view.position = Vector3.ZERO.lerp(ads_offset, smoothstep(0.0, 1.0, ads_t))

	# Kick: pushes the holder back/up and pitches it; recovers exponentially.
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-KICK_RECOVER_RATE * delta))
	var pos: Vector3 = Vector3(0.0, _kick * KICK_RISE_PER_DEG, _kick * KICK_Z_PER_DEG)
	var rot_x: float = deg_to_rad(_kick * KICK_PITCH_PER_DEG)

	# Walk bob, damped when aiming.
	_bob_t += delta * BOB_FREQUENCY * clampf(move_frac, 0.0, 1.6)
	var bob_mult: float = lerpf(1.0, BOB_ADS_MULT, ads_t) * clampf(move_frac, 0.0, 1.6)
	pos.y += sin(_bob_t * 2.0) * BOB_AMPLITUDE_M * bob_mult
	pos.x += cos(_bob_t) * BOB_AMPLITUDE_M * bob_mult

	# Look sway: the weapon lags behind the camera, then catches up.
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-SWAY_LAG_RATE * delta))
	pos.x += clampf(-_sway.x * SWAY_PER_RAD, -SWAY_MAX_M, SWAY_MAX_M) * (1.0 - ads_t)
	pos.y += clampf(_sway.y * SWAY_PER_RAD, -SWAY_MAX_M, SWAY_MAX_M) * (1.0 - ads_t)

	# Draw: weapon rises from below.
	if _draw_left > 0.0:
		_draw_left = maxf(_draw_left - delta, 0.0)
		var d: float = _draw_left / _draw_total
		pos.y -= DRAW_START_DROP_M * d * d

	# Reload dip (only the fallback model; real assets animate themselves).
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		if is_current_fallback():
			var phase: float = sin(PI * (1.0 - _reload_left / maxf(_reload_total, 0.01)))
			pos.y -= RELOAD_DIP_M * phase
			rot_x -= deg_to_rad(RELOAD_DIP_TILT_DEG) * phase

	position = pos
	rotation = _base_rotation + Vector3(rot_x, 0.0, 0.0)

	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _flash != null:
			_flash.visible = false


func _ensure_flash() -> void:
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()
		_flash = null
	if not is_current_fallback():
		return
	var muzzle: Node3D = _views[_current].get_muzzle()
	if muzzle == null:
		return
	_flash = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = FLASH_SIZE_M * 0.5
	mesh.height = FLASH_SIZE_M
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mesh.material = mat
	_flash.mesh = mesh
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	muzzle.add_child(_flash)
