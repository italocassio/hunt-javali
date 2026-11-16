shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Showcase walnut stock: solid (object space) grain, varnish, cut checkering panels with analytic
// normals, ebony fore-end tip and grip cap with white-line spacers. No UVs, no tangents needed.
// Gun space: s = -z forward from the butt plate, y up from the bore axis, x right.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 col_dark : source_color = vec3(0.105, 0.052, 0.028);
uniform vec3 col_mid : source_color = vec3(0.248, 0.138, 0.082);
uniform vec3 col_light : source_color = vec3(0.390, 0.242, 0.142);
uniform vec3 col_ebony : source_color = vec3(0.03, 0.027, 0.027);
uniform vec3 col_spacer : source_color = vec3(0.86, 0.82, 0.72);
uniform float varnish_roughness : hint_range(0.05, 1.0) = 0.23;
uniform float grain_bump = 0.0;
// per-instance grain character (defaults = the walnut look): 1 = wandering figure, 0 = straight and calm
uniform float warp_amount = 1.0;
uniform float ring_freq = 17.0;          // growth layers per unit of the grain coordinate
uniform float ring_amount = 0.50;        // strength of the thin dark ring lines
uniform float smoke_amount = 0.70;       // strength of the dark smoky patches
uniform float tone_amount = 0.85;        // mid to light tone drift
uniform float checker_freq = 560.0;      // grooves per metre
uniform float checker_slope = 0.5;
uniform vec4 grip_panel = vec4(0.2805, -0.0750, 0.0300, 0.0200);   // centre s, centre y, half length, half width
uniform float grip_angle = -1.0;
uniform vec4 fore_panel = vec4(0.655, -0.0245, 0.085, 0.0118);
uniform float fore_angle = -0.035;
uniform float tip_plane = 0.762;         // ebony tip starts where s + 0.55 * y exceeds this
uniform vec3 cap_plane = vec3(0.238, 0.312, -0.1030);   // grip cap: s range and height

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

// long panel with 30 degree pointed ends (fore-end)
float sd_panel(vec2 p, vec2 half_size) {
	vec2 q = abs(p);
	return max(q.y - half_size.y, (q.x - half_size.x) * 0.5 + q.y * 0.866);
}

// rounded rectangle (grip)
float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// x = pyramid height 0..1, yz = downhill direction in the panel plane
vec3 diamonds(vec2 uv, float freq) {
	const float ca = 0.8829;
	const float sa = 0.4695;
	float f1 = fract((uv.y * ca - uv.x * sa) * freq) - 0.5;
	float f2 = fract((uv.y * ca + uv.x * sa) * freq) - 0.5;
	float t1 = abs(f1) * 2.0;
	float t2 = abs(f2) * 2.0;
	vec2 g = t1 < t2 ? sign(f1) * vec2(-sa, ca) : sign(f2) * vec2(sa, ca);
	return vec3(min(t1, t2), g);
}

vec3 bump_from_height(vec3 n, vec3 p, float h, float scale) {
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = (r1 * dhdx + r2 * dhdy) * sign(det) / max(abs(det), 1e-9);
	float len = length(grad) * scale;
	return normalize(n - grad * scale * min(1.0, 0.35 / max(len, 1e-5)));
}

void fragment() {
	float s = -op.z;
	float y = op.y;
	float x = op.x;
	vec3 n = normalize(on);
	float ao = COLOR.a;

	// --- grain: warped growth layers cut by the stock surface ------------------------------------
	float w1 = texture(noise_tex, vec2(s * 0.9 + 0.11, y * 2.2 + 0.3)).r;
	float w2 = texture(noise_tex, vec2(s * 0.9 + 0.47, x * 2.2 + 0.7)).r;
	// domain warp at three scales + a slow drift along the length: growth layers wander, bunch up and
	// fan out instead of running as even parallel stripes in side view
	float wl = texture(noise_tex, vec2(s * 0.33 + 0.6, 0.21)).r;
	float wf = texture(noise_tex, vec2(s * 0.21 + 0.1, 0.63)).r;
	float w3 = texture(noise_tex, vec2(s * 2.6 + 0.3, y * 5.5 + 0.5)).g;
	float d = y * 0.92 + x * 0.38 + s * 0.05 + (w1 + w2 - 1.0) * 0.038 + (w3 - 0.5) * 0.012 + ((wl - 0.5) * 0.10 + (wl - 0.5) * (wf - 0.5) * 0.30 * y) * warp_amount;
	float dens = 1.0 + (0.40 * (wf - 0.5) + 0.20 * (wl - 0.5)) * warp_amount;
	vec2 broad = texture(noise_tex, vec2(d * 5.0 * dens, s * 0.16 + 0.2)).rg;      // slow tone drift, smoky streaks
	vec2 rings = texture(noise_tex, vec2(d * ring_freq * dens + 0.5, s * 0.30)).rg;     // growth layers
	float fibre = texture(noise_tex, vec2(d * 70.0 * dens, s * 2.0 + 0.3)).g;
	float pores = texture(noise_tex, vec2(d * 300.0 + 0.2, s * 13.0)).g;

	// thin dark lines where the stretched noise crosses its mid level = growth ring contours;
	// their strength drifts along the stock so the figure is not uniform
	float ring_a = 1.0 - abs(rings.r * 2.0 - 1.0);
	float ring_b = 1.0 - abs(rings.g * 2.0 - 1.0);
	float figure = smoothstep(0.30, 0.72, texture(noise_tex, vec2(s * 0.7 + 0.9, d * 3.0 + 0.4)).r);
	float ring_line = smoothstep(0.80, 0.97, ring_a) * mix(0.30, 0.85, figure) + smoothstep(0.88, 0.985, ring_b) * mix(0.50, 0.15, figure);
	float tone = smoothstep(0.25, 0.75, broad.r);
	float smoke = smoothstep(0.50, 0.78, rings.r * 0.55 + broad.g * 0.55);
	vec3 c = mix(col_mid, col_light, tone * tone_amount);
	c = mix(c, col_dark, smoke * smoke_amount);
	c = mix(c, col_dark, clamp(ring_line, 0.0, 1.0) * ring_amount);
	c *= 0.86 + 0.28 * fibre;
	float pore = smoothstep(0.62, 0.76, pores);
	c = mix(c, col_dark * 0.7, pore * 0.38);
	float rough = varnish_roughness + pore * 0.10 + ring_line * 0.03;
	float height = -(pore * 0.00003 + ring_line * 0.00001);

	// --- ebony fore-end tip and grip cap, white-line spacers -------------------------------------
	float tip_c = s + 0.55 * y - tip_plane;
	float cap_y = cap_plane.z - (s - 0.28) * 0.06;
	float in_cap_s = step(cap_plane.x, s) * step(s, cap_plane.y);
	float ebony = max(step(0.0025, tip_c), in_cap_s * step(y, cap_y - 0.0022));
	float spacer = max(step(0.0, tip_c) * step(tip_c, 0.0025), in_cap_s * step(y, cap_y) * step(cap_y - 0.0022, y));
	vec3 eb = col_ebony * (0.7 + 0.6 * fibre);
	c = mix(c, eb, ebony);
	rough = mix(rough, 0.20, ebony);
	c = mix(c, col_spacer, spacer);
	rough = mix(rough, 0.45, spacer);
	height *= 1.0 - max(ebony, spacer);

	// --- checkering ------------------------------------------------------------------------------
	vec3 e_s = vec3(0.0, 0.0, -1.0);
	vec3 e_y = vec3(0.0, 1.0, 0.0);
	float side = smoothstep(0.38, 0.50, abs(n.x));
	vec2 gp = vec2(s - grip_panel.x, y - grip_panel.y);
	vec2 g_u = vec2(cos(grip_angle), sin(grip_angle));
	vec2 guv = vec2(dot(gp, g_u), dot(gp, vec2(-g_u.y, g_u.x)));
	float sd_g = sd_round_box(guv, grip_panel.zw, 0.009);
	vec2 fp = vec2(s - fore_panel.x, y - fore_panel.y);
	vec2 f_u = vec2(cos(fore_angle), sin(fore_angle));
	vec2 fuv = vec2(dot(fp, f_u), dot(fp, vec2(-f_u.y, f_u.x)));
	float sd_f = sd_panel(fuv, fore_panel.zw);
	bool use_grip = sd_g < sd_f;
	float sd = use_grip ? sd_g : sd_f;
	vec2 puv = vec2(s, y);
	vec2 pu = vec2(1.0, 0.0);
	// soft mask: checkering relief fades out over 4.5 mm toward the panel edge, no step in colour or normal
	float pm = 1.0 - smoothstep(-0.0045, 0.0004, sd);
	float panel = pm * pm * side * (1.0 - max(ebony, spacer));
	float border = 0.0;
	vec3 nobj = n;
	if (panel > 0.0) {
		vec3 dm = diamonds(puv, checker_freq);
		float cells_per_px = fwidth(puv.x * 0.4695 + puv.y * 0.8829) * checker_freq;
		float fade = 1.0 - smoothstep(0.22, 0.60, cells_per_px);
		vec3 t_u = e_s * pu.x + e_y * pu.y;
		vec3 t_v = e_s * (-pu.y) + e_y * pu.x;
		vec3 g3 = t_u * dm.y + t_v * dm.z;
		g3 -= n * dot(n, g3);
		nobj = normalize(n - g3 * checker_slope * fade * panel);
		// pyramids: facets do the shading, the valleys are only a soft occlusion
		// cut grooves read as thin dark lines, the facets only add a little sparkle-free relief
		c *= mix(1.0, 0.82, panel) * mix(1.0, 0.50 + 0.50 * smoothstep(0.0, 0.32, dm.x), fade * panel);
		rough = mix(rough, 0.72, panel);
		height *= 1.0 - panel;
	}
	c *= 1.0 - 0.6 * border * step(0.5, side);
	rough = mix(rough, 0.6, border);

	vec3 nv = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * nobj, 0.0)).xyz);
	if (grain_bump > 0.0) {
		nv = bump_from_height(nv, VERTEX, height, grain_bump);
	}

	ALBEDO = c * mix(1.0, ao, 0.55);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	AO = ao;
	NORMAL = nv;
}
