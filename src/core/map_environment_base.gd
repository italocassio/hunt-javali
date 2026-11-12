class_name MapEnvironmentBase
extends Node3D
## Sky, fog and sun of a map. Required children: WorldEnvironment, Sun (DirectionalLight3D).


func apply_quality(quality: StringName) -> void:
	var sun: DirectionalLight3D = get_node_or_null(^"Sun") as DirectionalLight3D
	if sun == null:
		return
	var presets: Dictionary = Data.get_game().get("quality_presets", {})
	var preset: Dictionary = presets.get(String(quality), {})
	sun.shadow_enabled = bool(preset.get("shadows", false))
	sun.directional_shadow_max_distance = float(preset.get("shadow_distance_m", 30.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL


static func create_fallback() -> MapEnvironmentBase:
	var root: MapEnvironmentBase = MapEnvironmentBase.new()
	root.name = "MapEnvironmentFallback"
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = env
	root.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	root.add_child(sun)
	return root
