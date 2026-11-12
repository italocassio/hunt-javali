class_name Player
extends PlayerBase
## First-person hunter (docs §6.8, §8). Origin = feet, yaw on this node, pitch on Head.
## Reads keyboard/mouse through input actions, touch through TouchControls, and exposes the
## PlayerBase contract plus the bot hooks used by the tests.

signal weapon_changed(slot: int, weapon_id: StringName)
signal aim_changed(aiming: bool)

# --- Feel constants (not balance: balance lives in data/game.json and data/weapons.json) ---
const DRAW_TIME_S: float = 0.45               # weapon switch lockout
const FIRE_BUFFER_S: float = 0.2              # a tap slightly early still fires
const RECOIL_DECAY_TIME_CONSTANTS: float = 4.6   # recover_s = this many time constants
const RECOIL_YAW_JITTER: float = 0.25         # sideways kick as a fraction of the pitch kick
const CAMERA_ROLL_PER_DEG: float = 0.35       # roll jitter (deg) per degree of recoil
const CAMERA_PUNCH_PER_DEG: float = 0.012     # camera push back (m) per degree of recoil
const CAMERA_SHAKE_RATE: float = 18.0         # 1/s decay of the shake
const SCOPE_FADE_START: float = 0.6           # ads_t where the scoped weapon starts to fade out
const SCOPE_HIDE_WEAPON_AT: float = 0.95      # docs §7.3
const ZOOM_STEPS: float = 6.0                 # wheel steps across the zoom range
const CROUCH_HOLD_S: float = 0.35             # keyboard: longer than this = hold, shorter = toggle
const SPRINT_FORWARD_MIN: float = 0.5
const MOVING_SPEED_MIN: float = 0.5
const STRIDE_M: float = 2.1
const STEP_CROUCH_DB: float = -8.0
const KNOCKBACK_DECAY: float = 7.0
const HEARTBEAT_INTERVAL_S: float = 0.9
const DEATH_FALL_S: float = 0.8
const DEATH_EYE_HEIGHT_M: float = 0.3
const DEATH_ROLL_DEG: float = 70.0
const BOT_AIM_TIME_FALLBACK_S: float = 0.2

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _holder: WeaponHolder = $Head/Camera3D/WeaponHolder
@onready var _shape_node: CollisionShape3D = $CollisionShape3D

var _cfg: Dictionary = {}
var _request: HuntRequest = null
var _world: HuntWorld = null
var _items: ItemBelt = null
var _hud: Node = null
var _weapons: Array[Weapon] = []
var _slot: int = 0

var _health: float = 100.0
var _max_health: float = 100.0
var _alive: bool = true
var _input_enabled: bool = true
var _set_up: bool = false

var _pitch: float = 0.0
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0
var _shake: float = 0.0
var _crouching: bool = false
var _crouch_press_t: float = -1.0
var _eye_height: float = 1.65
var _sprinting: bool = false
var _ads_t: float = 0.0
var _aim_active: bool = false
var _zoom_value: float = 1.0
var _switch_left: float = 0.0
var _fire_buffer: float = 0.0
var _ignore_fire_until_release: bool = false
var _was_captured: bool = false
var _knock: Vector3 = Vector3.ZERO
var _stride: float = 0.0
var _heartbeat_t: float = 0.0
var _death_t: float = -1.0
var _thermal_emitted: bool = false
var _mouse_sens: float = 1.0
var _touch_sens: float = 1.0
var _invert_y: bool = false
var _speed_h: float = 0.0
var _gravity: float = 9.8

var _bot: bool = false
var _bot_move: Vector2 = Vector2.ZERO
var _bot_sprint: bool = false
var _bot_aim: bool = false


func _ready() -> void:
	_cfg = Data.get_game().get("player", {})
	_max_health = float(_cfg.get("max_health", 100.0))
	_health = _max_health
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_eye_height = float(_cfg.get("standing_eye_height_m", 1.65))
	_head.position.y = _eye_height
	_camera.fov = float(_cfg.get("base_fov_deg", 75.0))
	_shape_node.shape = _shape_node.shape.duplicate()
	_apply_capsule(float(_cfg.get("capsule_height_m", 1.8)))
	floor_snap_length = 0.4
	_read_settings()
	GameEvents.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	if _thermal_emitted:
		_thermal_emitted = false
		GameEvents.thermal_vision_changed.emit(false)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(request: HuntRequest, world: HuntWorld) -> void:
	_request = request
	_world = world
	_set_up = true
	_items = ItemBelt.new()
	_items.name = "ItemBelt"
	add_child(_items)
	_items.setup(request, self, world)
	_items.use_finished.connect(_on_item_use_finished)
	_items.binoculars_changed.connect(_on_binoculars_changed)

	var ids: Array[StringName] = request.weapon_ids.duplicate()
	if ids.is_empty():
		ids.append(Ids.W_CARBINE_22)
	for weapon_id: StringName in ids:
		var weapon: Weapon = Weapon.new()
		weapon.name = "Weapon_%s" % weapon_id
		add_child(weapon)
		if not weapon.setup(weapon_id, _items.reserve_mult):
			push_error("Player.setup: unknown weapon '%s'" % weapon_id)
			weapon.queue_free()
			continue
		weapon.fired.connect(_on_weapon_fired.bind(weapon))
		weapon.dry_fired.connect(_on_weapon_dry_fired.bind(weapon))
		weapon.cycle_started.connect(_on_weapon_cycle.bind(weapon))
		weapon.reload_started.connect(_on_weapon_reload_started.bind(weapon))
		weapon.reload_finished.connect(_on_weapon_reload_finished.bind(weapon))
		weapon.reload_cancelled.connect(_on_weapon_reload_cancelled.bind(weapon))
		_weapons.append(weapon)
		_holder.add_view(weapon_id)
	_camera.far = _resolve_view_distance(request)
	_camera.make_current()
	_slot = 0
	if not _weapons.is_empty():
		_holder.select(0)
		_holder.play_draw(DRAW_TIME_S)
		_reset_zoom()
	_hud = AssetLoader.instantiate(ScenePaths.HUD)
	if _hud != null:
		add_child(_hud)
		_hud.call("bind", self, world)
	if not GameEvents.hunt_ended.is_connected(_on_hunt_ended):
		GameEvents.hunt_ended.connect(_on_hunt_ended)


func _resolve_view_distance(request: HuntRequest) -> float:
	var quality: String = String(request.quality)
	if quality == "":
		var setting: Variant = Profile.get_setting("quality")
		quality = String(setting) if setting != null else "auto"
	if quality == "auto":
		quality = "low" if InputSetup.is_touch_mode() else "medium"
	var presets: Dictionary = Data.get_game().get("quality_presets", {})
	var preset: Dictionary = presets.get(quality, presets.get("medium", {}))
	return float(preset.get("view_distance_m", _camera.far))


func _read_settings() -> void:
	_mouse_sens = _setting_float("mouse_sensitivity", 1.0)
	_touch_sens = _setting_float("touch_sensitivity", 1.0)
	var inv: Variant = Profile.get_setting("invert_y")
	_invert_y = bool(inv) if inv != null else false


func _setting_float(key: String, fallback: float) -> float:
	var v: Variant = Profile.get_setting(key)
	return float(v) if v != null else fallback


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key in ["mouse_sensitivity", "touch_sensitivity", "invert_y"]:
		_read_settings()


# ---------------------------------------------------------------------------
# PlayerBase contract
# ---------------------------------------------------------------------------

func apply_damage(amount: float, source_position: Vector3, knockback_mps: float = 0.0) -> void:
	if not _alive or amount <= 0.0:
		return
	var reduction: float = _items.damage_reduction if _items != null else 0.0
	var final_amount: float = amount * (1.0 - reduction)
	_health = maxf(_health - final_amount, 0.0)
	var away: Vector3 = global_position - source_position
	away.y = 0.0
	if knockback_mps > 0.0 and away.length_squared() > 0.0001:
		_knock += away.normalized() * knockback_mps
	_shake = maxf(_shake, final_amount * 0.1)
	GameEvents.player_damaged.emit(final_amount, source_position, _health)
	if _health <= 0.0:
		_die()
	else:
		Sfx.play(&"player_hurt")


func heal(amount: float) -> void:
	if not _alive or amount <= 0.0:
		return
	var before: float = _health
	_health = minf(_health + amount, _max_health)
	var healed: float = _health - before
	if healed <= 0.0:
		return
	Sfx.play(&"player_heal")
	GameEvents.player_healed.emit(healed, _health)


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return _max_health


func get_eye_position() -> Vector3:
	if is_inside_tree() and _head != null:
		return _head.global_position
	return global_position + Vector3(0.0, _eye_height, 0.0)


func get_look_direction() -> Vector3:
	if is_inside_tree() and _camera != null:
		return -_camera.global_transform.basis.z
	return -global_transform.basis.z


func is_crouching() -> bool:
	return _crouching


func get_noise_radius() -> float:
	if _speed_h < MOVING_SPEED_MIN:
		return 0.0
	if _crouching:
		return float(_cfg.get("noise_radius_crouch_m", 0.0))
	if _sprinting:
		return float(_cfg.get("noise_radius_sprint_m", 0.0))
	return float(_cfg.get("noise_radius_walk_m", 0.0))


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_fire_buffer = 0.0
		if _thermal_emitted:
			_thermal_emitted = false
			GameEvents.thermal_vision_changed.emit(false)


func get_current_weapon_id() -> StringName:
	var w: Weapon = _weapon()
	return w.weapon_id if w != null else &""


func get_ammo_in_mag() -> int:
	var w: Weapon = _weapon()
	return w.ammo_in_mag if w != null else 0


func get_ammo_reserve() -> int:
	var w: Weapon = _weapon()
	return w.ammo_reserve if w != null else 0


func is_reloading() -> bool:
	var w: Weapon = _weapon()
	return w != null and w.is_reloading()


# ---------------------------------------------------------------------------
# Extra public API used by the HUD and touch controls (same package)
# ---------------------------------------------------------------------------

func get_weapon() -> Weapon:
	return _weapon()


func get_weapon_count() -> int:
	return _weapons.size()


func get_weapon_slot() -> int:
	return _slot


func get_items() -> ItemBelt:
	return _items


func get_camera() -> Camera3D:
	return _camera


func get_weapon_holder() -> WeaponHolder:
	return _holder


func get_ads_t() -> float:
	return _ads_t


func is_aiming() -> bool:
	return _aim_active


func is_sprinting() -> bool:
	return _sprinting


func is_binocular_view() -> bool:
	return _items != null and _items.is_binoculars_active()


## 0..1 opacity of the scope overlay (scoped weapons) or binocular view.
func get_scope_t() -> float:
	if is_binocular_view():
		return smoothstep(0.0, 1.0, _ads_t)
	var w: Weapon = _weapon()
	if w != null and w.is_scoped():
		return smoothstep(SCOPE_FADE_START, 1.0, _ads_t)
	return 0.0


func get_zoom_value() -> float:
	return _zoom_value


func get_zoom_range() -> Vector2:
	if is_binocular_view():
		var z: float = _items.get_binoculars_zoom()
		return Vector2(z, z)
	var w: Weapon = _weapon()
	if w == null:
		return Vector2.ONE
	return Vector2(w.get_def_float("ads_zoom_min"), w.get_def_float("ads_zoom_max"))


func has_zoom_range() -> bool:
	var r: Vector2 = get_zoom_range()
	return r.y > r.x + 0.001


func get_zoom_fraction() -> float:
	var r: Vector2 = get_zoom_range()
	if r.y <= r.x:
		return 0.0
	return clampf((_zoom_value - r.x) / (r.y - r.x), 0.0, 1.0)


func set_zoom_fraction(t: float) -> void:
	var r: Vector2 = get_zoom_range()
	_zoom_value = lerpf(r.x, r.y, clampf(t, 0.0, 1.0))


func step_zoom(direction: int) -> void:
	var r: Vector2 = get_zoom_range()
	if r.y <= r.x:
		return
	_zoom_value = clampf(_zoom_value + float(direction) * (r.y - r.x) / ZOOM_STEPS, r.x, r.y)


func get_fov_deg() -> float:
	return _camera.fov


## Current half-angle of the bullet cone in degrees (dynamic crosshair).
func get_spread_deg() -> float:
	var w: Weapon = _weapon()
	if w == null:
		return 0.0
	return w.get_spread_deg(_ads_t, _move_frac())


func has_thermal() -> bool:
	return _items != null and _items.thermal_range_m > 0.0


func get_world() -> HuntWorld:
	return _world


## Touch look pad feeds raw pixel deltas here.
func apply_touch_look(rel_px: Vector2) -> void:
	if not _can_look():
		return
	_apply_look(rel_px * deg_to_rad(float(_cfg.get("touch_deg_per_px", 0.25))) * _touch_sens)


func request_pause() -> void:
	if _hud != null and _alive and not _bot:
		_hud.call("open_pause")


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _bot or not _input_enabled or not _alive:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.device == InputEvent.DEVICE_ID_EMULATION or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		_apply_look(motion.relative * deg_to_rad(float(_cfg.get("mouse_deg_per_px", 0.12))) * _mouse_sens)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.device != InputEvent.DEVICE_ID_EMULATION \
				and not InputSetup.is_touch_mode() and not get_tree().paused \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_ignore_fire_until_release = true   # the capturing click must not shoot


func _can_look() -> bool:
	return _alive and _input_enabled and not _bot


func _apply_look(rel_rad: Vector2) -> void:
	var scale_factor: float = _sensitivity_scale()
	var dy: float = rel_rad.y * (1.0 if _invert_y else -1.0)
	rotation.y -= rel_rad.x * scale_factor
	var max_pitch: float = deg_to_rad(float(_cfg.get("max_pitch_deg", 85.0)))
	_pitch = clampf(_pitch + dy * scale_factor, -max_pitch, max_pitch)
	_holder.add_look(Vector2(rel_rad.x, -dy) * scale_factor)


## Sensitivity shrinks in proportion to the zoom (tan(fov/2) ratio).
func _sensitivity_scale() -> float:
	var base: float = deg_to_rad(float(_cfg.get("base_fov_deg", 75.0)))
	return tan(deg_to_rad(_camera.fov) * 0.5) / tan(base * 0.5)


func _read_move() -> Vector2:
	if _bot:
		return _bot_move
	if not _input_enabled or not _alive:
		return Vector2.ZERO
	var v: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	return Vector2(v.x, -v.y)


func _want_aim() -> bool:
	if not _alive:
		return false
	if _bot:
		return _bot_aim
	return _input_enabled and Input.is_action_pressed(&"aim")


func _fire_allowed_by_input() -> bool:
	if _bot or InputSetup.is_touch_mode():
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _ignore_fire_until_release


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _death_t >= 0.0:
		_update_death(delta)
		return
	_pump_discrete_input(delta)
	_update_aim(delta)
	_update_camera(delta)
	_update_web_pause()
	_update_heartbeat(delta)
	_holder.ads_t = _ads_t
	_holder.move_frac = _move_frac() if is_on_floor() else 0.0


func _pump_discrete_input(delta: float) -> void:
	_switch_left = maxf(_switch_left - delta, 0.0)
	_fire_buffer = maxf(_fire_buffer - delta, 0.0)
	if not _input_enabled or not _alive or _bot:
		return
	if Input.is_action_just_released(&"fire"):
		_ignore_fire_until_release = false
	if not Input.is_action_pressed(&"fire"):
		_ignore_fire_until_release = false
	if Input.is_action_just_pressed(&"fire") and _fire_allowed_by_input():
		_fire_buffer = FIRE_BUFFER_S
	if _fire_buffer > 0.0 and _fire_allowed_by_input() and _try_fire():
		_fire_buffer = 0.0
	if Input.is_action_just_pressed(&"reload"):
		_start_reload()
	if Input.is_action_just_pressed(&"weapon_1"):
		_select_weapon(0)
	if Input.is_action_just_pressed(&"weapon_2"):
		_select_weapon(1)
	if Input.is_action_just_pressed(&"weapon_swap"):
		_select_weapon((_slot + 1) % maxi(_weapons.size(), 1))
	if Input.is_action_just_pressed(&"use_item"):
		_use_selected_item()
	if Input.is_action_just_pressed(&"item_next") and _items != null:
		_items.next()
	if Input.is_action_just_pressed(&"dog_command"):
		GameEvents.dog_command_requested.emit()
	if Input.is_action_just_pressed(&"zoom_in"):
		step_zoom(1)
	if Input.is_action_just_pressed(&"zoom_out"):
		step_zoom(-1)
	_update_crouch_input(delta)


func _update_crouch_input(delta: float) -> void:
	if Input.is_action_just_pressed(&"crouch"):
		_crouching = not _crouching
		_crouch_press_t = 0.0
	elif Input.is_action_pressed(&"crouch") and _crouch_press_t >= 0.0:
		_crouch_press_t += delta
	elif Input.is_action_just_released(&"crouch"):
		# Keyboard: holding Ctrl crouches only while held. Touch button toggles.
		if _crouch_press_t >= CROUCH_HOLD_S and not InputSetup.is_touch_mode():
			_crouching = false
		_crouch_press_t = -1.0


func _update_aim(delta: float) -> void:
	var binoc: bool = is_binocular_view()
	var wants: bool = (_want_aim() or binoc) and _alive and _can_aim()
	var w: Weapon = _weapon()
	var time_s: float = BOT_AIM_TIME_FALLBACK_S
	if w != null:
		time_s = maxf(w.get_def_float("ads_time_s"), 0.01)
	var previous: float = _ads_t
	_ads_t = move_toward(_ads_t, 1.0 if wants else 0.0, delta / time_s)
	var aim_now: bool = wants and not binoc
	if aim_now != _aim_active:
		_aim_active = aim_now
		aim_changed.emit(_aim_active)
		if w != null and w.is_scoped():
			Sfx.play(&"scope_in" if aim_now else &"scope_out")
		_update_thermal()
	if is_zero_approx(previous - _ads_t) and not wants:
		pass
	# Scoped weapon disappears once the overlay is (almost) opaque; binoculars hide it entirely.
	var hide_weapon: bool = binoc or (w != null and w.is_scoped() and _ads_t >= SCOPE_HIDE_WEAPON_AT)
	_holder.set_weapon_hidden(hide_weapon or not _alive)


func _can_aim() -> bool:
	return not _items_busy()


func _items_busy() -> bool:
	return _items != null and _items.is_busy()


func _update_thermal() -> void:
	var active: bool = has_thermal() and _aim_active and _alive and _input_enabled
	if active != _thermal_emitted:
		_thermal_emitted = active
		GameEvents.thermal_vision_changed.emit(active)


func _update_camera(delta: float) -> void:
	var zoom_target: float = _zoom_value
	if is_binocular_view():
		zoom_target = _items.get_binoculars_zoom()
	var zoom_eff: float = lerpf(1.0, maxf(zoom_target, 1.0), smoothstep(0.0, 1.0, _ads_t))
	var base: float = deg_to_rad(float(_cfg.get("base_fov_deg", 75.0)))
	_camera.fov = rad_to_deg(2.0 * atan(tan(base * 0.5) / zoom_eff))
	# Recoil recovery (exponential), camera shake decay.
	var w: Weapon = _weapon()
	var recover_s: float = 0.2 if w == null else maxf(w.get_def_float("recoil_recover_s"), 0.02)
	var k: float = 1.0 - exp(-RECOIL_DECAY_TIME_CONSTANTS / recover_s * delta)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, k)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, k)
	_shake = lerpf(_shake, 0.0, 1.0 - exp(-CAMERA_SHAKE_RATE * delta))
	_head.rotation.x = _pitch + _recoil_pitch
	_head.rotation.y = _recoil_yaw
	_camera.rotation.z = deg_to_rad(_shake * CAMERA_ROLL_PER_DEG) * sin(Time.get_ticks_msec() * 0.05)
	_camera.position.z = _shake * CAMERA_PUNCH_PER_DEG
	# Eye height follows the crouch.
	var stand_h: float = float(_cfg.get("standing_eye_height_m", 1.65))
	var crouch_h: float = float(_cfg.get("crouch_eye_height_m", 1.05))
	var rate: float = (stand_h - crouch_h) / maxf(float(_cfg.get("crouch_transition_s", 0.2)), 0.01)
	_eye_height = move_toward(_eye_height, crouch_h if _crouching else stand_h, rate * delta)
	_head.position.y = _eye_height
	var cap_stand: float = float(_cfg.get("capsule_height_m", 1.8))
	var cap_crouch: float = float(_cfg.get("crouch_capsule_height_m", 1.2))
	var t: float = inverse_lerp(stand_h, crouch_h, _eye_height)
	_apply_capsule(lerpf(cap_stand, cap_crouch, clampf(t, 0.0, 1.0)))


func _apply_capsule(height: float) -> void:
	var capsule: CapsuleShape3D = _shape_node.shape as CapsuleShape3D
	capsule.height = height
	_shape_node.position.y = height * 0.5


func _update_web_pause() -> void:
	if _bot or not _set_up:
		return
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and _alive and _input_enabled and not InputSetup.is_touch_mode() \
			and not get_tree().paused:
		request_pause()   # browser released the pointer lock (docs §11)
	_was_captured = captured


func _update_heartbeat(delta: float) -> void:
	if not _alive:
		return
	if _health / maxf(_max_health, 1.0) > float(_cfg.get("low_health_frac", 0.3)):
		_heartbeat_t = 0.0
		return
	_heartbeat_t -= delta
	if _heartbeat_t <= 0.0:
		_heartbeat_t = HEARTBEAT_INTERVAL_S
		Sfx.play(&"heartbeat")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _set_up and not _bot and _alive and _input_enabled:
		request_pause()


func _physics_process(delta: float) -> void:
	var move_in: Vector2 = _read_move()
	if move_in.length() > 1.0:
		move_in = move_in.normalized()
	var want_aim: bool = _want_aim() or is_binocular_view()
	var want_sprint: bool = _bot_sprint if _bot else (_input_enabled and Input.is_action_pressed(&"sprint"))
	_sprinting = want_sprint and move_in.y > SPRINT_FORWARD_MIN and not _crouching and not want_aim \
		and _alive and not _items_busy()
	var speed: float = float(_cfg.get("walk_speed_mps", 4.0))
	if _crouching:
		speed = float(_cfg.get("crouch_speed_mps", 2.0))
	elif _sprinting:
		speed = float(_cfg.get("sprint_speed_mps", 6.5))
	if want_aim:
		speed *= float(_cfg.get("aim_speed_mult", 0.6))
	var basis_yaw: Basis = global_transform.basis
	var wish: Vector3 = (basis_yaw.x * move_in.x + (-basis_yaw.z) * move_in.y) * speed
	var h: Vector3 = Vector3(velocity.x - _knock.x, 0.0, velocity.z - _knock.z)
	h = h.move_toward(wish, float(_cfg.get("acceleration_mps2", 30.0)) * delta)
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-KNOCKBACK_DECAY * delta))
	velocity.x = h.x + _knock.x
	velocity.z = h.z + _knock.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	_speed_h = Vector2(h.x, h.z).length()
	_update_footsteps(delta)


func _move_frac() -> float:
	return _speed_h / maxf(float(_cfg.get("walk_speed_mps", 4.0)), 0.1)


func _update_footsteps(delta: float) -> void:
	if not is_on_floor() or _speed_h < MOVING_SPEED_MIN:
		return
	_stride += _speed_h * delta
	if _stride >= STRIDE_M:
		_stride = 0.0
		Sfx.play(&"step_grass", STEP_CROUCH_DB if _crouching else 0.0)


# ---------------------------------------------------------------------------
# Weapons and items
# ---------------------------------------------------------------------------

func _weapon() -> Weapon:
	if _slot < 0 or _slot >= _weapons.size():
		return null
	return _weapons[_slot]


func _reset_zoom() -> void:
	_zoom_value = get_zoom_range().x


func _try_fire() -> bool:
	var w: Weapon = _weapon()
	if w == null or not _alive or not _input_enabled and not _bot:
		return false
	if _switch_left > 0.0 or _items_busy() or is_binocular_view():
		return false
	var exclude: Array[RID] = [get_rid()]
	return w.fire(_camera, _ads_t, _move_frac(), exclude, get_parent())


func _start_reload() -> void:
	var w: Weapon = _weapon()
	if w == null or not _alive or _items_busy() or _switch_left > 0.0:
		return
	w.start_reload()


func _select_weapon(slot: int) -> void:
	if slot == _slot or slot < 0 or slot >= _weapons.size() or not _alive or _items_busy():
		return
	_weapon().holster()
	_holder.stop_reload()
	_slot = slot
	_holder.select(slot)
	_holder.play_draw(DRAW_TIME_S)
	_switch_left = DRAW_TIME_S
	_reset_zoom()
	Sfx.play(&"weapon_swap")
	weapon_changed.emit(slot, _weapons[slot].weapon_id)
	if _aim_active:
		_update_thermal()


func _use_selected_item() -> void:
	if _items == null or not _alive:
		return
	_items.use_selected()


func _on_weapon_fired(_shot_id: int, weapon: Weapon) -> void:
	if weapon != _weapon():
		return
	var recoil_deg: float = weapon.get_def_float("recoil_pitch_deg")
	_holder.play_fire(recoil_deg)
	_recoil_pitch += deg_to_rad(recoil_deg)
	var jitter: float = randf_range(-1.0, 1.0) * RECOIL_YAW_JITTER * deg_to_rad(recoil_deg)
	_recoil_yaw += jitter
	_shake = maxf(_shake, recoil_deg)
	Sfx.play(StringName(str(weapon.def.get("shot_sfx", ""))))


func _on_weapon_dry_fired(weapon: Weapon) -> void:
	if weapon == _weapon():
		Sfx.play(&"dry_fire")


func _on_weapon_cycle(duration_s: float, weapon: Weapon) -> void:
	if weapon != _weapon():
		return
	_holder.play_cycle(duration_s)
	var cycle_sfx: String = str(weapon.def.get("cycle_sfx", ""))
	if cycle_sfx != "":
		Sfx.play(StringName(cycle_sfx))


func _on_weapon_reload_started(duration_s: float, weapon: Weapon) -> void:
	if weapon != _weapon():
		return
	_holder.play_reload(duration_s)
	Sfx.play(&"reload_start")


func _on_weapon_reload_finished(weapon: Weapon) -> void:
	if weapon == _weapon():
		Sfx.play(&"reload_end")


func _on_weapon_reload_cancelled(weapon: Weapon) -> void:
	if weapon == _weapon():
		_holder.stop_reload()


func _on_item_use_finished(_item_id: StringName) -> void:
	pass


func _on_binoculars_changed(active: bool) -> void:
	if active:
		var w: Weapon = _weapon()
		if w != null:
			w.cancel_reload()
		_zoom_value = _items.get_binoculars_zoom()
	else:
		_reset_zoom()
		_holder.play_draw(DRAW_TIME_S)
	_update_thermal()


# ---------------------------------------------------------------------------
# Death and end of hunt
# ---------------------------------------------------------------------------

func _die() -> void:
	if not _alive:
		return
	_alive = false
	_input_enabled = false
	_death_t = 0.0
	_crouching = false
	_ads_t = 0.0
	if _items != null:
		_items.cancel_use()
		_items.set_binoculars(false)
	_holder.set_weapon_hidden(true)
	if _thermal_emitted:
		_thermal_emitted = false
		GameEvents.thermal_vision_changed.emit(false)
	InputSetup.release_all_actions()
	Sfx.play(&"player_death")
	GameEvents.player_died.emit()


func _update_death(delta: float) -> void:
	_death_t = minf(_death_t + delta, DEATH_FALL_S)
	var t: float = smoothstep(0.0, 1.0, _death_t / DEATH_FALL_S)
	_head.position.y = lerpf(_eye_height, DEATH_EYE_HEIGHT_M, t)
	_camera.rotation.z = deg_to_rad(DEATH_ROLL_DEG) * t
	_camera.fov = lerpf(_camera.fov, float(_cfg.get("base_fov_deg", 75.0)), t)


func _on_hunt_ended(_result: HuntResult) -> void:
	set_input_enabled(false)
	_aim_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	InputSetup.release_all_actions()
	if _hud != null:
		_hud.call("on_hunt_ended")


# ---------------------------------------------------------------------------
# Bot hooks (tests). Bot mode ignores real input and never captures the mouse.
# ---------------------------------------------------------------------------

func bot_set_enabled(enabled: bool) -> void:
	_bot = enabled
	if not enabled:
		_bot_move = Vector2.ZERO
		_bot_sprint = false
		_bot_aim = false


func bot_set_move(direction: Vector2, sprint: bool) -> void:
	_bot_move = direction.limit_length(1.0)
	_bot_sprint = sprint


func bot_look_at(point: Vector3) -> void:
	var d: Vector3 = point - get_eye_position()
	if d.length_squared() < 0.0001:
		return
	rotation.y = atan2(-d.x, -d.z)
	var max_pitch: float = deg_to_rad(float(_cfg.get("max_pitch_deg", 85.0)))
	_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -max_pitch, max_pitch)
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_head.rotation = Vector3(_pitch, 0.0, 0.0)


func bot_set_aim(aiming: bool) -> void:
	_bot_aim = aiming


func bot_fire() -> bool:
	if not _alive:
		return false
	return _try_fire()


func bot_reload() -> void:
	_start_reload()


## Slot is 0-based (same as Profile.set_loadout_weapon).
func bot_select_weapon(slot: int) -> void:
	_select_weapon(slot)


func bot_use_item(item_id: StringName) -> bool:
	if _items == null or not _alive:
		return false
	return _items.use_item(item_id)


func bot_dog_command() -> void:
	GameEvents.dog_command_requested.emit()
