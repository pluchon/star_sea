shader_type spatial;
render_mode unshaded, cull_disabled;
instance uniform float awake : instance_index(2) = 0.15;
instance uniform float stroke_progress : instance_index(4) = 0.0;
varying vec2 panel_position;

void vertex() {
	panel_position = VERTEX.xy;
}

void fragment() {
	vec2 relative = panel_position - vec2(0.0, 1.65);
	float angle = mod(atan(-relative.x, relative.y) + 6.283185, 6.283185);
	float stroke = angle / 6.283185 * 0.72;
	if (panel_position.y < 1.24 && abs(panel_position.x) < 0.18) {
		stroke = 0.72 + clamp((1.23 - panel_position.y) / 0.78, 0.0, 1.0) * 0.28;
	}
	float drawn = smoothstep(stroke - 0.015, stroke + 0.015, stroke_progress) * step(0.001, stroke_progress);
	vec3 amber = vec3(0.888, 0.456, 0.102);
	ALBEDO = amber * 0.6;
	EMISSION = amber * mix(0.1, 2.0, max(drawn, awake * 0.1));
}
