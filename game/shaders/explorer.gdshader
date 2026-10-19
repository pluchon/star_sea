shader_type spatial;
#include "res://shaders/toon_light.gdshaderinc"
global uniform float rim_strength;
uniform vec4 pigment : source_color = vec4(0.8, 0.8, 0.7, 1.0);

void fragment() {
	ALBEDO = pigment.rgb;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = ALBEDO * rim * rim_strength;
}
