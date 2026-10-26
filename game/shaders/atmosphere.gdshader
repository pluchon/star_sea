shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled, shadows_disabled;

global uniform vec3 sun_dir;
global uniform float cave_factor;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 planet_center;
uniform float planet_radius;
uniform float atmo_radius;
uniform float density = 1.5;
uniform float falloff = 4.0;
uniform vec3 tower_origin = vec3(0.0);
uniform vec3 tower_up = vec3(0.0);
uniform float tower_pixel_radius = 0.0;
uniform vec3 day_color : source_color = vec3(0.52, 0.74, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.56, 0.38);
uniform vec3 night_color : source_color = vec3(0.03, 0.04, 0.10);

vec2 ray_sphere(vec3 ro, vec3 rd, vec3 c, float r) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float k = dot(oc, oc) - r * r;
	float h = b * b - k;
	if (h < 0.0) {
		return vec2(1e20, -1e20);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float scene_dist = length(view.xyz);
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	vec3 camera_up = normalize(ro - planet_center);
	float elevation = max(dot(rd, camera_up), 0.0);
	vec2 shell = ray_sphere(ro, rd, planet_center, atmo_radius);
	float t0 = max(shell.x, 0.0);
	float t1 = min(shell.y, scene_dist);
	vec2 ground = ray_sphere(ro, rd, planet_center, planet_radius);
	if (ground.x > 0.0) {
		t1 = min(t1, ground.x);
	}
	if (t1 <= t0) {
		discard;
	}
	// 沿视线分 8 段积分：越低越稠密，越靠前的大气挡住后面的
	float thickness = atmo_radius - planet_radius;
	float seg = (t1 - t0) / 8.0;
	float optical = 0.0;
	vec3 sum = vec3(0.0);
	float weight = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 p = ro + rd * (t0 + seg * (float(i) + 0.5));
		vec3 up = normalize(p - planet_center);
		float h = clamp((length(p - planet_center) - planet_radius) / thickness, 0.0, 1.0);
		float d = exp(-h * falloff) * seg / thickness * density;
		float sun_h = dot(up, sun_dir);
		vec3 day_gradient = mix(day_color, vec3(0.16, 0.38, 0.78), pow(elevation, 0.45) * 0.65);
		vec3 dusk_gradient = mix(sunset_color, vec3(0.29, 0.24, 0.50), smoothstep(0.0, 0.7, elevation));
		vec3 lit = mix(dusk_gradient, day_gradient, smoothstep(-0.02, 0.30, sun_h));
		lit = mix(night_color, lit, smoothstep(-0.22, 0.04, sun_h));
		float w = d * exp(-optical);
		sum += lit * w;
		weight += w;
		optical += d;
	}
	ALBEDO = sum / max(weight, 1e-5);
	// 用不透明深度终点识别塔身，仅减弱塔面前方的大气，天空和山体保持原值。
	vec3 endpoint = ro + rd * scene_dist - planet_center - tower_origin;
	float tower_height = dot(endpoint, tower_up);
	float tower_radius = max(mix(60.0, 38.0, clamp(tower_height / 1000.0, 0.0, 1.0)), scene_dist * tower_pixel_radius);
	bool tower_surface = length(tower_up) > 0.5 && tower_height > 300.0 && tower_height < 6199.0 && abs(length(endpoint - tower_up * tower_height) - tower_radius) < 2.0;
	float cave_density = mix(1.0, 0.5, cave_factor);
	float opacity = clamp(1.0 - exp(-optical * (tower_surface ? 0.6 : 1.0) * cave_density), 0.0, depth > 0.000001 ? 0.65 : 1.0);
	// 地表保留至少 77% 的明度差；天空沿用完整积分，不复制屏幕颜色。
	ALPHA = opacity * (depth > 0.000001 ? 0.35 : 1.0);
}
