shader_type spatial;
render_mode cull_back;
#include "weather.gdshaderinc"
uniform int kind = 0;
uniform float frost = 0.0;
instance uniform float awake = 0.15;
varying vec3 stable_position;
varying float upward;
varying vec3 object_position;
void vertex() {
	stable_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - focus_center;
	upward = dot(normalize(MODEL_NORMAL_MATRIX * NORMAL), normalize(stable_position));
	object_position = VERTEX;
}
void fragment() {
	vec3 pigment = vec3(0.716, 0.672, 0.578);
	if (kind == 1) { pigment = vec3(0.112, 0.263, 0.233); }
	if (kind == 2) { pigment = vec3(0.888, 0.456, 0.102); EMISSION = pigment * awake * 2.0; }
	if (kind == 0) {
		pigment *= 0.94 + 0.06 * sin(UV.x * 4.0 + UV.y * 3.0);
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
#include "toon_light.gdshaderinc"
