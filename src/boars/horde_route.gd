class_name HordeRoute
extends RefCounted
## Horde route to the barn (docs/plano_horda_nivel2.md section 4.4): the shortest polyline from a boar to its eat
## point that does not cross the open interior of any obstacle rectangle (the corn field, the barn shed). Nodes are
## the corners of every rectangle grown by corner_out_m; Dijkstra over the visibility graph. At most a few
## rectangles, so at most ~14 nodes: computed once per trip, never per frame.

## Touching a rectangle's border does not block a segment.
const EPSILON: float = 1e-4


## Points to follow, without `from`, ending at `to`. obstacles: [{"rect": Rect2, "exit": Vector2}] (exit Vector2.INF
## = none). `from` inside a rectangle with an exit: the exit comes first and the plan goes on from it; without an exit
## that rectangle is ignored. `to` inside a rectangle: that rectangle is ignored. No way through: [to].
static func plan(from: Vector2, to: Vector2, obstacles: Array[Dictionary], corner_out_m: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var start: Vector2 = from
	var rects: Array[Rect2] = []
	for o: Dictionary in obstacles:
		var r: Rect2 = o.get("rect", Rect2()) as Rect2
		if _inside(r, to):
			continue
		if _inside(r, start):
			var exit: Vector2 = o.get("exit", Vector2.INF) as Vector2
			if not exit.is_finite():
				continue
			out.append(exit)
			start = exit
		rects.append(r)
	# Nodes: start, the corners of every grown rectangle not inside another one, to.
	var nodes: PackedVector2Array = PackedVector2Array([start])
	for r: Rect2 in rects:
		var g: Rect2 = r.grow(corner_out_m)
		for c: Vector2 in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
			var keep: bool = true
			for other: Rect2 in rects:
				if _inside(other, c):
					keep = false
					break
			if keep:
				nodes.append(c)
	nodes.append(to)
	var n: int = nodes.size()
	var goal: int = n - 1
	var dist: PackedFloat64Array = PackedFloat64Array()
	var prev: PackedInt32Array = PackedInt32Array()
	var done: PackedByteArray = PackedByteArray()
	dist.resize(n)
	prev.resize(n)
	done.resize(n)
	for i: int in n:
		dist[i] = INF
		prev[i] = -1
		done[i] = 0
	dist[0] = 0.0
	for _k: int in n:
		var u: int = -1
		for i: int in n:
			if done[i] == 0 and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i   # strict "<": equal distances keep the lowest node index
		if u < 0 or u == goal:
			break
		done[u] = 1
		for v: int in n:
			if done[v] != 0 or v == u:
				continue
			var d: float = dist[u] + nodes[u].distance_to(nodes[v])
			if d < dist[v] and not _blocked(nodes[u], nodes[v], rects):
				dist[v] = d
				prev[v] = u
	if dist[goal] == INF:
		out.append(to)
		return out
	var path: PackedVector2Array = PackedVector2Array()
	var at: int = goal
	while at > 0:
		path.append(nodes[at])
		at = prev[at]
	path.reverse()
	out.append_array(path)
	return out


## True if the segment a-b crosses the open interior of any rectangle.
static func _blocked(a: Vector2, b: Vector2, rects: Array[Rect2]) -> bool:
	for r: Rect2 in rects:
		if _crosses(a, b, r):
			return true
	return false


## Liang-Barsky clip of a-b against the rectangle shrunk by EPSILON: any part left inside = crosses the interior.
static func _crosses(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var lo: Vector2 = r.position + Vector2(EPSILON, EPSILON)
	var hi: Vector2 = r.end - Vector2(EPSILON, EPSILON)
	if lo.x >= hi.x or lo.y >= hi.y:
		return false
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	var ps: Array[float] = [-d.x, d.x, -d.y, d.y]
	var qs: Array[float] = [a.x - lo.x, hi.x - a.x, a.y - lo.y, hi.y - a.y]
	for k: int in 4:
		var p: float = ps[k]
		var q: float = qs[k]
		if p == 0.0:
			if q < 0.0:
				return false
			continue
		var t: float = q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return false
	return true


## Strictly inside (borders excluded, EPSILON slack).
static func _inside(r: Rect2, p: Vector2) -> bool:
	return p.x > r.position.x + EPSILON and p.x < r.end.x - EPSILON and p.y > r.position.y + EPSILON and p.y < r.end.y - EPSILON
