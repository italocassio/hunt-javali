shader_type canvas_item;
// Vertical gradient multiplied over white text; the outline keeps its own dark color.
uniform vec4 top_color : source_color = vec4(1.0, 0.86, 0.22, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.46, 0.08, 1.0);
uniform float height = 110.0;
varying float local_y;
void vertex() {
	local_y = VERTEX.y;
}
void fragment() {
	COLOR.rgb *= mix(top_color.rgb, bottom_color.rgb, clamp(local_y / height, 0.0, 1.0));
}
