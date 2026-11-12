shader_type spatial;
// Vertex-color foliage with a cheap height-weighted wind sway. Works for MultiMesh instances.
render_mode cull_disabled, diffuse_lambert;

uniform float wind_strength = 0.05;
uniform float wind_speed = 1.4;
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float sway_height = 1.0; // height (m) at which the sway reaches wind_strength

void vertex() {
	float h = clamp(VERTEX.y / sway_height, 0.0, 3.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed;
	float gust = sin(t + wp.x * 0.31 + wp.z * 0.23) * 0.7 + sin(t * 2.3 + wp.x * 0.9 + wp.z * 0.6) * 0.3;
	float amt = gust * wind_strength * h * h;
	VERTEX.x += wind_dir.x * amt;
	VERTEX.z += wind_dir.y * amt;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)); // vertex colors are authored as sRGB
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
