shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(0.0, 0.25, UV.x) * smoothstep(0.0, 0.25, 1.0-UV.x);
}
