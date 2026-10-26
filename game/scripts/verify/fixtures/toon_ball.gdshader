shader_type spatial;

#include "res://shaders/toon_light.gdshaderinc"


void fragment() {
	toon_distance = length(VERTEX);
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	EMISSION = vec3(0.0);
}
