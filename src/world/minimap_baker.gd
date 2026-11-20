class_name MinimapBaker
extends RefCounted
## Bakes the top-down image of the whole map (north up) that the HUD minimap draws (docs/arquitetura.md
## section 8.4 "Imagem do mapa"). CPU only, main thread, no SubViewport and no GPU read-back: it works headless.
## Needs the map built up to build_flora. Parameters come from game.minimap (section 9.1); the DEFAULT_* constants
## are the same values, so it also works before the data arrives.

const DEFAULT_IMAGE_PX: int = 256
const DEFAULT_GRID_STRIDE: int = 1
const DEFAULT_AZIMUTH_DEG: float = 315.0
const DEFAULT_ALTITUDE_DEG: float = 40.0
const DEFAULT_HILL_STRENGTH: float = 0.8
const DEFAULT_HILL_MIN: float = 0.65
const DEFAULT_HILL_MAX: float = 1.25
const DEFAULT_TINT_LOW: float = 0.92
const DEFAULT_TINT_HIGH: float = 1.06
const DEFAULT_CROP_ROW_PX: int = 3
const DEFAULT_COLORS: Dictionary = {
	"grass": "#BDA85C", "crop_soil": "#543D26", "road": "#9E4529", "wet": "#5C4D33",
	"water": "#33708C", "water_edge": "#24546B",
	"soy": "#5E9A3A", "corn": "#9DB04A", "crop_row": "#3F6E2A",
	"prop_default": "#9A9A9A",
}
const DEFAULT_PROP_COLORS: Dictionary = {
	"farmhouse": "#C9533D", "barn": "#8C5A3C", "water_tank": "#9AA0A6",
	"feed_trough": "#7A6248", "fence_segment": "#6E5238", "gate": "#6E5238",
}
const DEFAULT_CANOPY: Dictionary = {
	"cerrado_tree": {"radius_m": 2.5, "color": "#3E5F2A"},
	"buriti": {"radius_m": 2.0, "color": "#4D7A34"},
	"ipe": {"radius_m": 2.5, "color": "#C9B42A"},
}
const ROTATED_PROP_SIN: float = 0.7
const CROP_ROW_FIRST_OFFSET_PX: int = 1


## Pixel of a world point. Column 0 = west (rect.position.x), row 0 = north (rect.position.y); outside is clamped.
static func world_to_pixel(map_rect: Rect2, image_px: int, x: float, z: float) -> Vector2i:
	var col: int = floori((x - map_rect.position.x) / map_rect.size.x * float(image_px))
	var row: int = floori((z - map_rect.position.y) / map_rect.size.y * float(image_px))
	return Vector2i(clampi(col, 0, image_px - 1), clampi(row, 0, image_px - 1))


## Returns the RGB8 image, or null if the map has no heightmap yet.
static func bake(map: MapRoot, cfg: Dictionary) -> Image:
	if map == null or map.heightmap == null:
		return null
	var image_px: int = int(cfg.get("image_px", DEFAULT_IMAGE_PX))
	var colors: Dictionary = _merged(DEFAULT_COLORS, cfg.get("colors", {}) as Dictionary)
	var prop_colors: Dictionary = _merged(DEFAULT_PROP_COLORS, cfg.get("prop_colors", {}) as Dictionary)
	var canopy: Dictionary = cfg.get("canopy", DEFAULT_CANOPY) as Dictionary
	var img: Image = _bake_base(map, cfg, colors)
	if img.get_width() != image_px:
		img.resize(image_px, image_px, Image.INTERPOLATE_BILINEAR)
	var map_rect: Rect2 = map.get_map_rect()
	var m_per_px: float = map_rect.size.x / float(image_px)
	_draw_water(img, map, map_rect, image_px, m_per_px, colors)
	_draw_crops(img, map, map_rect, image_px, m_per_px, cfg, colors)
	_draw_props(img, map, map_rect, image_px, m_per_px, colors, prop_colors)
	_draw_canopy(img, map, map_rect, image_px, m_per_px, canopy)
	return img


# --- Step 1: base on the grid --------------------------------------------------------------------

static func _bake_base(map: MapRoot, cfg: Dictionary, colors: Dictionary) -> Image:
	var hm: Heightmap = map.heightmap
	var res: int = hm.resolution
	var stride: int = int(cfg.get("grid_stride", DEFAULT_GRID_STRIDE))
	if stride < 1 or (res - 1) % stride != 0:
		stride = 1
	var n: int = (res - 1) / stride + 1
	var heights: PackedFloat32Array = hm.get_grid_data()
	var mask: PackedColorArray = map.terrain.get_grid_mask() if map.terrain != null else PackedColorArray()
	var has_mask: bool = mask.size() == res * res
	var spacing: float = hm.spacing
	var amplitude: float = maxf(hm.amplitude_m, 0.0001)

	var hill: Dictionary = cfg.get("hillshade", {}) as Dictionary
	var az: float = deg_to_rad(float(hill.get("azimuth_deg", DEFAULT_AZIMUTH_DEG)))
	var alt: float = deg_to_rad(float(hill.get("altitude_deg", DEFAULT_ALTITUDE_DEG)))
	var strength: float = float(hill.get("strength", DEFAULT_HILL_STRENGTH))
	var shade_min: float = float(hill.get("min", DEFAULT_HILL_MIN))
	var shade_max: float = float(hill.get("max", DEFAULT_HILL_MAX))
	var tint_cfg: Dictionary = cfg.get("height_tint", {}) as Dictionary
	var tint_low: float = float(tint_cfg.get("low", DEFAULT_TINT_LOW))
	var tint_high: float = float(tint_cfg.get("high", DEFAULT_TINT_HIGH))
	var sin_alt: float = maxf(sin(alt), 0.0001)
	var lx: float = sin(az) * cos(alt)
	var ly: float = sin(alt)
	var lz: float = -cos(az) * cos(alt)
	var inv_2s: float = 1.0 / (2.0 * spacing)

	var grass: Color = _color(colors["grass"])
	var soil: Color = _color(colors["crop_soil"])
	var road: Color = _color(colors["road"])
	var wet: Color = _color(colors["wet"])

	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 3)
	var o: int = 0
	var last: int = res - 1
	for j: int in n:
		var gj: int = j * stride
		var row: int = gj * res
		var row_n: int = mini(gj + 1, last) * res
		var row_s: int = maxi(gj - 1, 0) * res
		for i: int in n:
			var gi: int = i * stride
			var k: int = row + gi
			var h: float = heights[k]
			var dx: float = (heights[row + mini(gi + 1, last)] - heights[row + maxi(gi - 1, 0)]) * inv_2s
			var dz: float = (heights[row_n + gi] - heights[row_s + gi]) * inv_2s
			var inv_len: float = 1.0 / sqrt(dx * dx + 1.0 + dz * dz)
			var ndotl: float = (-dx * lx + ly - dz * lz) * inv_len
			var shade: float = clampf(lerpf(1.0, ndotl / sin_alt, strength), shade_min, shade_max)
			var factor: float = shade * lerpf(tint_low, tint_high, clampf(h / amplitude, 0.0, 1.0))
			var r: float = grass.r
			var g: float = grass.g
			var b: float = grass.b
			if has_mask:
				var m: Color = mask[k]
				r += (soil.r - r) * m.r
				g += (soil.g - g) * m.r
				b += (soil.b - b) * m.r
				r += (road.r - r) * m.g
				g += (road.g - g) * m.g
				b += (road.b - b) * m.g
				r += (wet.r - r) * m.b
				g += (wet.g - g) * m.b
				b += (wet.b - b) * m.b
			bytes[o] = int(clampf(r * factor, 0.0, 1.0) * 255.0 + 0.5)
			bytes[o + 1] = int(clampf(g * factor, 0.0, 1.0) * 255.0 + 0.5)
			bytes[o + 2] = int(clampf(b * factor, 0.0, 1.0) * 255.0 + 0.5)
			o += 3
	return Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes)


# --- Step 3: sharp layers ------------------------------------------------------------------------

static func _draw_water(img: Image, map: MapRoot, map_rect: Rect2, image_px: int, m_per_px: float, colors: Dictionary) -> void:
	var water: Color = _color(colors["water"])
	var edge: Color = _color(colors["water_edge"])
	for w: WaterBody in map.get_water_bodies():
		var cx: float = w.global_position.x
		var cz: float = w.global_position.z
		var r: float = w.radius_m
		var lo: Vector2i = world_to_pixel(map_rect, image_px, cx - r, cz - r)
		var hi: Vector2i = world_to_pixel(map_rect, image_px, cx + r, cz + r)
		for py: int in range(lo.y, hi.y + 1):
			var wz: float = map_rect.position.y + (float(py) + 0.5) * m_per_px
			for px: int in range(lo.x, hi.x + 1):
				var wx: float = map_rect.position.x + (float(px) + 0.5) * m_per_px
				var d: float = Vector2(wx - cx, wz - cz).length()
				if d <= r:
					img.set_pixel(px, py, edge if d > r - m_per_px else water)


static func _draw_crops(img: Image, map: MapRoot, map_rect: Rect2, image_px: int, m_per_px: float, cfg: Dictionary, colors: Dictionary) -> void:
	var row_px: int = int(cfg.get("crop_row_px", DEFAULT_CROP_ROW_PX))
	var row_color: Color = _color(colors["crop_row"])
	for f: CropField in map.get_crop_fields():
		var rect: Rect2 = f.get_rect()
		var col: Color = _color(colors["corn"] if f.crop == &"corn" else colors["soy"])
		var x0: int = roundi((rect.position.x - map_rect.position.x) / m_per_px)
		var y0: int = roundi((rect.position.y - map_rect.position.y) / m_per_px)
		var x1: int = roundi((rect.end.x - map_rect.position.x) / m_per_px)
		var y1: int = roundi((rect.end.y - map_rect.position.y) / m_per_px)
		var w: int = maxi(x1 - x0, 1)
		var h: int = maxi(y1 - y0, 1)
		img.fill_rect(Rect2i(x0, y0, w, h), col)
		if row_px <= 0:
			continue
		if w >= h:
			# Rows run along the long side (X): one 1 px line every row_px px of Z.
			var y: int = y0 + CROP_ROW_FIRST_OFFSET_PX
			while y < y0 + h:
				img.fill_rect(Rect2i(x0, y, w, 1), row_color)
				y += row_px
		else:
			var x: int = x0 + CROP_ROW_FIRST_OFFSET_PX
			while x < x0 + w:
				img.fill_rect(Rect2i(x, y0, 1, h), row_color)
				x += row_px


static func _draw_props(img: Image, map: MapRoot, map_rect: Rect2, image_px: int, m_per_px: float, colors: Dictionary, prop_colors: Dictionary) -> void:
	var holder: Node = map.get_node_or_null(^"PropSpawns")
	if holder == null:
		return
	var default_color: Color = _color(colors["prop_default"])
	for c: Node in holder.get_children():
		var p: PropSpawn = c as PropSpawn
		if p == null or p.collision_size == Vector3.ZERO:
			continue
		var pos: Vector3 = p.global_position if p.is_inside_tree() else p.position
		var fx: float = p.collision_size.x
		var fz: float = p.collision_size.z
		if absf(sin(p.rotation.y)) > ROTATED_PROP_SIN:
			var tmp: float = fx
			fx = fz
			fz = tmp
		var col: Color = default_color
		var key: String = String(p.prop_id)
		if prop_colors.has(key):
			col = _color(prop_colors[key])
		var x0: int = roundi((pos.x - fx * 0.5 - map_rect.position.x) / m_per_px)
		var y0: int = roundi((pos.z - fz * 0.5 - map_rect.position.y) / m_per_px)
		var x1: int = roundi((pos.x + fx * 0.5 - map_rect.position.x) / m_per_px)
		var y1: int = roundi((pos.z + fz * 0.5 - map_rect.position.y) / m_per_px)
		img.fill_rect(Rect2i(x0, y0, maxi(x1 - x0, 1), maxi(y1 - y0, 1)), col)


static func _draw_canopy(img: Image, map: MapRoot, map_rect: Rect2, image_px: int, m_per_px: float, canopy: Dictionary) -> void:
	for key: Variant in canopy.keys():
		var entry: Dictionary = canopy[key] as Dictionary
		var col: Color = _color(entry.get("color", "#3E5F2A"))
		var r: float = maxf(float(entry.get("radius_m", 2.0)) / m_per_px, 1.0)
		var reach: int = ceili(r)
		var positions: PackedVector2Array = map.get_flora_positions(StringName(String(key)))
		for pos: Vector2 in positions:
			var c: Vector2i = world_to_pixel(map_rect, image_px, pos.x, pos.y)
			for dy: int in range(-reach, reach + 1):
				var span: float = r * r - float(dy * dy)
				if span < 0.0:
					continue
				var half: float = sqrt(span)
				var xa: int = roundi(float(c.x) - half)
				var xb: int = roundi(float(c.x) + half)
				img.fill_rect(Rect2i(xa, c.y + dy, xb - xa + 1, 1), col)


# --- Helpers -------------------------------------------------------------------------------------

static func _merged(defaults: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	for k: Variant in over.keys():
		out[k] = over[k]
	return out


## Parses "#RRGGBB" into a color that survives the RGB8 round trip: Image.set_pixel/fill_rect truncate
## value * 255, so the byte is nudged by half a step to land exactly on the intended byte.
static func _color(spec: Variant) -> Color:
	var parsed: Color = Color.from_string(String(spec), Color(0.6, 0.6, 0.6))
	return Color((roundf(parsed.r * 255.0) + 0.5) / 255.0, (roundf(parsed.g * 255.0) + 0.5) / 255.0,
		(roundf(parsed.b * 255.0) + 0.5) / 255.0, 1.0)
