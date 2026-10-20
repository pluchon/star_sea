shader_type spatial;
render_mode cull_back;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
uniform bool grass_cap = false;
varying vec3 v_world;
varying float v_altitude;
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_altitude = length(v_world - focus_center) - 40000.0;
	v_sunlit = cloud_sunlit(v_world);
}
void fragment() {
	float layer = mod(floor(v_altitude / 27.0), 3.0);
	vec3 pigment = layer < 1.0 ? vec3(0.381, 0.102, 0.045) : (layer < 2.0 ? vec3(0.584, 0.323, 0.105) : vec3(0.687, 0.610, 0.480));
	if (grass_cap) {
		pigment = vec3(0.19, 0.29, 0.08);
	}
	float haze = mist_amount(v_world, distance(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = pigment * (1.0 - haze);
	EMISSION = mist_color * haze;
	ROUGHNESS = 0.95;
}
