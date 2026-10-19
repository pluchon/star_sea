shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform float wind_strength = 0.0;
varying vec3 v_color;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	VERTEX.x += sin(TIME * 1.6 + phase + VERTEX.y * 1.5) * VERTEX.y * wind_strength;
	VERTEX.z += cos(TIME * 1.1 + phase) * VERTEX.y * wind_strength * 0.4;
	v_color = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_color;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
}
