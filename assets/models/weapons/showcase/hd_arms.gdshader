shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// First-person arms (arms_hd.gd): khaki field-shirt twill, synthetic gloves, a strip of skin at the wrist.
// One material for both arms. Vertex layout (hd_mesh.gd):
//   COLOR.rgb albedo (sRGB)  COLOR.a baked AO  UV = (around, along) in metres on the sleeve tube
//   UV2.x roughness          UV2.y feature (0 shirt, 1 glove, 2 glove cuff, 3 skin, 4 button) + wear/2

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float twill_freq = 520.0;        // diagonal ridges per metre on the shirt
uniform float twill_amount : hint_range(0.0, 0.5) = 0.16;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec3 dust_color : source_color = vec3(0.62, 0.52, 0.38);

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
	float rough = UV2.x;
	float feat = floor(UV2.y + 0.01);
	float shirt = 1.0 - step(0.5, feat);
	float glove = step(0.5, feat) * step(feat, 2.5);
	float skin = step(2.5, feat) * step(feat, 3.5);

	// noise projected along the dominant axis of the object normal (2 fetches)
	vec3 an = abs(normalize(on));
	vec2 pc = an.x > an.y ? (an.x > an.z ? op.zy : op.xy) : (an.y > an.z ? op.zx : op.xy);
	vec2 lo = texture(noise_tex, pc * 5.0 + 0.37).rg;
	vec2 hi = texture(noise_tex, pc * 31.0 + 0.71).rg;

	// shirt: twill ridges (faded out before they alias), mottled dye, dust in the folds
	float t = (UV.x + UV.y * 0.8) * twill_freq;
	float aa = fwidth(t);
	float ridge = (sin(t * 6.2832) * 0.5) * (1.0 - smoothstep(0.25, 0.6, aa));
	base *= 1.0 + shirt * (ridge * twill_amount + (lo.r - 0.5) * 0.30 + (hi.g - 0.5) * 0.12);
	float dust = smoothstep(0.45, 0.85, lo.g + (1.0 - ao) * 0.6) * dust_amount * shirt;
	base = mix(base, srgb_to_linear(dust_color) * 0.85, dust * 0.35);
	rough = mix(rough, 1.0, dust * 0.5);

	// glove: woven synthetic with a little sheen where it is stretched (knuckles), scuffed patches
	base *= 1.0 + glove * ((hi.r - 0.5) * 0.35 + (lo.r - 0.5) * 0.25);
	rough += glove * (hi.g - 0.5) * 0.25;

	// skin: faint warm/cool drift
	base *= 1.0 + skin * (lo.g - 0.5) * 0.18;
	base.r *= 1.0 + skin * (lo.r - 0.5) * 0.10;

	ALBEDO = base * mix(1.0, ao, 0.4);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = mix(0.5, 0.25, shirt);
	AO = ao;
}
