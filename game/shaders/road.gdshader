shader_type spatial;
render_mode cull_back;
#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
varying float v_wear;
varying vec3 v_world;

float tile_noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	v_wear = COLOR.r;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_sunlit = cloud_sunlit(v_world);
}

void fragment() {
	toon_distance = length(VERTEX);
	float row = floor(UV.y / 0.6);
	vec2 tile = vec2(UV.x / 0.8 + mod(row, 2.0) * 0.5, UV.y / 0.6);
	vec2 inside = fract(tile);
	float noise = tile_noise(floor(tile));
	if (noise < v_wear || inside.x < 0.025 || inside.y < 0.035) discard;
	vec3 stone = vec3(0.72, 0.66, 0.51) * (0.92 + noise * 0.16);
	float seam = 1.0 - smoothstep(0.03, 0.08, min(min(inside.x, 1.0 - inside.x), min(inside.y, 1.0 - inside.y)));
	stone = mix(stone, vec3(0.31, 0.39, 0.20), seam * 0.45);
	float haze = mist_amount(v_world, distance(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = stone * (1.0 - wetness * 0.2) * (1.0 - haze);
	EMISSION = mist_color * haze;
	ROUGHNESS = 1.0;
}
