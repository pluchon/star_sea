shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 0.6;
void fragment() {
	ALBEDO = vec3(1.0, 0.91, 0.70) * 2.0;
	ALPHA = exp(-dot(UV - 0.5, UV - 0.5) * 40.0) * strength;
}
