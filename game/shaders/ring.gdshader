shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec3 ring_color : source_color = vec3(0.92, 0.86, 0.76);

void fragment() {
	float r = UV.x;
	float bands = sin(r * 70.0) * 0.5 + 0.5;
	float gap = smoothstep(0.42, 0.44, r) * (1.0 - smoothstep(0.50, 0.52, r));
	float edge = smoothstep(0.0, 0.05, r) * (1.0 - smoothstep(0.95, 1.0, r));
	ALBEDO = ring_color;
	ALPHA = edge * (0.35 + bands * 0.35) * (1.0 - gap);
}
