extends Node3D
## Procedural farm props. One script, one merged MeshInstance3D per prop (vertex colors, shared material).
## Each <prop_id>.tscn only sets `prop_id`. Origin on the ground at the footprint center, front = -Z.
## The HD model scripts are loaded on demand (GDScript compiles a script when it is loaded, ~15-40 ms each on a
## desktop), so a map only pays for the props it really places. The export filter is "all_resources": the
## scripts are in the package although nothing preloads them.

const MODEL_SCRIPTS: Dictionary = {
	&"farmhouse": "res://assets/models/props/farmhouse_hd.gd",
	&"barn": "res://assets/models/props/barn_hd.gd",
	&"water_tank": "res://assets/models/props/water_tank_hd.gd",
	&"fence_segment": "res://assets/models/props/fence_hd.gd",
	&"gate": "res://assets/models/props/gate_hd.gd",
	&"corn_bait": "res://assets/models/props/corn_bait_hd.gd",
	&"feed_trough": "res://assets/models/props/feed_trough_hd.gd",
}

static var _cache: Dictionary = {}

@export var prop_id: StringName = &""


func _ready() -> void:
	if get_child_count() > 0 or prop_id == &"":
		return
	var key: String = String(prop_id)
	if not _cache.has(key):
		_cache[key] = _build(prop_id)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _cache[key]
	add_child(mi)


static func _build(id: StringName) -> ArrayMesh:
	if not MODEL_SCRIPTS.has(id):
		return ArrayMesh.new()
	var script: GDScript = load(MODEL_SCRIPTS[id] as String) as GDScript
	return script.call(&"get_model")["mesh"]
