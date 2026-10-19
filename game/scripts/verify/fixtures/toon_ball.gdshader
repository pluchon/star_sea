shader_type spatial;

#include "res://shaders/toon_light.gdshaderinc"

global uniform float rim_strength;

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = ALBEDO * rim * rim_strength;
}
