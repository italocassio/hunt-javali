shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;
// HD tree bark (trees_hd.gd) for the three trees. One fetch of the shared 512x512 RG noise, bump from screen
// derivatives of that same fetch (no normal map, no loops).
// Vertex layout (trees_hd.gd):
//   COLOR.rgb albedo, used as stored   COLOR.a analytic ambient occlusion
//   UV        x = around (integer tiles, seamless)  y = along the limb (metres)
//   UV2       x = bark kind: 0 corky cerrado bark (thick plates, deep fissures), 1 ipe (long furrows),
//                 2 buriti (smooth, leaf-scar rings)

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float bump = 0.9;
uniform vec3 fissure_color = vec3(0.10, 0.075, 0.06);
uniform float ring_freq = 3.6;          // buriti rings per metre

void fragment() {
	float kind = UV2.x;
	float cork = 1.0 - step(0.5, kind);
	float ipe = step(0.5, kind) * (1.0 - step(1.5, kind));
	float palm = step(1.5, kind);
	// plates stretched along the limb; ipe furrows much longer than the cork plates
	vec2 q = vec2(UV.x * (cork * 0.5 + ipe * 0.5 + palm * 0.25), UV.y * (cork * 0.42 + ipe * 0.16 + palm * 0.3));
	vec2 n = texture(noise_tex, q).rg;
	// ridged noise: fissure lines where the broad field crosses its mid value
	float ridge = abs(n.r - 0.5) * 2.0;
	float fis = 1.0 - smoothstep(0.0, mix(0.16, 0.1, ipe), ridge + (n.g - 0.5) * 0.12);
	float rings = smoothstep(0.78, 0.97, fract(UV.y * ring_freq + n.g * 0.25));
	float h = (1.0 - palm) * (1.0 - fis) * (0.6 + 0.4 * n.g) + palm * (n.g * 0.3 - rings * 0.6);
	vec3 base = COLOR.rgb * (0.86 + 0.28 * n.g);
	base = mix(base, fissure_color, fis * (1.0 - palm) * 0.85);
	base *= 1.0 - palm * rings * 0.35;
	// bump from screen derivatives of the height (Mikkelsen)
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	float fade = 1.0 - smoothstep(18.0, 45.0, -VERTEX.z);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * 0.02 * fade);
	ALBEDO = base * mix(1.0, COLOR.a, 0.4);
	AO = COLOR.a * (1.0 - fis * 0.35 * (1.0 - palm));
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = 0.92 - palm * 0.2;
	SPECULAR = 0.25;
}
