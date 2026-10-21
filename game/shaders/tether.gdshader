shader_type spatial;
render_mode cull_back;
#include "weather.gdshaderinc"
uniform float tether_time = 0.0;
varying vec3 stable_position;
void vertex() {
	float weight = clamp(-VERTEX.y / 800.0, 0.0, 1.0);
	VERTEX.x += sin(tether_time * 0.22 + VERTEX.y * 0.004) * weight * 2.0;
	stable_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - focus_center;
}
void fragment() { ALBEDO = vec3(0.24, 0.34, 0.30); ROUGHNESS = 0.75; }
#include "toon_light.gdshaderinc"
