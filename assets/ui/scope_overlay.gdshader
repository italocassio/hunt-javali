shader_type canvas_item;
// Rifle scope overlay for a full-screen ColorRect. Black outside a circle, thin reticle inside.
// reticle_kind: 0 = duplex (thick outside, thin center), 1 = mil-dot.

uniform float reticle_kind = 0.0;
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.42;
uniform vec4 reticle_color : source_color = vec4(0.02, 0.02, 0.02, 1.0);

void fragment() {
	// Aspect-correct coordinates: 1.0 = half of the shorter screen side.
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * res / (min(res.x, res.y) * 0.5);
	float r = length(p);
	float radius = vignette_radius * 2.0;
	float px = 2.0 / min(res.x, res.y);

	// Soft dark ring, then solid black.
	float edge = smoothstep(radius - 0.02, radius, r);
	float shade = smoothstep(radius * 0.7, radius, r) * 0.45;
	float alpha = clamp(edge + shade * (1.0 - edge), 0.0, 1.0);
	vec3 col = vec3(0.0);

	if (r < radius) {
		float w = max(px * 1.2, 0.0035);
		float ax = abs(p.x);
		float ay = abs(p.y);
		float line = 0.0;
		float thin = 1.0 - smoothstep(w, w + px, min(ax, ay));
		if (reticle_kind < 0.5) {
			// Duplex: thick posts from the edge, thin crosshair near the center.
			float inner = radius * 0.28;
			float outer_w = w * 4.0;
			float thick_h = (1.0 - smoothstep(outer_w, outer_w + px, ay)) * step(inner, ax) * step(ax, radius);
			float thick_v = (1.0 - smoothstep(outer_w, outer_w + px, ax)) * step(inner, ay) * step(ay, radius);
			float thin_h = (1.0 - smoothstep(w, w + px, ay)) * step(ax, inner + px);
			float thin_v = (1.0 - smoothstep(w, w + px, ax)) * step(ay, inner + px);
			line = max(max(thick_h, thick_v), max(thin_h, thin_v));
		} else {
			// Mil-dot: thin cross with dots every 0.1 of the radius.
			float cross_h = (1.0 - smoothstep(w, w + px, ay)) * step(ax, radius * 0.9);
			float cross_v = (1.0 - smoothstep(w, w + px, ax)) * step(ay, radius * 0.9);
			line = max(cross_h, cross_v);
			float dots = 0.0;
			for (int i = 1; i <= 4; i++) {
				float d = float(i) * radius * 0.16;
				float dot_r = w * 2.4;
				dots = max(dots, 1.0 - smoothstep(dot_r, dot_r + px, length(vec2(ax - d, ay))));
				dots = max(dots, 1.0 - smoothstep(dot_r, dot_r + px, length(vec2(ax, ay - d))));
			}
			line = max(line, dots);
		}
		// Center dot.
		line = max(line, 1.0 - smoothstep(w * 1.8, w * 1.8 + px, r));
		col = reticle_color.rgb;
		alpha = max(alpha, line * reticle_color.a);
	}
	COLOR = vec4(col, alpha);
}
