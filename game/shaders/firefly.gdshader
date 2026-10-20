shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 萤火：面向相机的小光点，各自缓慢飘动并按自己的节奏明灭。
// INSTANCE_CUSTOM.r 为相位，g 为明灭周期的倍率。
uniform vec3 glow : source_color = vec3(0.86, 1.0, 0.42);
uniform float intensity = 0.0;

varying float v_blink;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	vec3 drift = vec3(sin(TIME * 0.31 + phase), sin(TIME * 0.47 + phase * 1.7) * 0.6, cos(TIME * 0.27 + phase * 0.6)) * 0.9;
	float pulse = sin(TIME * (0.6 + INSTANCE_CUSTOM.g * 0.9) + phase * 3.0);
	v_blink = smoothstep(0.35, 0.95, pulse);
	// 以实例中心为原点，把四边形朝向相机。
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + drift;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * 0.09;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float falloff = 1.0 - smoothstep(0.0, 1.0, length(UV - 0.5) * 2.0);
	ALBEDO = glow * falloff * v_blink * intensity * 2.2;
	ALPHA = falloff * v_blink * intensity;
}
