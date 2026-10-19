shader_type spatial;

#include "res://shaders/toon_light.gdshaderinc"

uniform vec3 band_a : source_color = vec3(0.93, 0.80, 0.62);
uniform vec3 band_b : source_color = vec3(0.78, 0.55, 0.45);
uniform vec3 band_c : source_color = vec3(0.60, 0.62, 0.78);

varying vec3 v_local;

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	float warp = sin(v_local.x * 9.0 + v_local.z * 7.0) * 0.04;
	float lat = v_local.y + warp;
	float s = sin(lat * 22.0) * 0.5 + 0.5;
	float t = sin(lat * 7.0 + 1.3) * 0.5 + 0.5;
	ALBEDO = mix(mix(band_a, band_b, smoothstep(0.35, 0.65, s)), band_c, smoothstep(0.6, 0.9, t) * 0.6);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.55, 0.65, 1.0) * rim * 0.4;
}
