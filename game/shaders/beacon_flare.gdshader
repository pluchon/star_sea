shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 0.0;
void fragment() {
	float core = exp(-dot(UV - 0.5, UV - 0.5) * 40.0);
	ALBEDO = vec3(1.0, 0.64, 0.25) * 3.0;
	ALPHA = core * strength;
}
