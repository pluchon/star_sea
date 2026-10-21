shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float phase = 0.0;
uniform vec3 up_direction = vec3(0.0, 1.0, 0.0);
void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	center += up_direction * sin(phase * 0.12 + INSTANCE_CUSTOM.r * 6.28318) * 0.2;
	vec3 world = center + INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}
void fragment() {
	float core = exp(-dot(UV - 0.5, UV - 0.5) * 20.0);
	ALBEDO = vec3(0.9, 0.8, 0.6);
	ALPHA = core * 0.2;
}
