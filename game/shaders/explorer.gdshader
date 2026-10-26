shader_type spatial;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
uniform vec4 pigment : source_color = vec4(0.8, 0.8, 0.7, 1.0);

void vertex() {
	v_sunlit = cloud_sunlit((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	toon_distance = length(VERTEX);
	ALBEDO = pigment.rgb;
	ROUGHNESS = 1.0;
	EMISSION = vec3(0.0);
}
