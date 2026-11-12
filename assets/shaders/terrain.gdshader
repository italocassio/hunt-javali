shader_type spatial;
// Cerrado terrain. Vertex color: R = crop mask, G = exposed red earth, B = wet margin.
// UV = world XZ / 4. No textures: value noise in the fragment stage.
render_mode diffuse_lambert;

uniform vec3 grass_a : source_color = vec3(0.76, 0.66, 0.33);
uniform vec3 grass_b : source_color = vec3(0.60, 0.55, 0.26);
uniform vec3 grass_green : source_color = vec3(0.46, 0.52, 0.24);
uniform vec3 red_a : source_color = vec3(0.66, 0.29, 0.17);
uniform vec3 red_b : source_color = vec3(0.50, 0.21, 0.13);
uniform vec3 crop_green : source_color = vec3(0.31, 0.52, 0.19);
uniform vec3 crop_soil : source_color = vec3(0.42, 0.21, 0.12);
uniform vec3 wet_color : source_color = vec3(0.30, 0.20, 0.14);

varying float v_up;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_up = normalize((MODEL_NORMAL_MATRIX * NORMAL)).y;
}

void fragment() {
	vec2 w = UV * 4.0; // world meters
	float n1 = vnoise(w * 0.11);
	float n2 = vnoise(w * 0.9);
	float n3 = vnoise(w * 3.1);
	vec3 grass = mix(grass_a, grass_b, n1);
	grass = mix(grass, grass_green, smoothstep(0.55, 0.9, vnoise(w * 0.05 + 7.0)) * 0.6);
	grass *= 0.88 + 0.24 * n2;
	// tussocks
	grass *= 0.94 + 0.12 * n3;
	vec3 red = mix(red_a, red_b, n2) * (0.92 + 0.16 * n3);
	// crop rows along X: stripes across Z every metre
	float row = smoothstep(0.30, 0.55, abs(fract(w.y * 0.5 + 0.25) - 0.5) * 2.0);
	vec3 crop = mix(crop_soil, crop_green, row);
	crop *= 0.9 + 0.2 * n2;
	vec3 col = grass;
	float slope = smoothstep(0.88, 0.7, v_up);
	col = mix(col, red, clamp(COLOR.g + slope * 0.8, 0.0, 1.0));
	col = mix(col, crop, COLOR.r);
	col = mix(col, wet_color * (0.9 + 0.2 * n2), COLOR.b);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
