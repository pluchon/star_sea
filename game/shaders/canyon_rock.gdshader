shader_type spatial;
render_mode cull_back;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
#include "res://shaders/strata.gdshaderinc"
uniform bool grass_cap = false;
varying vec3 v_world;
varying float v_altitude;
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_altitude = length(v_world - focus_center) - 40000.0;
	v_sunlit = cloud_sunlit(v_world);
}
void fragment() {
	toon_distance = length(VERTEX);
	vec3 pigment = strata_pigment(v_world - focus_center, v_altitude, max(0.0, dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(v_world - focus_center, 0.0)).xyz))));
	if (grass_cap) {
		pigment = vec3(0.19, 0.29, 0.08);
	}
	float haze = mist_amount(v_world, distance(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = pigment * (1.0 - haze);
	EMISSION = mist_color * haze;
	ROUGHNESS = 0.95;
}
