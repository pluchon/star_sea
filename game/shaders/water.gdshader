shader_type spatial;
render_mode cull_back, depth_draw_never, depth_test_disabled, shadows_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.36, 0.78, 0.80);
uniform vec3 deep : source_color = vec3(0.08, 0.22, 0.42);
uniform float depth_range = 25.0;
uniform vec3 planet_center;
uniform float planet_radius = 40000.0;
global uniform vec3 sun_dir;

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	vec3 origin = (CAMERA_POSITION_WORLD - planet_center) / planet_radius;
	float b = dot(origin, ray);
	float discriminant = b * b - dot(origin, origin) + 1.0;
	if (discriminant < 0.0) {
		discard;
	}
	float water_distance = (-b - sqrt(discriminant)) * planet_radius;
	if (water_distance < 0.0 || water_distance > length(view.xyz) + 0.03) {
		discard;
	}
	// 所有分块用同一条射线与球面交点着色，避免曲面弦长差异形成远海条带。
	vec3 v_world = CAMERA_POSITION_WORLD + ray * water_distance;
	vec3 v_position = v_world - planet_center;
	float water_depth = max(length(view.xyz) - water_distance, 0.0);
	float t = clamp(water_depth / depth_range, 0.0, 1.0);
	float warp_a = dot(v_position, vec3(0.11, 0.17, 0.07));
	float warp_b = dot(v_position, vec3(0.23, 0.03, 0.19));
	float phase_a = dot(v_position, vec3(0.9, 0.3, 0.6)) + sin(warp_a) * 1.2 + TIME * 1.1;
	float phase_b = dot(v_position, vec3(0.22, -0.31, 0.44)) + sin(warp_b) * 0.8 + TIME * 0.65;
	float ripple = sin(phase_a);
	float wave = sin(phase_b);
	float foam_band = sin(water_depth * 6.0 - TIME * 1.4 + wave);
	float foam = (1.0 - smoothstep(0.0, 1.6, water_depth)) * smoothstep(0.3, 0.8, foam_band);
	float glint = ripple * wave * 0.0012 * (1.0 - smoothstep(20.0, 70.0, water_distance));
	vec3 up = normalize(v_position);
	float near_wave = 1.0 - smoothstep(20.0, 90.0, water_distance);
	vec3 gradient = (vec3(0.9, 0.3, 0.6) + cos(warp_a) * vec3(0.11, 0.17, 0.07) * 1.2) * cos(phase_a);
	gradient += (vec3(0.22, -0.31, 0.44) + cos(warp_b) * vec3(0.23, 0.03, 0.19) * 0.8) * cos(phase_b);
	gradient -= up * dot(up, gradient);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(up - gradient * near_wave * 0.025), 0.0)).xyz);
	vec3 eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float fresnel = pow(1.0 - max(dot(up, eye), 0.0), 4.0);
	vec3 water = mix(shallow, deep, smoothstep(0.0, 1.0, t));
	float day = smoothstep(-0.10, 0.18, dot(up, sun_dir));
	vec3 horizon = mix(vec3(0.012, 0.018, 0.04), vec3(0.06, 0.15, 0.30), day);
	water = mix(water, horizon, fresnel * 0.55);
	ALBEDO = mix(water, vec3(0.79, 0.91, 0.88), foam * 0.8) + glint;
	vec3 half_direction = normalize(eye + sun_dir);
	float sun_path = pow(max(dot(up, half_direction), 0.0), 180.0);
	EMISSION = vec3(1.0, 0.77, 0.48) * sun_path * day * (0.15 + wave * ripple * 0.04);
	ALPHA = mix(0.55, 1.0, t);
	ROUGHNESS = 1.0;
}
