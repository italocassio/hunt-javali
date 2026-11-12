shader_type spatial;
// Farm pond: murky green-blue, fresnel sky tint, soft ripples. No depth texture needed.
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec3 deep_color : source_color = vec3(0.12, 0.30, 0.32);
uniform vec3 shallow_color : source_color = vec3(0.30, 0.48, 0.42);
uniform vec3 sky_color : source_color = vec3(0.78, 0.84, 0.88);
uniform float alpha = 0.86;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz; // keep ripples anchored per instance
	vec2 p = UV * 24.0 + w * 0.0;
	float t = TIME * 0.25;
	float r = vnoise(p + vec2(t, t * 0.6)) * 0.6 + vnoise(p * 2.3 - vec2(t * 1.3, t)) * 0.4;
	vec3 n = normalize(vec3((r - 0.5) * 0.35, 1.0, (vnoise(p * 1.7 + 3.0) - 0.5) * 0.35));
	NORMAL = normalize(mix(NORMAL, n, 0.6));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 base = mix(deep_color, shallow_color, r);
	ALBEDO = mix(base, sky_color, fres * 0.7);
	ALPHA = clamp(alpha + fres * 0.1, 0.0, 1.0);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
