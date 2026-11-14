shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Showcase hard-surface shader: one material for blued steel, anodised scope, polished bolt,
// rubber and painted marks. Everything that differs between parts lives in the vertices:
//   COLOR.rgb albedo (sRGB)  COLOR.a baked AO  UV2.x roughness + 2*metallic  UV2.y feature + wear/2
// Edge wear = chamfer faces tagged with wear, broken up by noise.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 wear_color : source_color = vec3(0.50, 0.50, 0.50);
uniform float wear_amount : hint_range(0.0, 2.0) = 1.25;
uniform float smudge : hint_range(0.0, 1.0) = 0.5;
uniform float tick_count = 24.0;

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	float ao = COLOR.a;
	float metal = step(1.5, UV2.x);
	float rough = UV2.x - 2.0 * metal;
	float feat = floor(UV2.y + 0.01);
	float wear = clamp((UV2.y - feat) * 2.0, 0.0, 1.0);

	// noise projected along the dominant axis of the object normal (2 fetches)
	vec3 an = abs(normalize(on));
	vec2 pc = an.x > an.y ? (an.x > an.z ? op.zy : op.xy) : (an.y > an.z ? op.zx : op.xy);
	vec2 lo = texture(noise_tex, pc * 7.0 + 0.13).rg;
	vec2 hi = texture(noise_tex, pc * 43.0 + 0.61).rg;

	// handling marks: slow roughness and tone drift
	rough += (lo.r - 0.5) * 0.22 * smudge + (hi.g - 0.5) * 0.06 * smudge;
	base *= 1.0 + (lo.g - 0.5) * 0.25 * smudge;

	// worn edges: bare steel on metal, a paler scuff on rubber and paint
	float w = smoothstep(0.40, 0.72, wear * wear_amount * (0.20 + hi.r * 0.70 + lo.r * 0.45));
	vec3 worn = mix(base * 2.2 + 0.012, wear_color, metal);
	base = mix(base, worn, w * 0.8);
	rough = mix(rough, mix(rough, 0.30, metal), w);

	// painted index marks on the dials (UV.x = turn, UV.y = across the band)
	if (feat > 0.5 && feat < 1.5) {
		float t = UV.x * tick_count;
		float major = step(mod(floor(t), 4.0), 0.5);
		float aa = fwidth(t) * 1.2;
		float half_w = mix(0.07, 0.11, major);
		float line = 1.0 - smoothstep(half_w - aa, half_w + aa, abs(fract(t) - 0.5));
		line *= step(UV.y, mix(0.55, 0.92, major)) * step(0.08, UV.y);
		base = mix(base, vec3(0.80, 0.80, 0.76), line);
		metal *= 1.0 - line;
		rough = mix(rough, 0.55, line);
	}

	ALBEDO = base * mix(1.0, ao, 0.5);
	METALLIC = metal;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	// rubber and matte paint: almost no sheen
	SPECULAR = mix(0.5 * mix(1.0, 0.40, smoothstep(0.55, 0.88, rough)), 0.5, metal);
	AO = ao;
}
