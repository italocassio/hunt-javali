class_name ObstacleGrid
extends RefCounted
## Circular obstacles in XZ for steering (boars and dogs have no physics bodies).
## Bucketed by cell so queries touch only a few circles. No per-query allocation.

const CELL_M: float = 8.0
const KEY_STRIDE: int = 1024
const KEY_OFFSET: int = 512

var _cx: PackedFloat32Array = PackedFloat32Array()
var _cz: PackedFloat32Array = PackedFloat32Array()
var _cr: PackedFloat32Array = PackedFloat32Array()
var _cells: Dictionary = {}   # int key -> PackedInt32Array of circle indices


func get_count() -> int:
	return _cr.size()


func add_circle(x: float, z: float, radius: float) -> void:
	if radius <= 0.0:
		return
	var idx: int = _cr.size()
	_cx.append(x)
	_cz.append(z)
	_cr.append(radius)
	var c0: int = _cell(x - radius)
	var c1: int = _cell(x + radius)
	var r0: int = _cell(z - radius)
	var r1: int = _cell(z + radius)
	for cz: int in range(r0, r1 + 1):
		for cx: int in range(c0, c1 + 1):
			var key: int = cz * KEY_STRIDE + cx + KEY_OFFSET
			# Read, append, write back: a packed array read from a Dictionary through a cast is a copy.
			var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
			list.append(idx)
			_cells[key] = list


## Lateral push away from circles ahead of the agent. Zero when the way is clear.
func avoidance(pos: Vector2, forward: Vector2, lookahead_m: float, agent_r: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var side_axis: Vector2 = Vector2(-forward.y, forward.x)
	var c0: int = _cell(pos.x - lookahead_m)
	var c1: int = _cell(pos.x + lookahead_m)
	var r0: int = _cell(pos.y - lookahead_m)
	var r1: int = _cell(pos.y + lookahead_m)
	for cz: int in range(r0, r1 + 1):
		for cx: int in range(c0, c1 + 1):
			var list: Variant = _cells.get(cz * KEY_STRIDE + cx + KEY_OFFSET)
			if list == null:
				continue
			for idx: int in (list as PackedInt32Array):
				var to: Vector2 = Vector2(_cx[idx] - pos.x, _cz[idx] - pos.y)
				var ahead: float = to.dot(forward)
				if ahead <= 0.0 or ahead > lookahead_m + _cr[idx]:
					continue
				var lateral: float = to.dot(side_axis)
				var clearance: float = _cr[idx] + agent_r
				if absf(lateral) >= clearance + 0.5:
					continue
				var strength: float = 1.0 - clampf(ahead / (lookahead_m + _cr[idx]), 0.0, 1.0)
				var side: float = -1.0 if lateral >= 0.0 else 1.0
				push += side_axis * side * (0.5 + strength * 1.5)
	return push


## Moves pos out of any circle it overlaps. Returns the corrected position.
func resolve(pos: Vector2, agent_r: float) -> Vector2:
	var out: Vector2 = pos
	var key: int = _cell(out.y) * KEY_STRIDE + _cell(out.x) + KEY_OFFSET
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var list: Variant = _cells.get(key + dz * KEY_STRIDE + dx)
			if list == null:
				continue
			for idx: int in (list as PackedInt32Array):
				var d: Vector2 = Vector2(out.x - _cx[idx], out.y - _cz[idx])
				var min_d: float = _cr[idx] + agent_r
				var len_sq: float = d.length_squared()
				if len_sq < min_d * min_d:
					var dist: float = sqrt(len_sq)
					if dist < 0.001:
						d = Vector2(1.0, 0.0)
						dist = 1.0
					out = Vector2(_cx[idx], _cz[idx]) + d / dist * min_d
	return out


func is_free(pos: Vector2, agent_r: float) -> bool:
	var key: int = _cell(pos.y) * KEY_STRIDE + _cell(pos.x) + KEY_OFFSET
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var list: Variant = _cells.get(key + dz * KEY_STRIDE + dx)
			if list == null:
				continue
			for idx: int in (list as PackedInt32Array):
				var min_d: float = _cr[idx] + agent_r
				if Vector2(pos.x - _cx[idx], pos.y - _cz[idx]).length_squared() < min_d * min_d:
					return false
	return true


func _cell(v: float) -> int:
	return int(floor(v / CELL_M))
