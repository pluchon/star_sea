shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float flame_time = 0.0;
uniform float strength = 1.0;
void vertex() {
	VERTEX.x += sin(flame_time * 3.0 + VERTEX.y * 4.0) * 0.12 * (1.0 - UV.y);
}
void fragment() {
	float edge = abs(UV.x - 0.5) * 2.0;
	float height = 1.0 - UV.y;
	float waviness = sin(height * 15.0 - flame_time * 5.0) * 0.1;
	float body = 1.0 - smoothstep((1.0 - height) * 0.6, (1.0 - height) + 0.1, edge + waviness);
	ALBEDO = vec3(1.0, 0.50, 0.12);
	EMISSION = vec3(1.0, 0.42, 0.06) * strength * 2.0;
	ALPHA = body * smoothstep(0.0, 0.1, height) * 0.85;
}
