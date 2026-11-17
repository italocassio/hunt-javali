shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Shared farm-prop material (farmhouse now; barn, water tank, fence, gate, bait, trough later): ONE material,
// the surface kind comes from the feature id in UV2.y. Cheap: 2 to 4 fetches of the shared 512 px noise
// texture per fragment, no loops, no alpha blend.
//
// Vertex layout (hd_mesh.gd):
//   COLOR.rgb albedo (sRGB)   COLOR.a baked AO
//   UV2.x roughness           UV2.y = feature + 0.5 * code (code in 0..1, see below)
//   UV    plaster: (metres along the wall, depth below the roof edge / overhang shade length)
//         tile roof: (metres along the eave, metres down the slope from the eave)
//         glass: (columns, rows) of the window lights
//
// Features:
//   0 plaster (caiado) with the red-earth skirt, grime streaks, peeled patches showing brick
//   1 clay roof tile (capa e canal) with rows, per-tile tone and ribs bumped in the normal
//   2 raw wood (grain axis in code: 0 = Y, 0.4 = X, 0.8 = Z)
//   3 painted wood (same grain codes), chipped paint
//   4 burnt cement / concrete (porch floor, steps), expansion joints
//   5 window glass with painted muntins
//   6 louvered painted shutter
//   7 zinc sheet (gutter, downspout)
//   8 plain fired clay / ceramic (ridge cap, chimney pot, fascia)
//   9 weathered vertical boards, painted (barn walls): board id from the object-space coordinate
//  10 corrugated zinc sheet, rusty (barn roof): UV = (metres along the eave, metres down the slope)
//  11 packed earth floor with straw
//  12 fibre-cement (water tank): vertical grime and algae streaks
//  13 hay (bales)
//  14 corn kernels: code 0 = cob (UV = turn, along: staggered rows), code 0.4 = loose grain (object space cells)

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 dirt_color : source_color = vec3(0.44, 0.25, 0.17);
uniform float dirt_height = 0.55;
uniform float eave_shadow : hint_range(0.0, 1.0) = 0.55;
uniform float tile_pitch = 0.30;         // one capa + one canal
uniform float tile_row = 0.34;           // visible length of a tile along the slope
uniform float tile_bump = 0.016;
// 0 = vertex colour used as stored (same as the flora), 1 = sRGB -> linear (what the hd_* shaders do)
uniform float linearize : hint_range(0.0, 1.0) = 0.0;

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
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

// grain frame: x = along the fibres (metres), y = across
vec2 grain_frame(vec3 p, float code) {
	if (code < 0.1) {
		return vec2(p.y, p.x + p.z * 1.37);
	} else if (code < 0.3) {
		return vec2(p.x, p.y + p.z * 1.37);
	}
	return vec2(p.z, p.x + p.y * 1.37);
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec3 base = mix(col, srgb_to_linear(col), linearize);
	float ao = COLOR.a;
	float rough = UV2.x;
	float spec = 0.5;
	float feat = floor(UV2.y + 0.01);
	float code = UV2.y - feat;
	vec3 on_n = normalize(on);
	vec3 an = abs(on_n);
	vec2 pc = an.x > an.y ? (an.x > an.z ? op.zy : op.xy) : (an.y > an.z ? op.zx : op.xy);
	vec3 nrm = NORMAL;
	float horiz = 1.0 - smoothstep(0.5, 0.9, an.y);   // 1 on walls, 0 on floors and roofs

	if (feat < 0.5) {
		// ---- plaster ----------------------------------------------------------------------------------
		vec2 lo = texture(noise_tex, pc * 0.45 + 0.37).rg;
		vec2 hi = texture(noise_tex, pc * 3.1 + 0.71).rg;
		vec2 st = texture(noise_tex, vec2(pc.x * 0.8 + 0.2, pc.y * 0.10 + 0.55)).rg;
		base *= 1.0 + (lo.r - 0.5) * 0.20 + (hi.g - 0.5) * 0.09;
		// grime streaks run down from the roof edge
		float has_shade = step(0.001, UV.y);   // boxes without wall UVs (chimney) carry UV 0: no roof-edge shade
		float streak = smoothstep(0.50, 0.78, st.r) * exp(-UV.y * 0.55) * has_shade;
		base = mix(base, base * vec3(0.74, 0.69, 0.60), streak * 0.55);
		// peeled plaster showing brick, low on the wall only
		float peel = smoothstep(0.80, 0.83, texture(noise_tex, pc * 0.7 + 0.55).r + (hi.r - 0.5) * 0.05) * (1.0 - smoothstep(0.5, 1.2, op.y)) * horiz;
		if (peel > 0.0) {
			vec2 bp = vec2(pc.x / 0.20, op.y / 0.07);
			bp.x += 0.5 * mod(floor(bp.y), 2.0);
			vec2 bf = fract(bp);
			float mortar = max(step(bf.x, 0.07), step(bf.y, 0.14));
			float tone = textureLod(noise_tex, floor(bp) * vec2(0.61, 1.37), 0.0).g;
			vec3 brick = mix(vec3(0.52, 0.27, 0.19) * (0.8 + 0.4 * tone), vec3(0.62, 0.56, 0.47), mortar);
			base = mix(base, brick, peel);
			rough = mix(rough, 0.95, peel);
		}
		// skirt of red earth splashed up from the ground
		float edge = dirt_height + (lo.g - 0.5) * 0.42 + (hi.r - 0.5) * 0.14;
		float dirt = (1.0 - smoothstep(edge - 0.18, edge + 0.02, op.y)) * horiz;
		vec3 dc = mix(dirt_color, srgb_to_linear(dirt_color), linearize) * (0.70 + 0.55 * hi.g);
		base = mix(base, dc, dirt * 0.92);
		rough = mix(rough, 1.0, dirt);
		// shade under the roof edge
		base *= 1.0 - eave_shadow * exp(-UV.y * 2.4) * has_shade;
		spec = 0.3;
	} else if (feat < 1.5) {
		// ---- roof tile --------------------------------------------------------------------------------
		float cu = UV.x / tile_pitch;
		float cv = UV.y / tile_row;
		vec2 id = floor(vec2(cu * 2.0, cv));
		float fu = fract(cu);
		float fv = fract(cv);
		float aa = fwidth(cu);
		float fade = 1.0 - smoothstep(0.22, 0.55, aa);
		float rib = cos(6.2832 * cu);
		float h1 = textureLod(noise_tex, id * vec2(0.53, 0.97) + 0.13, 0.0).g;
		float h2 = textureLod(noise_tex, id * vec2(0.71, 0.43) + 0.57, 0.0).r;
		vec2 lo = texture(noise_tex, UV * 0.22 + 0.2).rg;
		vec2 st = texture(noise_tex, vec2(UV.x * 0.7 + 0.1, UV.y * 0.06 + 0.3)).rg;
		float tone = 0.80 + 0.40 * h1;
		// a few tiles are old and sun-bleached, a few dark with lichen
		float old = smoothstep(0.76, 0.90, h2);
		float lichen = smoothstep(0.30, 0.10, h2);
		base *= tone * (1.0 + (lo.r - 0.5) * 0.18);
		base = mix(base, vec3(0.50, 0.38, 0.30) * (0.8 + 0.4 * h1), old * 0.55);
		base = mix(base, vec3(0.30, 0.31, 0.24), lichen * 0.45);
		// capa tiles catch more light than the canals
		base *= mix(0.84, 1.08, rib * 0.5 * fade + 0.5);
		// shadow under the lip of the row above
		float gap = smoothstep(0.72, 0.99, fv);
		float lip = 1.0 - smoothstep(0.0, 0.10, fv);
		base *= 1.0 - 0.38 * gap * fade + 0.10 * lip;
		// dust and dark runs down the slope
		base = mix(base, base * vec3(0.72, 0.70, 0.66), smoothstep(0.55, 0.85, st.r) * 0.5);
		rough = 0.80;
		spec = 0.35;
		nrm = bump_from_height(NORMAL, VERTEX, rib * tile_bump * fade, 1.0);
	} else if (feat < 3.5) {
		// ---- wood: raw (2) and painted (3) ----------------------------------------------------------
		vec2 g = grain_frame(op, code);
		vec2 g1 = texture(noise_tex, vec2(g.y * 18.0, g.x * 0.9)).rg;
		vec2 g2 = texture(noise_tex, vec2(g.y * 4.0 + 0.3, g.x * 0.35)).rg;
		float crack = smoothstep(0.88, 0.97, texture(noise_tex, vec2(g.y * 9.0 + 0.5, g.x * 0.2)).r);
		if (feat < 2.5) {
			base *= (0.72 + 0.50 * g1.g) * (0.86 + 0.28 * g2.r);
			base = mix(base, vec3(0.50, 0.46, 0.40), smoothstep(0.55, 0.9, g2.g) * 0.38);   // sun-grey patina
			base *= 1.0 - 0.45 * crack;
			rough = 0.88;
		} else {
			float chip = smoothstep(0.66, 0.76, g1.r * 0.45 + g2.g * 0.65 + crack * 0.2);
			vec3 wood = vec3(0.45, 0.38, 0.30) * (0.7 + 0.5 * g1.g);
			base *= 0.92 + 0.14 * g2.r;
			base = mix(base, wood, chip);
			rough = mix(0.62, 0.9, chip);
		}
		spec = 0.3;
	} else if (feat < 4.5) {
		// ---- burnt cement -------------------------------------------------------------------------
		vec2 lo = texture(noise_tex, pc * 0.8 + 0.1).rg;
		vec2 hi = texture(noise_tex, pc * 4.0 + 0.9).rg;
		base *= 0.90 + 0.22 * lo.r + (hi.g - 0.5) * 0.12;
		float dust = smoothstep(0.55, 0.85, lo.g) * (1.0 - horiz);
		base = mix(base, vec3(0.72, 0.55, 0.42), dust * 0.40);
		if (an.y > 0.7) {
			vec2 j = abs(fract(op.xz / 1.1 + 0.5) - 0.5) * 1.1;
			base *= 1.0 - 0.30 * (1.0 - smoothstep(0.0, 0.012, min(j.x, j.y)));
			rough = 0.5 + 0.3 * lo.g;
		}
		float edge = dirt_height * 0.6 + (lo.g - 0.5) * 0.3;
		float dirt = (1.0 - smoothstep(edge - 0.15, edge + 0.02, op.y)) * horiz;
		vec3 dc = mix(dirt_color, srgb_to_linear(dirt_color), linearize) * (0.7 + 0.5 * hi.g);
		base = mix(base, dc * 0.9, dirt * 0.8);
		rough = mix(rough, 1.0, dirt);
		spec = 0.4;
	} else if (feat < 5.5) {
		// ---- glass with muntins -------------------------------------------------------------------
		vec2 cell = fract(UV);
		float d_edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
		float mull = 1.0 - smoothstep(0.04, 0.08, d_edge);
		vec3 glass = mix(vec3(0.015, 0.025, 0.030), vec3(0.07, 0.10, 0.12), UV.y * 0.15);
		base = mix(glass, base, mull);
		rough = mix(0.06, 0.65, mull);
		spec = mix(0.9, 0.3, mull);
	} else if (feat < 6.5) {
		// ---- louvered shutter ---------------------------------------------------------------------
		vec2 g = vec2(op.y, op.x + op.z * 1.37);
		vec2 g1 = texture(noise_tex, vec2(g.y * 14.0, g.x * 0.6)).rg;
		vec2 g2 = texture(noise_tex, vec2(g.y * 3.0 + 0.3, g.x * 0.3 + 0.2)).rg;
		float sl = fract(op.y / 0.055);
		float slat = mix(0.45, 1.12, smoothstep(0.05, 0.45, sl) * (1.0 - smoothstep(0.80, 1.0, sl) * 0.6));
		float chip = smoothstep(0.68, 0.78, g1.r * 0.45 + g2.g * 0.65);
		vec3 wood = vec3(0.45, 0.38, 0.30) * (0.7 + 0.5 * g1.g);
		base *= (0.90 + 0.18 * g2.r) * slat;
		base = mix(base, wood * slat, chip);
		rough = mix(0.6, 0.9, chip);
		spec = 0.3;
	} else if (feat < 7.5) {
		// ---- zinc ---------------------------------------------------------------------------------
		vec2 st = texture(noise_tex, vec2(pc.x * 6.0 + 0.2, pc.y * 0.5 + 0.1)).rg;
		vec2 lo = texture(noise_tex, pc * 1.4 + 0.6).rg;
		base *= 0.85 + 0.25 * st.g;
		float rust = smoothstep(0.62, 0.82, lo.r + (st.g - 0.5) * 0.3);
		base = mix(base, vec3(0.45, 0.24, 0.13), rust * 0.6);
		rough = mix(0.42, 0.85, rust);
		spec = 0.55;
	} else if (feat < 8.5) {
		// ---- plain fired clay -----------------------------------------------------------------------
		vec2 lo = texture(noise_tex, pc * 0.9 + 0.3).rg;
		vec2 hi = texture(noise_tex, pc * 5.0 + 0.1).rg;
		base *= 0.82 + 0.34 * lo.r + (hi.g - 0.5) * 0.12;
		base = mix(base, vec3(0.26, 0.24, 0.20), smoothstep(0.62, 0.85, lo.g) * 0.35);
		rough = 0.78;
		spec = 0.35;
	} else if (feat < 9.5) {
		// ---- weathered vertical boards ----------------------------------------------------------------
		float bu = pc.x / 0.19;
		float bid = floor(bu);
		float bf = fract(bu);
		float fade = 1.0 - smoothstep(0.25, 0.6, fwidth(bu));
		float t1 = textureLod(noise_tex, vec2(bid * 0.37 + 0.11, 0.5), 0.0).g;
		float t2 = textureLod(noise_tex, vec2(bid * 0.61 + 0.3, 0.25), 0.0).r;
		vec2 g1 = texture(noise_tex, vec2(pc.x * 14.0 + bid * 0.3, pc.y * 0.35)).rg;
		vec2 g2 = texture(noise_tex, vec2(pc.x * 2.5 + 0.2, pc.y * 0.12 + 0.4)).rg;
		float wear = smoothstep(0.42, 0.78, g2.g * 0.55 + t2 * 0.55 + (g1.r - 0.5) * 0.25);
		vec3 grey = vec3(0.44, 0.37, 0.31) * (0.75 + 0.45 * g1.g);
		base *= (0.80 + 0.36 * t1) * (0.92 + 0.16 * g2.r);
		base = mix(base, grey, wear * 0.55);
		float gap = (1.0 - smoothstep(0.0, 0.07, bf)) + smoothstep(0.93, 1.0, bf);
		base *= 1.0 - 0.60 * min(gap, 1.0) * fade;
		// rain streaks and splashed earth
		float streak = smoothstep(0.55, 0.85, texture(noise_tex, vec2(pc.x * 1.7 + 0.5, pc.y * 0.06)).r);
		base *= 1.0 - 0.22 * streak;
		float dedge = 0.45 + (g2.g - 0.5) * 0.35;
		float dirt = (1.0 - smoothstep(dedge - 0.2, dedge, op.y)) * horiz;
		base = mix(base, dirt_color * (0.7 + 0.5 * g1.g), dirt * 0.85);
		rough = 0.92;
		spec = 0.25;
	} else if (feat < 10.5) {
		// ---- corrugated zinc --------------------------------------------------------------------------
		float cu = UV.x / 0.16;
		float fade = 1.0 - smoothstep(0.22, 0.55, fwidth(cu));
		float rib = cos(6.2832 * cu);
		vec2 lo = texture(noise_tex, UV * 0.17 + 0.4).rg;
		vec2 md = texture(noise_tex, vec2(UV.x * 0.8 + 0.3, UV.y * 0.06 + 0.1)).rg;
		vec2 hi = texture(noise_tex, UV * 2.3).rg;
		float sheet = fract(UV.y / 2.2);
		float seam = (1.0 - smoothstep(0.0, 0.05, sheet)) * fade;
		float rust = smoothstep(0.46, 0.70, lo.g * 0.70 + md.r * 0.45 + hi.r * 0.12 + seam * 0.25);
		base *= (0.84 + 0.22 * md.g) * (0.92 + 0.16 * lo.r);
		vec3 rc = vec3(0.50, 0.26, 0.13) * (0.7 + 0.6 * hi.g);
		base = mix(base, rc, rust * 0.88);
		base *= mix(0.80, 1.08, rib * 0.5 * fade + 0.5);
		base *= 1.0 - 0.35 * seam;
		rough = mix(0.58, 0.90, rust);
		spec = mix(0.32, 0.18, rust);
		nrm = bump_from_height(NORMAL, VERTEX, rib * 0.014 * fade, 1.0);
	} else if (feat < 11.5) {
		// ---- packed earth floor -----------------------------------------------------------------------
		vec2 lo = texture(noise_tex, op.xz * 0.35 + 0.2).rg;
		vec2 hi = texture(noise_tex, op.xz * 2.7 + 0.6).rg;
		vec2 tr = texture(noise_tex, vec2(op.x * 0.10, op.z * 1.5)).rg;
		base *= 0.80 + 0.35 * lo.r + (hi.g - 0.5) * 0.20;
		base = mix(base, base * 0.68, smoothstep(0.55, 0.80, tr.r) * 0.6);
		base = mix(base, vec3(0.72, 0.60, 0.32), smoothstep(0.78, 0.9, hi.r) * 0.55);
		rough = 1.0;
		spec = 0.12;
	} else if (feat < 12.5) {
		// ---- fibre-cement -------------------------------------------------------------------------------
		float u = op.x + op.z * 0.73;
		vec2 st = texture(noise_tex, vec2(u * 2.2 + 0.1, op.y * 0.12)).rg;
		vec2 lo = texture(noise_tex, vec2(u * 0.5 + 0.7, op.y * 0.35 + 0.2)).rg;
		vec2 hi = texture(noise_tex, vec2(u * 4.0, op.y * 4.0 + 0.3)).rg;
		base *= 0.86 + 0.24 * lo.r + (hi.g - 0.5) * 0.12;
		float alg = smoothstep(0.58, 0.82, st.r * 0.8 + lo.g * 0.3);
		base = mix(base, vec3(0.24, 0.29, 0.22) * (0.8 + 0.4 * hi.r), alg * 0.5);
		rough = 0.86;
		spec = 0.3;
	} else if (feat < 13.5) {
		// ---- hay ----------------------------------------------------------------------------------------
		vec2 s = texture(noise_tex, vec2((op.y + op.z * 0.9) * 22.0, op.x * 0.5)).rg;
		vec2 lo = texture(noise_tex, vec2(op.x * 0.8 + 0.2, op.z * 0.8 + op.y * 0.8)).rg;
		base *= (0.72 + 0.50 * s.g) * (0.90 + 0.20 * lo.r);
		base = mix(base, base * vec3(0.7, 0.62, 0.45), smoothstep(0.6, 0.9, s.r) * 0.5);
		rough = 1.0;
		spec = 0.1;
	} else {
		// ---- corn kernels -----------------------------------------------------------------------------
		vec2 cp = code < 0.1 ? vec2(UV.x * 10.0, UV.y * 13.0) : (op.xz + vec2(op.y * 0.7, op.y * 0.4)) * 60.0;   // loose grain: top-down, no axis seams
		cp.x += 0.5 * mod(floor(cp.y), 2.0);
		vec2 cid = floor(cp);
		vec2 cf = fract(cp) - 0.5;
		float cfade = 1.0 - smoothstep(0.35, 0.8, max(fwidth(cp.x), fwidth(cp.y)));
		float tone = textureLod(noise_tex, cid * vec2(0.37, 0.71) + 0.2, 0.0).g;
		float tone2 = textureLod(noise_tex, cid * vec2(0.53, 0.29) + 0.6, 0.0).r;
		float kern = 1.0 - smoothstep(0.30, 0.50, length(cf * vec2(1.0, 0.86)));
		vec2 lo = texture(noise_tex, op.xz * 0.6 + op.y * 0.4 + 0.3).rg;
		vec3 kc = base * (0.76 + 0.42 * tone);
		kc = mix(kc, kc * vec3(1.0, 0.72, 0.45), smoothstep(0.78, 0.95, tone2) * 0.8);   // a few orange kernels
		kc = mix(kc, vec3(0.80, 0.70, 0.45), smoothstep(0.86, 0.98, tone) * 0.55);       // and a few pale ones
		kc *= 0.92 + 0.16 * lo.r;
		float gapk = code < 0.1 ? 1.0 : 0.5;
		vec3 gap = mix(kc, base * vec3(0.42, 0.26, 0.12), gapk);
		base = mix(mix(gap, kc, kern), kc * 0.95, 1.0 - cfade);
		rough = mix(0.42, 0.62, 1.0 - kern * cfade);
		spec = 0.45;
		nrm = bump_from_height(NORMAL, VERTEX, kern * cfade * (code < 0.1 ? 0.004 : 0.008), 1.0);
	}

	ALBEDO = base * mix(1.0, ao, 0.5);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	AO = ao;
	NORMAL = nrm;
}
