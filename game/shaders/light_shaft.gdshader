shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.2;
uniform float core_gain = 2.2;
uniform float phase = 0.0;
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float vertical = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.90, 1.0, UV.y));
	// 减少铺满大厅的散射，只在光锥中心保留清楚的光束。
	float core = pow(edge, 8.0);
	float alpha = (edge * 0.35 + core * core_gain) * vertical * mix(1.0, 0.45, UV.y) * strength;
	ALBEDO = tint * (0.95 + 0.05 * sin(phase));
	ALPHA = alpha;
}
