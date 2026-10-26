shader_type spatial;
render_mode cull_disabled;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
uniform bool edges_only = false;
uniform float cloth_time = 0.0;
varying float width_position;
void vertex() {
	width_position = abs(VERTEX.x);
	VERTEX.y += sin(VERTEX.x * 4.0 + VERTEX.z * 7.0 + cloth_time * 2.5) * 0.03;
	v_sunlit = cloud_sunlit((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	toon_distance = length(VERTEX);
	if (edges_only && width_position < 0.95) { discard; }
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	ALBEDO = vec3(0.8, 0.3, 0.22);
	ROUGHNESS = 1.0;
}
