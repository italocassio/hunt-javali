shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
// HD boar (boar_hd_model.gd): coarse bristle coat, snout disc, hooves, tusks and eyes in one material per type.
// Cheap on purpose (the Web build is fragment bound): two fetches of the shared 512x512 noise, no loops.
// Vertex layout (boar_hd_mesh.gd):
//   COLOR.rgb albedo  COLOR.a baked AO
// Colours (vertex and uniforms) are used as they are, like the StandardMaterial3D vertex-colour materials of the other
// assets (MeshKit): in this Compatibility build those render the stored value without an sRGB decode, so the palette
// stays comparable with the rest of the map.
//   UV  x = around (integer tiles, seamless)  y = along the part; the hair runs along UV.y
//   UV2 x = feature (0 fur, 1 mane, 2 skin, 3 hoof, 4 tusk, 5 eye) + coarseness / 2   y = around share (stripes)
//          eye: coarseness 0 = wet globe, > 0.25 = bare eyelid
//   TANGENT = around direction

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 tip_color = vec3(0.55, 0.48, 0.40);   // grizzled bristle tips
uniform float tip_amount : hint_range(0.0, 1.0) = 0.5;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.55;
uniform float bump_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec3 stripe_color = vec3(0.85, 0.72, 0.52);  // piglet stripes
uniform float stripe_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float code = UV2.x;
	float feat = floor(code + 0.01);
	float coarse = (code - feat) * 2.0;
	float fur = 1.0 - step(1.5, feat);
	float mane = step(0.5, feat) * fur;
	float skin = step(1.5, feat) * step(feat, 2.5);
	float hoof = step(2.5, feat) * step(feat, 3.5);
	float tusk = step(3.5, feat) * step(feat, 4.5);
	float eye = step(4.5, feat);
	float lid = eye * step(0.25, coarse);
	float globe = eye - lid;

	vec3 base = COLOR.rgb;
	float ao = COLOR.a;

	// bristles: fine across the hair, stretched along it (UV.x must stay an integer multiple: seamless)
	vec2 sp = vec2(UV.x * 3.0, UV.y * (0.55 - mane * 0.3));
	float strand = texture(noise_tex, sp).g;
	float clump = texture(noise_tex, UV * vec2(1.0, 0.35) + vec2(0.0, 0.37)).r;
	float fade = 1.0 - smoothstep(0.35, 0.9, fwidth(sp.x) * 14.0);
	float h = (strand - 0.5) * 2.0 * fade;
	float hair = fur * (1.0 + coarse);

	// coat: dark roots, streaks, clumps; grizzled tips that catch the light at grazing angles
	base *= 1.0 + fur * (h * streak_amount + (clump - 0.5) * 0.5);
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float tips = smoothstep(0.52, 0.78, mix(0.5, strand, fade)) * (0.35 + 0.65 * fres * fres);
	base = mix(base, tip_color, clamp(fur * tips * tip_amount * (0.6 + coarse), 0.0, 1.0));

	// piglet: pale longitudinal stripes on the flanks and back
	float a = UV2.y;
	float band = smoothstep(0.2, 0.3, a) * (1.0 - smoothstep(0.7, 0.8, a));
	float stripe = smoothstep(0.35, 0.85, sin(a * 6.2832 * 7.0 + 1.3)) * band * stripe_amount * fur * (0.75 + 0.5 * clump);
	base = mix(base, stripe_color, stripe);

	// snout disc: nostrils, moist fine grain
	vec2 dq = vec2(abs(UV.x) - 0.36, UV.y + 0.05);
	float nostril = 1.0 - smoothstep(0.15, 0.24, length(dq * vec2(1.0, 0.8)));
	base *= 1.0 - skin * (nostril * 0.85 - (strand - 0.5) * 0.25);

	// hoof: vertical keratin striation; tusk: growth bands
	base *= 1.0 + hoof * (strand - 0.5) * 0.6 + tusk * (clump - 0.5) * 0.25;

	// eye: fine-grained eyelid skin; a sky catchlight fixed in view space (upper front) keeps the dark globe readable
	// in the shade and against the sun
	base *= 1.0 + lid * (strand - 0.5) * 0.3;
	float glint = globe * smoothstep(0.84, 0.94, dot(NORMAL, normalize(vec3(-0.3, 0.5, 0.8))));
	base = mix(base, vec3(0.80, 0.84, 0.88), glint * 0.85);

	NORMAL = normalize(NORMAL + TANGENT * h * bump_amount * hair);

	ALBEDO = base * mix(1.0, ao, 0.5);
	ROUGHNESS = fur * (0.88 - mane * 0.05) + skin * 0.38 + hoof * 0.5 + tusk * 0.32 + globe * 0.08 + lid * 0.55;
	SPECULAR = fur * 0.14 + skin * 0.5 + hoof * 0.45 + tusk * 0.5 + globe * 0.9 + lid * 0.3;
	EMISSION = vec3(0.30, 0.32, 0.34) * glint;
	RIM = fur * 0.25;
	RIM_TINT = 0.6;
	AO = ao;
}
