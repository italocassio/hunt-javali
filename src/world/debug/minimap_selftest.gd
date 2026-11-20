extends Node
## Self-test of the minimap image (docs/arquitetura.md section 8.4 "Imagem do mapa", task HF5-B).
## Builds Mato Grosso up to build_flora(1.0, true), bakes the image and checks size/format, orientation, determinism,
## independence from the flora density and the time budget. Writes the PNG so a human can look at it.
## Usage: tools/godot.sh --headless --path . res://src/world/debug/minimap_selftest.tscn -- --out=<absolute>.png
## Not part of the game; the qa-tester owns the real tests in tests/.

const MAP_ID: StringName = &"mato_grosso"
const OUT_ARG: String = "--out="
const DEFAULT_OUT: String = "user://minimap_selftest.png"
const BUDGET_PASS_MS: float = 150.0
const BUDGET_TARGET_MS: float = 60.0
const LOW_DENSITY: float = 0.5
const POND_CENTER: Vector2 = Vector2(-70.0, -55.0)
const POND_MIRROR: Vector2 = Vector2(70.0, 55.0)
const SOY_CENTER: Vector2 = Vector2(-35.0, 15.0)
const FARMHOUSE_CENTER: Vector2 = Vector2(10.0, -85.0)

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var cfg: Dictionary = Data.get_game().get("minimap", {}) as Dictionary
	print("cfg from data: %s" % ("yes" if not cfg.is_empty() else "no (script defaults)"))
	var map_a: MapRoot = _build_map(1.0)
	if map_a == null:
		_check("map_loaded", false, "scene %s" % ScenePaths.map_scene(MAP_ID))
		_finish()
		return
	var t0: int = Time.get_ticks_usec()
	map_a.build_minimap(cfg)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("MINIMAP_BAKE_MS=%.1f" % ms)
	var image: Image = map_a.get_minimap_image()
	var colors: Dictionary = MinimapBaker.DEFAULT_COLORS.duplicate()
	colors.merge(cfg.get("colors", {}) as Dictionary, true)
	var prop_colors: Dictionary = MinimapBaker.DEFAULT_PROP_COLORS.duplicate()
	prop_colors.merge(cfg.get("prop_colors", {}) as Dictionary, true)
	var px: int = int(cfg.get("image_px", MinimapBaker.DEFAULT_IMAGE_PX))

	var tex: Texture2D = map_a.get_minimap_texture()
	_check("texture_size", image != null and tex != null and image.get_width() == px and image.get_height() == px
		and image.get_format() == Image.FORMAT_RGB8 and tex.get_width() == px and tex.get_height() == px,
		"image=%s texture=%s px=%d" % [str(image.get_size()) if image != null else "null", str(tex.get_size()) if tex != null else "null", px])
	if image == null:
		_finish()
		return
	var rect: Rect2 = map_a.get_map_rect()
	var pond: String = _hex_at(image, rect, px, POND_CENTER)
	var mirror: String = _hex_at(image, rect, px, POND_MIRROR)
	var soy: String = _hex_at(image, rect, px, SOY_CENTER)
	var house: String = _hex_at(image, rect, px, FARMHOUSE_CENTER)
	var water_hex: String = _hex(colors["water"])
	var soy_ok: bool = soy == _hex(colors["soy"]) or soy == _hex(colors["crop_row"])
	_check("orientation", pond == water_hex and mirror != water_hex and soy_ok and house == _hex(prop_colors["farmhouse"]),
		"pond=%s want %s, mirror=%s, soy=%s, house=%s want %s" % [pond, water_hex, mirror, soy, house, _hex(prop_colors["farmhouse"])])
	var corner: Vector2i = MinimapBaker.world_to_pixel(rect, px, rect.position.x - 50.0, rect.position.y - 50.0)
	var far: Vector2i = MinimapBaker.world_to_pixel(rect, px, rect.end.x + 50.0, rect.end.y + 50.0)
	_check("world_to_pixel_clamped_and_northwest_origin", corner == Vector2i.ZERO and far == Vector2i(px - 1, px - 1)
		and MinimapBaker.world_to_pixel(rect, px, 0.0, rect.position.y + 0.5).y == 0
		and MinimapBaker.world_to_pixel(rect, px, rect.position.x + 0.5, 0.0).x == 0,
		"%s %s" % [str(corner), str(far)])

	var again: Image = MinimapBaker.bake(map_a, cfg)
	_check("deterministic", again != null and again.get_data() == image.get_data())

	var map_b: MapRoot = _build_map(LOW_DENSITY)
	map_b.build_minimap(cfg)
	var other: Image = map_b.get_minimap_image()
	_check("quality_independent", other != null and other.get_data() == image.get_data(),
		"flora %d vs %d tufts" % [map_a.get_flora_positions(&"grass_tuft").size(), map_b.get_flora_positions(&"grass_tuft").size()])

	var canopy: Dictionary = cfg.get("canopy", MinimapBaker.DEFAULT_CANOPY) as Dictionary
	var scaled: Array[String] = []
	for key: Variant in canopy.keys():
		if MapRoot.DENSITY_SCALED_IDS.has(StringName(String(key))):
			scaled.append(String(key))
	_check("canopy_not_density_scaled", scaled.is_empty() and not canopy.is_empty(), "scaled ids in canopy: %s" % str(scaled))

	_check("budget", ms <= BUDGET_PASS_MS, "%.1f ms (pass <= %.0f, target <= %.0f)" % [ms, BUDGET_PASS_MS, BUDGET_TARGET_MS])

	var out: String = DEFAULT_OUT
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(OUT_ARG):
			out = a.substr(OUT_ARG.length())
	var err: Error = image.save_png(out)
	var shown: String = ProjectSettings.globalize_path(out) if out.begins_with("user://") else out
	_check("png_written", err == OK, shown)
	map_a.queue_free()
	map_b.queue_free()
	_finish()


## Mato Grosso assembled the way HuntController does, up to build_flora (steps are synchronous here).
func _build_map(density: float) -> MapRoot:
	var path: String = ScenePaths.map_scene(MAP_ID)
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var map: MapRoot = packed.instantiate() as MapRoot if packed != null else null
	if map == null:
		return null
	add_child(map)
	map.build_heightmap()
	map.build_terrain()
	map.build_props_and_water()
	map.build_flora(density, true)
	return map


func _hex_at(image: Image, rect: Rect2, px: int, world: Vector2) -> String:
	var p: Vector2i = MinimapBaker.world_to_pixel(rect, px, world.x, world.y)
	return image.get_pixelv(p).to_html(false)


func _hex(spec: Variant) -> String:
	return Color.from_string(String(spec), Color.MAGENTA).to_html(false)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _finish() -> void:
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
