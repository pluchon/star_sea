shader_type spatial;
render_mode cull_back, depth_draw_never;

#include "res://shaders/toon_light.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.36, 0.78, 0.80);
uniform vec3 deep : source_color = vec3(0.08, 0.22, 0.42);
uniform float depth_range = 25.0;
uniform vec3 planet_center;
varying vec3 v_position;

void vertex() {
	v_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - planet_center;
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float water_depth = length(view.xyz) - length(VERTEX);
	float t = clamp(water_depth / depth_range, 0.0, 1.0);
	float ripple = sin(v_position.x * 0.9 + v_position.z * 0.6 + TIME * 1.1);
	float wave = sin(v_position.z * 0.22 - v_position.y * 0.31 + TIME * 0.65);
	float foam_band = sin(water_depth * 6.0 - TIME * 1.4 + wave);
	float foam = (1.0 - smoothstep(0.0, 1.6, water_depth)) * smoothstep(0.3, 0.8, foam_band);
	float glint = (ripple + wave) * 0.006 * (1.0 - smoothstep(30.0, 180.0, length(VERTEX)));
	ALBEDO = mix(mix(shallow, deep, t), vec3(0.88, 0.97, 0.96), foam * 0.75) + glint;
	ALBEDO = mix(ALBEDO, mix(shallow, deep, 0.65), smoothstep(180.0, 1800.0, length(VERTEX)) * 0.35);
	ALPHA = mix(0.55, 1.0, t);
	ROUGHNESS = 1.0;
}
