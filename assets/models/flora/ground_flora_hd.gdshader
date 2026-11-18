shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
// Shared shader of the HD ground flora: grass tuft, shrub, soy, corn (healthy and eaten) and the termite mound.
// Built for MultiMesh and for the Web (fragment-bound): 1 or 2 fetches of the shared 512 px noise texture per
// fragment, none in loops, no alpha blend, no discard.
//
// Vertex layout (flora_ground_hd.gd):
//   COLOR.rgb  albedo, used as stored (same convention as the other flora)
//   COLOR.a    wind weight 0..1 (0 at the roots, 1 at the free tips); squared in the shader
//   UV.x       flutter weight 0..1 (leaf tips); the termite mound uses UV = (turn 0..1, height in metres)
//   NORMAL     authored (up-biased for grass and crops, inflated for shrubs)
// Per instance: a hash of the instance position (value jitter) and a low-frequency noise of it (drier / greener
// patches across the field), both computed in the vertex stage, so the fragment stays cheap.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.7;
uniform vec2 wind_dir = vec2(0.92, 0.39);
uniform float flutter = 0.0;           // fast leaf-tip flutter (metres)
uniform float inst_tint = 0.14;        // per-instance value jitter
uniform float patch_tint = 0.20;       // per-patch value jitter
uniform vec3 dry_tint = vec3(1.18, 1.0, 0.72);
uniform float dry_amount = 0.35;       // how far the driest patches shift towards dry_tint
uniform float speckle = 0.0;           // leaf speckle contrast (object-space noise)
uniform float speckle_scale = 5.0;
uniform float translucency = 0.0;      // fake light through thin leaves
uniform float height_var = 0.0;       // per-instance height jitter (hash of the instance position)
uniform float mottle = 0.0;            // termite mound: clay mottling and gully streaks

varying float v_inst;
varying float v_patch;
varying vec3 v_op;

void vertex() {
	vec3 ip = MODEL_MATRIX[3].xyz;
	v_inst = fract(sin(dot(ip.xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_patch = textureLod(noise_tex, ip.xz * 0.011 + 0.31, 0.0).r;
	v_op = VERTEX;
	VERTEX.y *= 1.0 + (v_inst - 0.5) * height_var;
	float w = COLOR.a * COLOR.a;
	if (w > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME * wind_speed;
		float gust = sin(t + wp.x * 0.31 + wp.z * 0.23) * 0.7 + sin(t * 2.3 + wp.x * 0.9 + wp.z * 0.6 + v_inst * 6.2832) * 0.3;
		float fl = sin(t * 5.1 + wp.x * 2.3 + wp.z * 1.7 + v_inst * 9.0) * flutter * UV.x;
		vec3 world_off = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust * wind_strength * w + fl);
		// world-space wind pushed back into object space so every instance leans the same way whatever its yaw
		mat3 m = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
		VERTEX += (transpose(m) * world_off) / max(dot(m[0], m[0]), 1e-4);
	}
}

void fragment() {
	vec3 c = COLOR.rgb;
	c *= 1.0 + (v_inst - 0.5) * inst_tint + (v_patch - 0.5) * patch_tint;
	c = mix(c, c * dry_tint, smoothstep(0.50, 0.85, v_patch) * dry_amount);
	if (speckle > 0.0) {
		vec2 s = texture(noise_tex, vec2(v_op.x + v_op.z * 0.55, v_op.z * 0.8 + v_op.y * 0.7) * speckle_scale).rg;
		c *= 1.0 + (s.r * 0.55 + s.g * 0.45 - 0.5) * speckle;
	}
	if (mottle > 0.0) {
		vec2 g = texture(noise_tex, vec2(UV.x * 3.0, UV.y * 0.2)).rg;
		float m = texture(noise_tex, vec2(UV.x * 5.0, UV.y * 1.6)).r;
		c *= 1.0 + (m - 0.5) * mottle;
		c = mix(c, c * vec3(0.62, 0.52, 0.48), smoothstep(0.52, 0.80, g.r) * 0.55 * mottle);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;   // keep the authored (up-biased) normal on both faces
	BACKLIGHT = c * translucency;
}
