shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
// HD dog (dog_hd_model.gd): short sleek coat, nose leather, paws and eyes in ONE material shared by every breed
// (the coat pattern is vertex colour). Cheap on purpose (the Web build is fragment bound): two fetches of the shared
// 512x512 noise, no loops. Same vertex layout as the HD boar (boar_hd_mesh.gd):
//   COLOR.rgb albedo (used as stored, like the other vertex-colour assets)  COLOR.a baked AO
//   UV  x = around (integer tiles, seamless)  y = along the part; the hair runs along UV.y
//       nose: planar over the nose front (-1..1)
//   UV2 x = feature (0 fur, 2 nose, 3 paw, 5 eye) + coarseness / 2   y = around share 0..1 (0 = underside)
//          fur: coarseness 0 = sleek coat, higher = longer hair (tail brush)
//          eye: coarseness 0 = wet globe, > 0.25 = eyelid
//   TANGENT = around direction

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.16;
uniform float bump_amount : hint_range(0.0, 1.0) = 0.22;
uniform float sheen_amount : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	float code = UV2.x;
	float feat = floor(code + 0.01);
	float coarse = (code - feat) * 2.0;
	float fur = 1.0 - step(0.5, feat);
	float nose = step(1.5, feat) * step(feat, 2.5);
	float paw = step(2.5, feat) * step(feat, 3.5);
	float eye = step(4.5, feat);
	float lid = eye * step(0.25, coarse);
	float globe = eye - lid;

	vec3 base = COLOR.rgb;
	float ao = COLOR.a;

	// short hair: fine strands across, long along the hair (UV.x stays an integer multiple: seamless)
	vec2 sp = vec2(UV.x * 4.0, UV.y * (1.1 - coarse * 0.6));
	float strand = texture(noise_tex, sp).g;
	float clump = texture(noise_tex, UV * vec2(1.0, 0.45) + vec2(0.0, 0.37)).r;
	float fade = 1.0 - smoothstep(0.35, 0.9, fwidth(sp.x) * 14.0);
	float h = (strand - 0.5) * 2.0 * fade;
	// the paw is furred like the leg above it
	float coat = fur + paw;
	float hair = coat * (1.0 + coarse * 1.5);
	base *= 1.0 + coat * (h * streak_amount * (1.0 + coarse) + (clump - 0.5) * 0.14);

	// sleek coat: a soft sheen at grazing angles, tinted by the coat itself
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	base = mix(base, base * 1.25 + vec3(0.05), coat * fres * fres * sheen_amount * (0.6 + 0.4 * strand));

	// nose leather: pebbled grain, two comma nostrils and the philtrum groove (planar UV over the front)
	vec2 dq = vec2(abs(UV.x) - 0.42, UV.y + 0.12);
	float nostril = 1.0 - smoothstep(0.16, 0.26, length(dq * vec2(1.0, 1.35)));
	float philtrum = (1.0 - smoothstep(0.03, 0.08, abs(UV.x))) * (1.0 - smoothstep(-0.2, 0.1, UV.y));
	float pebble = texture(noise_tex, UV * 2.3 + vec2(0.13, 0.71)).g;
	base *= 1.0 - nose * (nostril * 0.85 + philtrum * 0.5 - (pebble - 0.5) * 0.5);

	// paw: soft shaded toe grooves on the top front (UV2.y around share: 0.5 = top); claws ride the vertex colour
	float a = UV2.y;
	float toes = 1.0 - smoothstep(0.05, 0.14, UV.y);
	float g = min(abs(a - 0.5), abs(abs(a - 0.5) - 0.085));
	float groove = (1.0 - smoothstep(0.0, 0.03, g)) * toes * smoothstep(0.3, 0.36, a) * (1.0 - smoothstep(0.64, 0.7, a));
	base *= 1.0 - paw * groove * 0.22;

	// eye: fine-grained lid; a sky catchlight fixed in view space keeps the dark globe readable
	base *= 1.0 + lid * (strand - 0.5) * 0.25;
	float glint = globe * smoothstep(0.86, 0.95, dot(NORMAL, normalize(vec3(-0.3, 0.5, 0.8))));
	base = mix(base, vec3(0.85, 0.88, 0.92), glint * 0.9);

	NORMAL = normalize(NORMAL + TANGENT * h * bump_amount * hair);

	ALBEDO = base * mix(1.0, ao, 0.5);
	ROUGHNESS = coat * (0.72 + coarse * 0.15) + nose * 0.32 + globe * 0.06 + lid * 0.5;
	SPECULAR = coat * 0.3 + nose * 0.55 + globe * 0.9 + lid * 0.35;
	EMISSION = vec3(0.30, 0.32, 0.34) * glint;
	RIM = coat * 0.3;
	RIM_TINT = 0.55;
	AO = ao;
}
