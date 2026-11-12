class_name AssetLoader
extends RefCounted
## Loads assets that may not exist yet. Returns null (and warns once) so callers use a fallback.

static var _missing: Dictionary = {}


static func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


static func load_resource(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		_report(path)
		return null
	var res: Resource = load(path)
	if res == null:
		_report(path)
	return res


static func instantiate(path: String) -> Node:
	var packed: PackedScene = load_resource(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


static func get_missing() -> PackedStringArray:
	return PackedStringArray(_missing.keys())


static func clear_missing() -> void:
	_missing.clear()


static func _report(path: String) -> void:
	if _missing.has(path):
		return
	_missing[path] = true
	push_warning("AssetLoader: missing asset '%s', using fallback." % path)
