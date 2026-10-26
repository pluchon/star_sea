shader_type spatial;
#include "res://shaders/toon_light.gdshaderinc"
render_mode cull_back;
#include "weather.gdshaderinc"
uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform bool ice = false;
varying vec3 stable_position;
varying vec4 marks;
varying float layer_noise;
void vertex() {
	stable_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - focus_center;
	marks = COLOR;
	layer_noise = weather_noise(stable_position * 0.15);
}
void fragment() {
	toon_distance = length(VERTEX);
	float height = dot(stable_position, local_up);
	float band = 0.94 + 0.06 * sin(height * 2.4 + layer_noise);
	vec3 rock = vec3(0.20, 0.23, 0.27) * band;
	vec3 stone = vec3(0.57, 0.47, 0.31);
	float joint = smoothstep(0.025, 0.06, abs(fract(height * 1.2) - 0.5));
	vec3 pigment = mix(rock, stone * mix(0.78, 1.0, joint), marks.a);
	pigment = mix(pigment * vec3(0.62, 0.81, 0.57), pigment, smoothstep(0.0, 0.42, marks.b));
	pigment *= 1.0 - marks.g * 0.22;
	if (ice) {
		float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
		pigment = mix(vec3(0.40, 0.64, 0.75), vec3(0.73, 0.87, 0.92), fresnel);
	}
	ALBEDO = pigment;
	AO = marks.r;
	ROUGHNESS = mix(0.95, 0.45, marks.g);
}
