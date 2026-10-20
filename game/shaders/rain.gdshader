shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 雨丝：一张网格里放几百个细长四边形，位置全部在着色器里按相机附近的方盒计算，
// 沿当地竖直方向下落并略随风斜；超出方盒的部分绕回另一侧，相机移动时雨丝相对地面静止。
global uniform float rain;
global uniform vec3 sky_up;
global uniform vec3 wind_dir;
global uniform float wind_speed;

varying float v_fade;

void vertex() {
	vec3 seed = vec3(UV2, COLOR.r);
	vec3 up = sky_up;
	vec3 axis_a = normalize(cross(up, abs(up.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 axis_b = cross(up, axis_a);
	vec3 camera = CAMERA_POSITION_WORLD;
	float span = 36.0;
	float a = mod(seed.x * span - dot(camera, axis_a), span) - span * 0.5;
	float b = mod(seed.y * span - dot(camera, axis_b), span) - span * 0.5;
	float fall = fract(seed.z * 13.7 + TIME * (1.1 + seed.y * 0.3));
	vec3 slant = normalize(-up + wind_dir * wind_speed * 0.25);
	vec3 center = camera + axis_a * a + axis_b * b - slant * (fall * 18.0 - 9.0);
	vec3 view = normalize(center - camera);
	vec3 side = normalize(cross(slant, view));
	vec3 world = center + side * (UV.x - 0.5) * 0.022 + slant * (UV.y - 0.5) * 0.75;
	// 雨量小于种子值的雨丝不显示，雨越大越密。
	v_fade = step(seed.z, rain) * (1.0 - smoothstep(10.0, 18.0, length(center - camera)));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = vec3(0.78, 0.83, 0.90);
	ALPHA = across * v_fade * 0.32;
}
