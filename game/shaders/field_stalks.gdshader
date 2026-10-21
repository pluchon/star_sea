shader_type spatial;
render_mode cull_back;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
uniform float wind_strength = 0.08;
uniform float field_time = 0.0;
varying vec3 v_color;
varying float v_haze;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 relative = root - focus_center;
	vec3 side = normalize(cross(normalize(relative), wind_dir));
	float phase = INSTANCE_CUSTOM.r * 6.283185;
	float wave = sin(dot(relative, wind_dir) / 9.0 - field_time * 2.3 + sin(dot(relative, side) / 17.0) * 1.6);
	vec3 push = (wind_dir * (0.675 + wave * 0.325) + side * sin(field_time * 3.4 + phase) * 0.088) * wind_speed;
	mat3 model = mat3(MODEL_MATRIX);
	VERTEX += transpose(model) * push * UV2.x * wind_strength / max(dot(model[0], model[0]), 0.001);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR.rgb;
	v_sunlit = cloud_sunlit(world);
	v_haze = mist_amount(world, distance(world, CAMERA_POSITION_WORLD));
}

void fragment() {
	ALBEDO = v_color * (1.0 - wetness * 0.12) * (1.0 - v_haze);
	EMISSION = mist_color * v_haze;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
