shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon_light.gdshaderinc"

uniform float wind_strength = 0.0;
uniform bool is_grass = false;
varying vec3 v_color;
varying float v_root;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	float sway = UV.y * wind_strength;
	VERTEX.x += sin(TIME * 1.6 + phase + VERTEX.y * 0.35) * sway;
	VERTEX.z += cos(TIME * 1.1 + phase) * sway * 0.6;
	v_color = COLOR.rgb;
	v_root = is_grass ? smoothstep(0.0, 0.35, VERTEX.y) : 1.0;
}

void fragment() {
	ALBEDO = v_color * mix(0.68, 1.0, v_root);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
}
