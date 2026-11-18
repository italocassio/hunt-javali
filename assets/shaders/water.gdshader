shader_type spatial;
// Farm pond: murky brown-green water, fake sky reflection by fresnel, soft ripples, muddy rim.
// No SCREEN_TEXTURE, no DEPTH_TEXTURE. Texture reads per pixel: 2 (wave_tex, two scrolling scales).
// The pond mesh is a CylinderMesh disc: its top cap UV is a circle centred at (0.25, 0.75), radius 0.25,
// which gives the distance to the shore for free (rim_t: 0 at the centre, 1 at the shore).
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D wave_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.13, 0.19, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.34, 0.33, 0.18);
uniform vec3 shore_color : source_color = vec3(0.50, 0.42, 0.26);
uniform vec3 sky_horizon : source_color = vec3(1.0, 0.74, 0.52);
uniform vec3 sky_zenith : source_color = vec3(0.50, 0.46, 0.74);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.40);
uniform vec3 sun_dir = vec3(0.435, 0.375, 0.819); // world direction TOWARD the Sun node of mato_grosso_env
uniform float sun_sharpness = 160.0;
uniform float sun_energy = 3.0;
uniform vec2 uv_center = vec2(0.25, 0.75);
uniform float uv_radius = 0.25;
uniform float wave_scale = 7.0;
uniform float wave_strength = 0.55;
uniform float alpha = 0.93;

void fragment() {
	float rim_t = clamp(length(UV - uv_center) / uv_radius, 0.0, 1.0);
	vec2 p = UV * wave_scale;
	float t = TIME * 0.03;
	vec2 w1 = texture(wave_tex, p + vec2(t, t * 0.6)).xy * 2.0 - 1.0;
	vec2 w2 = texture(wave_tex, p * 2.7 - vec2(t * 1.7, t * 1.1)).xy * 2.0 - 1.0;
	vec2 w = (w1 + w2 * 0.6) * wave_strength;
	vec3 nrm = normalize(NORMAL + TANGENT * w.x + BINORMAL * w.y);
	vec3 view = normalize(VIEW);
	float ndv = clamp(dot(nrm, view), 0.0, 1.0);
	float fres = 0.05 + 0.95 * pow(1.0 - ndv, 3.0);
	// fake sky in the reflected direction, in world space
	vec3 refl = (INV_VIEW_MATRIX * vec4(reflect(-view, nrm), 0.0)).xyz;
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.6, refl.y));
	// turbid body: dark green in the middle, muddy near the shore, ripples modulate it
	vec3 body = mix(deep_color, shallow_color, smoothstep(0.35, 0.95, rim_t));
	body *= 0.88 + 0.24 * (w1.x + w2.y);
	float fringe = smoothstep(0.9, 1.0, rim_t + w1.y * 0.03);
	body = mix(body, shore_color, fringe * 0.7);
	float refl_amt = clamp(fres * (1.0 - fringe * 0.7), 0.0, 0.95);
	// the reflection is emitted (independent of the scene lighting), the turbid colour is lit
	ALBEDO = body * (1.0 - refl_amt);
	EMISSION = sky * refl_amt * (0.9 + 0.2 * w1.x) + sun_color * sun_energy * pow(max(dot(refl, normalize(sun_dir)), 0.0), sun_sharpness);
	NORMAL = nrm;
	ALPHA = clamp(mix(alpha, 1.0, refl_amt) - fringe * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.3;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
