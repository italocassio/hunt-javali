shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Showcase coated lens: opaque mirror tinted by a thin-film style gradient (violet facing the
// viewer, green-amber at grazing angles), dark in the middle where one would look into the tube.

uniform vec3 coat_center : source_color = vec3(0.16, 0.07, 0.42);
uniform vec3 coat_mid : source_color = vec3(0.10, 0.30, 0.55);
uniform vec3 coat_rim : source_color = vec3(0.75, 0.55, 0.20);
uniform float depth_darkening : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float f = 1.0 - ndv;
	vec3 coat = mix(coat_center, coat_mid, smoothstep(0.0, 0.45, f));
	coat = mix(coat, coat_rim, smoothstep(0.45, 0.95, f));
	// UV.y runs 0 at the centre to 1 at the rim of the lens
	float rim = smoothstep(0.2, 1.0, UV.y);
	ALBEDO = coat * mix(1.0 - depth_darkening, 1.0, max(rim, f));
	METALLIC = 1.0;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	EMISSION = coat * 0.07;
}
