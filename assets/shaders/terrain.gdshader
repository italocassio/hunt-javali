shader_type spatial;
// Cerrado terrain. Vertex color: R = crop mask, G = exposed red earth, B = wet margin.
// UV = world XZ / 4. Normals supplied by the mesh.
// Texture reads per pixel: 3, all from the same 256x256 seamless noise (noise_tex):
//   1. macro  (period ~47 m)  : large patches of dry / green grass, bare soil, dust, crop vigour
//   2. mid    (period ~12 m, rotated 37 deg) : breaks the macro, tussock clumps, rut meanders, mask edges
//   3. detail (period ~1.8 m, rotated -23 deg): soil grain, straw, pebbles
// Everything else (furrows, ruts) is ALU. No triplanar, no loops.
render_mode diffuse_lambert;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 grass_a : source_color = vec3(0.74, 0.63, 0.32);
uniform vec3 grass_b : source_color = vec3(0.58, 0.52, 0.25);
uniform vec3 grass_dry : source_color = vec3(0.82, 0.72, 0.42);
uniform vec3 grass_green : source_color = vec3(0.44, 0.50, 0.23);
uniform vec3 red_a : source_color = vec3(0.54, 0.27, 0.17);
uniform vec3 red_b : source_color = vec3(0.42, 0.21, 0.14);
uniform vec3 red_dust : source_color = vec3(0.66, 0.44, 0.30);
uniform vec3 crop_green : source_color = vec3(0.30, 0.50, 0.18);
uniform vec3 crop_soil : source_color = vec3(0.40, 0.21, 0.13);
uniform vec3 wet_color : source_color = vec3(0.24, 0.16, 0.11);
uniform float furrow_period_m = 0.9;
uniform float detail_fade_start = 35.0;
uniform float detail_fade_end = 80.0;

varying float v_up;

void vertex() {
	v_up = normalize((MODEL_NORMAL_MATRIX * NORMAL)).y;
}

void fragment() {
	vec2 w = UV * 4.0; // world meters
	float nm = texture(noise_tex, w * 0.0213 + vec2(0.31, 0.77)).r;
	float nl = texture(noise_tex, vec2(0.80 * w.x - 0.60 * w.y, 0.60 * w.x + 0.80 * w.y) * 0.083).r;
	float nd = texture(noise_tex, vec2(0.92 * w.x + 0.39 * w.y, -0.39 * w.x + 0.92 * w.y) * 0.55).r;
	float far_t = smoothstep(detail_fade_start, detail_fade_end, length(VERTEX));
	float dn = (nd - 0.5) * (1.0 - far_t * 0.7);
	// fine grain: one hash per 7 cm cell, only near the camera (fades before it can shimmer)
	vec2 gc = floor(w * 14.0);
	float gr = fract(sin(dot(gc, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	gr *= 1.0 - smoothstep(6.0, 18.0, length(VERTEX));

	// grass: dry/bleached and green patches at macro scale, tussock clumps at mid scale
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.65, nl));
	grass = mix(grass, grass_dry, smoothstep(0.52, 0.30, nm) * 0.65);
	grass = mix(grass, grass_green, smoothstep(0.55, 0.72, nm) * 0.65);
	grass *= 0.90 + 0.32 * (nl - 0.5);
	grass *= 1.0 + 0.55 * dn;

	// red earth: dust, grain, meandering rut grooves (contours of the mid noise)
	vec3 red = mix(red_a, red_b, smoothstep(0.35, 0.65, nl));
	red = mix(red, red_dust, smoothstep(0.50, 0.30, nm) * 0.5);
	float rut = 1.0 - smoothstep(0.0, 0.10, abs(nl - 0.52));
	float rut2 = 1.0 - smoothstep(0.0, 0.08, abs(nl - 0.34));
	red *= 1.0 - 0.17 * (rut + rut2) * (1.0 - far_t);
	red *= 1.0 + 0.7 * dn;
	red = mix(red, red_dust, clamp((dn - 0.28) * 3.0, 0.0, 0.5)); // pebbles / dry crust

	// crop: ridges and furrows along X, seedlings on the ridge crest, patchy vigour
	float ph = fract(w.y / furrow_period_m);
	float ridge = 0.5 + 0.5 * cos(ph * 6.2831853);
	float amp = 1.0 - far_t;
	float vigor = clamp(0.55 + (nm - 0.5) * 1.6, 0.0, 1.0);
	float sprout = smoothstep(0.55 - 0.25 * vigor, 0.95, ridge) * (0.35 + 0.65 * vigor);
	sprout = mix(0.45 * vigor, sprout, amp);
	vec3 soil = crop_soil * (0.80 + 0.30 * ridge * amp + 0.10 * ridge * (1.0 - amp)) * (1.0 + 0.6 * dn);
	vec3 crop = mix(soil, crop_green * (0.85 + 0.3 * nl), sprout);

	// masks with a noise-broken edge: wide vertex-colour gradients turn into ragged borders
	float m_red = smoothstep(0.35, 0.65, COLOR.g + (nl - 0.5) * 0.55);
	float slope = smoothstep(0.88, 0.7, v_up);
	m_red = clamp(m_red + slope * 0.8, 0.0, 1.0);
	float m_crop = smoothstep(0.35, 0.65, COLOR.r + dn * 0.5);
	float m_wet = smoothstep(0.15, 0.6, COLOR.b + (nl - 0.5) * 0.3);

	vec3 col = mix(grass, red, m_red);
	col = mix(col, crop, m_crop);
	col = mix(col, wet_color * (0.85 + 0.5 * nl) * (1.0 + 0.5 * dn), m_wet);
	col *= 1.0 + 0.08 * gr;
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.55, m_wet);
	SPECULAR = mix(0.0, 0.5, m_wet);
}
