shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// HD tree crowns (trees_hd.gd): cerrado tree tufts, ipe flower clusters, buriti fan leaves. One material for all three.
// Cheap on purpose (the Web build is fragment bound): one fetch of the shared 512x512 RG noise, no loops, no alpha.
// Vertex layout (trees_hd.gd):
//   COLOR.rgb albedo, used as stored (like the other flora / props)   COLOR.a analytic ambient occlusion
//   NORMAL    "inflated": blended from the tuft centre and the crown centre, so the crown shades like one volume
//   UV        noise coordinates (metres x 0.9, planar)
//   UV2       x = wind weight (0 rigid .. 1 free tip)   y = translucency (thin leaves / petals)
// Per instance (MultiMesh): a hash of the instance origin shifts brightness, warmth and the wind phase.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wind_strength = 0.07;     // metres at weight 1
uniform float wind_speed = 1.15;
uniform vec2 wind_dir = vec2(0.86, 0.5);
uniform float flutter = 0.018;          // fast small leaf shake (metres)
uniform float leaf_contrast : hint_range(0.0, 1.0) = 0.42;
uniform float leaf_bump : hint_range(0.0, 2.0) = 0.7;
uniform vec3 trans_tint = vec3(0.7, 1.0, 0.5);   // greener: the orange sun alone would turn green leaves yellow
uniform float translucency : hint_range(0.0, 4.0) = 1.1;
uniform float wrap = 0.4;               // diffuse wrap: soft terminator on the round crowns

varying float v_trans;
varying vec3 v_tint;

void vertex() {
	vec3 ip = MODEL_MATRIX[3].xyz;
	float h1 = fract(sin(dot(ip.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(h1 * 17.31 + ip.z * 0.0137);
	// brightness 0.88..1.1, some crowns warmer / drier
	v_tint = vec3(0.88 + 0.22 * h1) * mix(vec3(1.0), vec3(1.03, 1.0, 0.8), h2);
	v_trans = UV2.y;
	float w = UV2.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed + h1 * 6.2832;
	float gust = sin(t + wp.x * 0.21 + wp.z * 0.17) * 0.7 + sin(t * 2.3 + wp.y * 0.9 + wp.x * 0.4) * 0.3;
	float shake = sin(TIME * 7.0 + wp.x * 3.1 + wp.y * 2.3 + wp.z * 2.7);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust * wind_strength * w);
	off += vec3(0.3, 1.0, -0.4) * (shake * flutter * w);
	// world offset -> local (uniform scale + yaw per instance: transpose / scale^2)
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += (transpose(m) * off) / dot(m[0], m[0]);
}

void fragment() {
	vec2 n = texture(noise_tex, UV).rg;
	float clump = n.r;
	float fine = n.g;
	// leaf clusters: gaps between them darker, tips lighter
	float leaf = smoothstep(0.3, 0.72, fine * 0.65 + clump * 0.35);
	vec3 base = COLOR.rgb * v_tint * mix(1.0 - leaf_contrast, 1.0 + leaf_contrast * 0.3, leaf);
	// leaf facets: jitter the normal at leaf scale
	NORMAL = normalize(NORMAL + vec3(fine - 0.5, clump - 0.5, 0.0) * leaf_bump);
	ALBEDO = base * mix(1.0, COLOR.a, 0.35);
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = 0.9;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Fake translucency, sun behind the leaves (the late sun is low). Not shadowed: the faces seen against the sun are exactly the ones the crown shadows itself, and the light
	// that crosses the leaves is the point. Thin edges (grazing view) glow most.
	float back = clamp(dot(VIEW, -LIGHT), 0.0, 1.0);
	back *= back * back;
	float edge = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float thru = (0.3 + 0.7 * clamp(-ndl * 0.5 + 0.5, 0.0, 1.0)) * (0.45 + edge) * back * v_trans * translucency;
	DIFFUSE_LIGHT += (diff * ATTENUATION + thru * trans_tint) * LIGHT_COLOR / PI;
}
