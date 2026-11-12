class_name BoarHerd
extends RefCounted
## A group of boars (1 = loner). The first member is the leader. Shares alerts and reactions,
## the crop target of the trip and the retreat point of a flight.

const RETREAT_CACHE_S: float = 3.0
const CROP_TARGET_CACHE_S: float = 90.0
const CROP_TARGET_MARGIN_M: float = 4.0
const FALLBACK_FLEE_DISTANCE_M: float = 60.0

var herd_id: int = 0
var members: Array[Boar] = []
var anchor: Vector2 = Vector2.ZERO              # where the herd was born (wander center)
var wander_end_time: float = 0.0                # world elapsed time when wandering ends
var last_detect_time: float = -1000.0           # last time any member saw/heard the player

var crop_target: Vector2 = Vector2.INF
var crop_rect: Rect2 = Rect2()
var _crop_target_time: float = -1000.0
var _retreat_point: Vector2 = Vector2.INF
var _retreat_time: float = -1000.0


func add(boar: Boar) -> void:
	members.append(boar)


func remove(boar: Boar) -> void:
	members.erase(boar)


func alive_count() -> int:
	var n: int = 0
	for b: Boar in members:
		if b.state != Ids.BS_DEAD:
			n += 1
	return n


func get_leader() -> Boar:
	for b: Boar in members:
		if b.state != Ids.BS_DEAD:
			return b
	return null


## One crop target per trip, shared by the herd (members spread around it).
func ensure_crop_target(rects: Array[Rect2], now: float, rng: RandomNumberGenerator) -> void:
	if crop_target.is_finite() and now - _crop_target_time < CROP_TARGET_CACHE_S:
		return
	_crop_target_time = now
	if rects.is_empty():
		crop_target = anchor
		crop_rect = Rect2(anchor - Vector2.ONE, Vector2(2.0, 2.0))
		return
	crop_rect = rects[rng.randi_range(0, rects.size() - 1)].grow(-CROP_TARGET_MARGIN_M)
	crop_target = Vector2(
		rng.randf_range(crop_rect.position.x, crop_rect.end.x),
		rng.randf_range(crop_rect.position.y, crop_rect.end.y))


## The retreat zone farthest from the player among the 2 nearest to the boar. Cached for a few
## seconds so every member of the herd flees to the same place.
func get_retreat(player_pos: Vector2, from: Vector2, zones: PackedVector2Array, now: float) -> Vector2:
	if _retreat_point.is_finite() and now - _retreat_time < RETREAT_CACHE_S:
		return _retreat_point
	_retreat_time = now
	if zones.is_empty():
		_retreat_point = from + Steering.flee(from, player_pos) * FALLBACK_FLEE_DISTANCE_M
		return _retreat_point
	var first: int = -1
	var second: int = -1
	for i: int in zones.size():
		var d: float = from.distance_squared_to(zones[i])
		if first < 0 or d < from.distance_squared_to(zones[first]):
			second = first
			first = i
		elif second < 0 or d < from.distance_squared_to(zones[second]):
			second = i
	var pick: int = first
	if second >= 0 and player_pos.distance_squared_to(zones[second]) > player_pos.distance_squared_to(zones[first]):
		pick = second
	_retreat_point = zones[pick]
	return _retreat_point


func raise_alert(source: Boar, player_pos: Vector2) -> void:
	for b: Boar in members:
		if b != source:
			b.receive_alert(player_pos)
	source.receive_alert(player_pos)


## Reaction shared by the whole herd (hit = a member was wounded).
func raise_reaction(player_pos: Vector2, hit: bool) -> void:
	for b: Boar in members.duplicate():
		b.react(player_pos, hit)
