shader_type spatial;
render_mode cull_back;

#include "res://shaders/toon_light.gdshaderinc"

global uniform float rim_strength;
uniform vec3 planet_center;

uniform vec3 sand : source_color = vec3(0.86, 0.80, 0.64);
uniform vec3 grass : source_color = vec3(0.37, 0.49, 0.23);
uniform vec3 grass_far : source_color = vec3(0.48, 0.54, 0.34);
uniform vec3 rock : source_color = vec3(0.43, 0.44, 0.46);
uniform vec3 snow : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 dry_grass : source_color = vec3(0.60, 0.56, 0.31);
uniform vec3 wet_grass : source_color = vec3(0.25, 0.37, 0.20);
uniform vec3 cold_grass : source_color = vec3(0.48, 0.48, 0.34);
uniform vec3 forest_ground : source_color = vec3(0.24, 0.34, 0.16);
uniform float planet_radius = 40000.0;
uniform float snow_height = 1580.0;
uniform float beach_height = 12.0;
uniform bool terrestrial = true;

varying float v_height;
varying float v_slope;
varying vec3 v_position;
varying vec2 v_climate;
varying float v_grove;

float patch(vec3 p) {
	// 三轴连续变化，避免两极附近的色块拉伸成条纹。
	return sin(p.x * 1.3 + sin(p.y * 0.7)) * sin(p.z * 0.9 + p.y * 0.5);
}

void vertex() {
	v_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - planet_center;
	// 顶点颜色只有八位精度，不能承载公里范围内的海岸高度。
	v_height = length(v_position) - planet_radius;
	v_slope = COLOR.g;
	v_climate = vec2(COLOR.b, clamp(1.05 - abs(normalize(v_position).y) * 0.72 - max(v_height, 0.0) / 2800.0, 0.0, 1.0));
	v_grove = COLOR.a;
}

void fragment() {
	vec3 c = mix(grass, grass_far, smoothstep(300.0, 1200.0, v_height));
	if (terrestrial) {
		c = mix(dry_grass, c, smoothstep(0.18, 0.55, v_climate.x));
		c = mix(c, wet_grass, smoothstep(0.55, 0.86, v_climate.x) * 0.6);
		c = mix(c, cold_grass, 1.0 - smoothstep(0.15, 0.40, v_climate.y));
		float woodland = v_grove * smoothstep(0.20, 0.65, v_climate.x) * (1.0 - smoothstep(1200.0, 1600.0, v_height));
		c = mix(c, forest_ground, woodland * 0.38 * smoothstep(10.0, 25.0, v_height));
	}
	float meadow = patch(v_position / 110.0) * 0.5 + 0.5;
	c = mix(c, c * vec3(1.08, 1.02, 0.88), meadow * 0.45);
	c = mix(sand * 0.82, sand, smoothstep(-1.0, 3.0, v_height)) * (1.0 - smoothstep(2.0, beach_height, v_height)) + c * smoothstep(2.0, beach_height, v_height);
	c = mix(c, rock, smoothstep(0.22, 0.34, v_slope));
	float snow_line = smoothstep(snow_height - 80.0, snow_height + 120.0, v_height + patch(v_position / 150.0) * 65.0) * (1.0 - smoothstep(0.30, 0.45, v_slope));
	c = mix(c, snow, snow_line);
	float variation = patch(v_position / 32.0) * 0.07 + patch(v_position / 3.0) * 0.028;
	float exposed = smoothstep(0.20, 0.40, v_slope);
	c = mix(c, rock * (0.85 + patch(v_position / 14.0) * 0.12), exposed * 0.45);
	c *= 1.0 + variation;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = ALBEDO * rim * rim_strength;
}
