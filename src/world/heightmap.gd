class_name Heightmap
extends RefCounted
## Square height grid centered on the origin. get_height() is the bilinear interpolation of the grid
## (the same surface the terrain mesh and collision are built from). Deterministic for a given seed.

var size_m: float = 256.0
var resolution: int = 129
var amplitude_m: float = 6.0
var terrain_seed: int = 1
var spacing: float = 2.0
var half: float = 128.0

var _h: PackedFloat32Array = PackedFloat32Array()


func _init(p_size_m: float = 256.0, p_resolution: int = 129, p_seed: int = 1, p_amplitude_m: float = 6.0) -> void:
	size_m = p_size_m
	resolution = maxi(p_resolution, 2)
	terrain_seed = p_seed
	amplitude_m = p_amplitude_m
	spacing = size_m / float(resolution - 1)
	half = size_m * 0.5
	_h.resize(resolution * resolution)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = terrain_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	for j: int in resolution:
		var z: float = -half + float(j) * spacing
		for i: int in resolution:
			var x: float = -half + float(i) * spacing
			_h[j * resolution + i] = (noise.get_noise_2d(x, z) * 0.5 + 0.5) * amplitude_m


func get_grid(i: int, j: int) -> float:
	return _h[clampi(j, 0, resolution - 1) * resolution + clampi(i, 0, resolution - 1)]


func set_grid(i: int, j: int, value: float) -> void:
	_h[j * resolution + i] = value


func grid_x(i: int) -> float:
	return -half + float(i) * spacing


func get_height(x: float, z: float) -> float:
	var fx: float = clampf((x + half) / spacing, 0.0, float(resolution) - 1.0001)
	var fz: float = clampf((z + half) / spacing, 0.0, float(resolution) - 1.0001)
	var i: int = int(fx)
	var j: int = int(fz)
	var tx: float = fx - float(i)
	var tz: float = fz - float(j)
	var k: int = j * resolution + i
	var h00: float = _h[k]
	var h10: float = _h[k + 1]
	var h01: float = _h[k + resolution]
	var h11: float = _h[k + resolution + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func get_normal(x: float, z: float) -> Vector3:
	var s: float = 1.0
	var dx: float = get_height(x - s, z) - get_height(x + s, z)
	var dz: float = get_height(x, z - s) - get_height(x, z + s)
	return Vector3(dx, 2.0 * s, dz).normalized()


## Flattens the terrain inside rect to `level` (default: mean height of the rect), blending out over blend_m.
func flatten_rect(rect: Rect2, blend_m: float, level: float = NAN) -> float:
	var lvl: float = level
	if is_nan(lvl):
		lvl = _mean_in_rect(rect)
	var grown: Rect2 = rect.grow(blend_m)
	var i0: int = maxi(int(floor((grown.position.x + half) / spacing)), 0)
	var i1: int = mini(int(ceil((grown.end.x + half) / spacing)), resolution - 1)
	var j0: int = maxi(int(floor((grown.position.y + half) / spacing)), 0)
	var j1: int = mini(int(ceil((grown.end.y + half) / spacing)), resolution - 1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = Vector2(grid_x(i), grid_x(j))
			var dx: float = maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
			var dz: float = maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
			var d: float = sqrt(dx * dx + dz * dz)
			var w: float = 1.0 - smoothstep(0.0, maxf(blend_m, 0.01), d)
			var k: int = j * resolution + i
			_h[k] = lerpf(_h[k], lvl, w)
	return lvl


func flatten_circle(center: Vector2, radius: float, blend_m: float, level: float = NAN) -> float:
	var lvl: float = level
	if is_nan(lvl):
		lvl = get_height(center.x, center.y)
	var reach: float = radius + blend_m
	var i0: int = maxi(int(floor((center.x - reach + half) / spacing)), 0)
	var i1: int = mini(int(ceil((center.x + reach + half) / spacing)), resolution - 1)
	var j0: int = maxi(int(floor((center.y - reach + half) / spacing)), 0)
	var j1: int = mini(int(ceil((center.y + reach + half) / spacing)), resolution - 1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var d: float = Vector2(grid_x(i), grid_x(j)).distance_to(center)
			var w: float = 1.0 - smoothstep(radius, reach, d)
			var k: int = j * resolution + i
			_h[k] = lerpf(_h[k], lvl, w)
	return lvl


## Digs a bowl (pond). Returns the rim level; the water surface goes slightly below it.
func dig_bowl(center: Vector2, radius: float, depth_m: float, blend_m: float) -> float:
	var rim: float = get_height(center.x, center.y)
	var reach: float = radius + blend_m
	var i0: int = maxi(int(floor((center.x - reach + half) / spacing)), 0)
	var i1: int = mini(int(ceil((center.x + reach + half) / spacing)), resolution - 1)
	var j0: int = maxi(int(floor((center.y - reach + half) / spacing)), 0)
	var j1: int = mini(int(ceil((center.y + reach + half) / spacing)), resolution - 1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var d: float = Vector2(grid_x(i), grid_x(j)).distance_to(center)
			var k: int = j * resolution + i
			if d <= radius:
				var t: float = d / radius
				_h[k] = rim - depth_m * (1.0 - t * t)
			else:
				var w: float = 1.0 - smoothstep(0.0, blend_m, d - radius)
				_h[k] = lerpf(_h[k], rim, w)
	return rim


func _mean_in_rect(rect: Rect2) -> float:
	var sum: float = 0.0
	var n: int = 0
	var x: float = rect.position.x
	while x <= rect.end.x:
		var z: float = rect.position.y
		while z <= rect.end.y:
			sum += get_height(x, z)
			n += 1
			z += spacing
		x += spacing
	return sum / float(maxi(n, 1))
