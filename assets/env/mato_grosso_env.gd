extends MapEnvironmentBase
## Mato Grosso late afternoon: golden sun, whitish-blue horizon, light dust haze.
## Compatibility-safe: ProceduralSkyMaterial + depth fog + one shadow-capable DirectionalLight3D.

const SUN_COLOR: Color = Color(1.0, 0.80, 0.52)
const FOG_COLOR: Color = Color(0.86, 0.76, 0.62)


func _init() -> void:
	name = "MatoGrossoEnvironment"
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _make_environment()
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_color = SUN_COLOR
	sun.light_energy = 0.95
	sun.shadow_enabled = false
	sun.shadow_blur = 0.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


static func _make_environment() -> Environment:
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.44, 0.86)
	sky_mat.sky_horizon_color = Color(0.90, 0.88, 0.82)
	sky_mat.sky_curve = 0.18
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = Color(0.82, 0.72, 0.60)
	sky_mat.ground_bottom_color = Color(0.40, 0.28, 0.20)
	sky_mat.ground_curve = 0.06
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.12
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.15
	env.fog_sun_scatter = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	return env
