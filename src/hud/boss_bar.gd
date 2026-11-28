class_name BossBar
extends Control
## Health bar of the horde boss ("Cachaço rei", docs/plano_horda_boss.md 4.3): the name in capitals above a dark
## track with a blood-red fill, a thin light border and four dividers. Pure display and read-only (it ignores the
## mouse): the Hud feeds it the boss health in 0..100 from GameEvents.horde_boss_health_changed and decides where it
## sits. The fill chases the target (CHASE_PCT_PER_FRAME at 60 fps, times delta) so a 4 Hz signal does not show as jumps.

const BOSS_NAME: String = "CACHAÇO REI"
const WIDTH_FRAC: float = 0.44        # of the screen width
const MIN_WIDTH_PX: float = 320.0
const MAX_WIDTH_PX: float = 720.0
const BAR_HEIGHT_PX: float = 22.0
const NAME_FONT_PX: int = 20
const NAME_OUTLINE_PX: int = 5
const NAME_GAP_PX: float = 2.0        # name to bar
const DIVIDER_COUNT: int = 4
const DIVIDER_WIDTH_PX: float = 2.0
const BORDER_PX: float = 2.0
const CHASE_PCT_PER_FRAME: float = 8.0   # at CHASE_REF_FPS
const CHASE_REF_FPS: float = 60.0
const FADE_IN_S: float = 0.25
const TRACK_ALPHA: float = UiKit.VEIL_STRONG_ALPHA
const BORDER_ALPHA: float = 0.75
const DIVIDER_ALPHA: float = 0.8
const FILL_DARKEN: float = 0.25   # blood red derived from UiKit.DANGER_COLOR (no blood token in the UiKit yet)

var _target_pct: float = 0.0
var _shown_pct: float = 0.0
var _name_label: Label = Label.new()
var _name_height: float = 0.0
var _tween: Tween = null


## Width the bar takes on a screen `screen_width_px` wide: 44%, clamped to 320..720 px.
static func width_for(screen_width_px: float) -> float:
	return clampf(screen_width_px * WIDTH_FRAC, MIN_WIDTH_PX, MAX_WIDTH_PX)


func _init() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.name = "BossName"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.theme_type_variation = &"HudBigLabel"
	_name_label.text = BOSS_NAME
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_PX)
	_name_label.add_theme_color_override("font_color", UiKit.TEXT_COLOR)
	_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_name_label.add_theme_constant_override("outline_size", NAME_OUTLINE_PX)
	add_child(_name_label)
	_name_height = ceilf(_name_label.get_combined_minimum_size().y)
	custom_minimum_size = Vector2(MIN_WIDTH_PX, get_total_height())
	modulate.a = 0.0
	visible = false
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = get_bar_rect()
	var track: Color = Color(UiKit.VEIL_COLOR.r, UiKit.VEIL_COLOR.g, UiKit.VEIL_COLOR.b, TRACK_ALPHA)
	draw_rect(rect, track, true)
	var inner: Rect2 = rect.grow(-BORDER_PX)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		var fill: Rect2 = Rect2(inner.position, Vector2(inner.size.x * clampf(_shown_pct, 0.0, 100.0) * 0.01, inner.size.y))
		draw_rect(fill, UiKit.DANGER_COLOR.darkened(FILL_DARKEN), true)
		var mark: Color = Color(UiKit.VEIL_COLOR.r, UiKit.VEIL_COLOR.g, UiKit.VEIL_COLOR.b, DIVIDER_ALPHA)
		for i: int in range(1, DIVIDER_COUNT + 1):
			var x: float = inner.position.x + inner.size.x * float(i) / float(DIVIDER_COUNT + 1)
			draw_rect(Rect2(x - DIVIDER_WIDTH_PX * 0.5, inner.position.y, DIVIDER_WIDTH_PX, inner.size.y), mark, true)
	var border: Color = Color(UiKit.TEXT_COLOR.r, UiKit.TEXT_COLOR.g, UiKit.TEXT_COLOR.b, BORDER_ALPHA)
	draw_rect(rect, border, false, BORDER_PX)


func _process(delta: float) -> void:
	var step: float = CHASE_PCT_PER_FRAME * CHASE_REF_FPS * delta
	_shown_pct = move_toward(_shown_pct, _target_pct, step)
	queue_redraw()
	if is_equal_approx(_shown_pct, _target_pct):
		_shown_pct = _target_pct
		set_process(false)


## Boss health in 0..100. A value above 0 shows the bar (fading in when it was hidden and jumping straight to the
## value then); 0 only empties it: the Hud decides when to hide.
func set_health_pct(pct: float) -> void:
	_target_pct = clampf(pct, 0.0, 100.0)
	if _target_pct > 0.0 and not visible:
		_shown_pct = _target_pct
		visible = true
		_fade_in()
	if not is_equal_approx(_shown_pct, _target_pct):
		set_process(true)
	queue_redraw()


## Hides at once and forgets the value.
func hide_bar() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	modulate.a = 0.0
	_target_pct = 0.0
	_shown_pct = 0.0
	set_process(false)


## The value the fill is chasing, and the one drawn now (both 0..100).
func get_target_pct() -> float:
	return _target_pct


func get_fill_pct() -> float:
	return _shown_pct


func get_text() -> String:
	return _name_label.text


## Height of name + gap + bar; the Hud uses it to size the control.
func get_total_height() -> float:
	return _name_height + NAME_GAP_PX + BAR_HEIGHT_PX


## The track rectangle in local coordinates (the bar proper, under the name).
func get_bar_rect() -> Rect2:
	return Rect2(0.0, _name_height + NAME_GAP_PX, size.x, BAR_HEIGHT_PX)


func _layout() -> void:
	_name_label.position = Vector2.ZERO
	_name_label.size = Vector2(size.x, _name_height)


func _fade_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		modulate.a = 1.0
		return
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_S)
