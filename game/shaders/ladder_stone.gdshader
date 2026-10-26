shader_type spatial;
#include "res://shaders/toon_light.gdshaderinc"
render_mode cull_back;
#include "weather.gdshaderinc"
uniform int kind = 0;
uniform float frost = 0.0;
uniform float cloth_time = 0.0;
uniform sampler2D stone_paint : filter_linear_mipmap, repeat_enable;
instance uniform float awake = 0.15;
varying vec3 stable_position;
varying float upward;
varying vec3 object_position;
void vertex() {
	if (kind == 3) { VERTEX.z += smoothstep(0.0, 5.0, abs(VERTEX.x) - 19.0) * sin(cloth_time * 1.5 + VERTEX.x * 1.6) * 0.3; }
	stable_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - focus_center;
	upward = dot(normalize(MODEL_NORMAL_MATRIX * NORMAL), normalize(stable_position));
	object_position = VERTEX;
}
void fragment() {
	toon_distance = length(VERTEX);
	vec3 pigment = vec3(0.716, 0.672, 0.578);
	if (kind == 1) { pigment = vec3(0.112, 0.263, 0.233); }
	if (kind == 2) { pigment = vec3(0.888, 0.456, 0.102); EMISSION = pigment * awake * 2.0; }
	if (kind == 3) { pigment = vec3(0.71, 0.40, 0.29); }
	if (kind == 0) {
		pigment *= 0.94 + 0.06 * sin(UV.x * 4.0 + UV.y * 3.0);
		float detail = 1.0 - smoothstep(120.0, 400.0, toon_distance);
		if (detail > 0.001) {
			vec3 weights = pow(abs(mat3(INV_VIEW_MATRIX) * NORMAL), vec3(4.0));
			weights /= max(weights.x + weights.y + weights.z, 0.001);
			float middle = dot(vec3(texture(stone_paint, stable_position.yz / 18.0).r, texture(stone_paint, stable_position.xz / 18.0).r, texture(stone_paint, stable_position.xy / 18.0).r), weights);
			float small = dot(vec3(texture(stone_paint, stable_position.yz / 3.0).r, texture(stone_paint, stable_position.xz / 3.0).r, texture(stone_paint, stable_position.xy / 3.0).r), weights);
			pigment *= 1.0 + ((middle - 0.78) * 1.1 + (small - 0.78) * 0.5) * detail;
		}
		vec2 cell = object_position.xz / 2.0;
		vec2 joint_distance = min(fract(cell), 1.0 - fract(cell));
		float joints = 1.0 - smoothstep(0.008, 0.025, min(joint_distance.x, joint_distance.y));
		float tile = fract(sin(dot(floor(cell), vec2(127.1, 311.7))) * 43758.5453);
		pigment *= mix(1.0, mix(0.91, 1.02, tile) * (1.0 - joints * 0.25), smoothstep(0.65, 0.9, upward));
		pigment = mix(pigment, vec3(0.80, 0.87, 0.92), frost * smoothstep(0.60, 0.9, upward));
	}
	ALBEDO = pigment;
	ROUGHNESS = 0.9;
}
