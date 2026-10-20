shader_type spatial;
render_mode cull_disabled;

#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"

uniform int kind = 0;
uniform bool batched = false;
uniform sampler2D stone_texture : source_color, filter_linear_mipmap, repeat_enable;
instance uniform float moss = 0.0;
instance uniform float sand = 0.0;
instance uniform float awake = 0.0;
instance uniform float base_height = 0.0;
varying vec4 v_weathering;
varying vec4 v_color;
varying float v_upward;
varying float v_height;
varying float v_distance;
varying float v_haze;

void vertex() {
	v_weathering = batched ? INSTANCE_CUSTOM : vec4(moss, sand, awake, base_height);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (kind == 3 && COLOR.b < 0.5) {
		mat3 model = mat3(MODEL_MATRIX);
		VERTEX += transpose(model) * wind_push(world, VERTEX.x) * COLOR.g * 0.18 / max(dot(model[0], model[0]), 0.001);
	}
	v_color = COLOR;
	v_upward = dot(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz), normalize(world - focus_center));
	v_height = VERTEX.y + v_weathering.w;
	v_distance = distance(world, CAMERA_POSITION_WORLD);
	v_haze = mist_amount(world, v_distance);
	v_sunlit = cloud_sunlit(world);
}

void fragment() {
	vec3 pigment = vec3(0.72, 0.62, 0.43);
	if (kind == 0) {
		// 规格中的十六进制色先转换为线性空间，避免石材和铜锈过亮。
		pigment = vec3(0.672, 0.571, 0.371) * mix(0.9, 1.07, texture(stone_texture, UV).r);
		pigment *= v_color.r;
		float moss_pattern = smoothstep(0.5, 0.75, weather_noise(vec3(UV * 0.4, 2.0)));
		pigment = mix(pigment, pigment * vec3(0.59, 0.78, 0.43), v_weathering.x * smoothstep(0.64, 0.9, v_upward) * moss_pattern * 0.7);
		pigment = mix(pigment, vec3(0.59, 0.47, 0.3), v_weathering.y * (1.0 - smoothstep(0.0, 0.8, v_height)));
		float crack = 1.0 - smoothstep(0.005, 0.025, abs(weather_noise(vec3(UV * 7.0, 0.5)) - 0.5));
		pigment *= 1.0 - crack * 0.15 * (1.0 - smoothstep(25.0, 60.0, v_distance));
	} else if (kind == 1) {
		pigment = mix(vec3(0.055, 0.04, 0.015), vec3(0.112, 0.263, 0.233), v_color.r);
	} else if (kind == 2) {
		pigment = vec3(0.888, 0.456, 0.102);
		EMISSION = pigment * mix(0.1, 2.0, v_weathering.z) * (1.0 + sin(TIME * 1.570796) * 0.08 * v_weathering.z);
	} else {
		pigment = mix(vec3(0.462, 0.133, 0.068), vec3(0.047, 0.133, 0.033), step(0.5, v_color.b));
	}
	ALBEDO = pigment * (1.0 - wetness * 0.15) * (1.0 - v_haze);
	EMISSION += mist_color * v_haze;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
