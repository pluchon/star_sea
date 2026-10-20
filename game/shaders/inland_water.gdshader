shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 河面与湖面：卡通色块，浅处透出河床，深处偏蓝绿；河面有顺流的亮纹，岸边有一圈浅色水花。
// 和海面一样手动计算昼夜明暗，之后由大气球壳统一做远景淡化。

global uniform vec3 sun_dir;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform bool flowing = true;
uniform vec3 shallow : source_color = vec3(0.42, 0.74, 0.70);
uniform vec3 deep : source_color = vec3(0.13, 0.34, 0.42);

varying vec3 v_world;
varying vec3 v_up;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float water_depth = max(length(view.xyz) - length(VERTEX), 0.0);
	float t = smoothstep(0.0, flowing ? 2.5 : 6.0, water_depth);
	vec3 water = mix(shallow, deep, t);
	float distance_to_eye = length(VERTEX);
	float near = 1.0 - smoothstep(25.0, 140.0, distance_to_eye);
	float streak = 0.0;
	float foam = 0.0;
	if (flowing) {
		// 河面亮纹顺着河道方向移动，中间流得快、两边慢。
		float across = UV.x;
		float speed = 1.6 * (1.0 - across * across * 0.6);
		float phase = UV.y * 0.32 - TIME * speed + sin(across * 3.1 + UV.y * 0.05) * 1.4;
		streak = smoothstep(0.82, 0.97, sin(phase) * 0.5 + 0.5) * (1.0 - abs(across)) * near;
		foam = smoothstep(0.78, 0.98, abs(across)) * (0.55 + 0.45 * sin(UV.y * 0.9 - TIME * 1.3));
	} else {
		// 湖面只有缓慢的细小波纹，岸边浅水处有一圈水花。
		float ripple = sin(dot(UV, vec2(0.21, 0.13)) + TIME * 0.6) * sin(dot(UV, vec2(-0.09, 0.27)) - TIME * 0.4);
		streak = smoothstep(0.55, 0.9, ripple) * near * 0.6;
		foam = (1.0 - smoothstep(0.0, 0.5, water_depth)) * step(0.001, water_depth);
	}
	vec3 eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float fresnel = pow(1.0 - max(dot(v_up, eye), 0.0), 4.0);
	float sun_height = dot(v_up, sun_dir);
	float day = smoothstep(-0.10, 0.18, sun_height);
	vec3 sky = mix(vec3(0.012, 0.018, 0.04), vec3(0.42, 0.62, 0.82), day);
	sky = mix(sky, vec3(0.95, 0.60, 0.45), (1.0 - smoothstep(0.02, 0.30, sun_height)) * day);
	water = mix(water, sky, fresnel * 0.6);
	water = mix(water, vec3(0.86, 0.95, 0.93), foam * 0.75);
	water += vec3(0.85, 0.95, 1.0) * streak * 0.18;
	vec3 half_direction = normalize(eye + sun_dir);
	float glint = pow(max(dot(v_up, half_direction), 0.0), 220.0);
	water *= mix(0.16, 1.0, day);
	ALBEDO = water + vec3(1.0, 0.82, 0.58) * glint * day * 0.6;
	ALPHA = mix(0.55, 0.92, t);
}
