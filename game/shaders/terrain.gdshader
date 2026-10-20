shader_type spatial;
render_mode cull_back;

#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"

global uniform float rim_strength;
uniform vec3 planet_center;

uniform vec3 sand : source_color = vec3(0.86, 0.80, 0.64);
uniform vec3 grass : source_color = vec3(0.48, 0.60, 0.28);
uniform vec3 grass_far : source_color = vec3(0.54, 0.61, 0.38);
uniform vec3 rock : source_color = vec3(0.43, 0.44, 0.46);
uniform vec3 snow : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 dry_grass : source_color = vec3(0.71, 0.61, 0.35);
uniform vec3 wet_grass : source_color = vec3(0.29, 0.46, 0.34);
uniform vec3 cold_grass : source_color = vec3(0.48, 0.48, 0.34);
uniform vec3 forest_ground : source_color = vec3(0.24, 0.34, 0.16);
uniform float planet_radius = 40000.0;
uniform float snow_height = 1580.0;
uniform float beach_height = 12.0;
uniform bool terrestrial = true;
uniform sampler2D ground_paint : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 volcano_center = vec3(0.0);
uniform float volcano_radius = 0.0;
uniform vec3 basalt : source_color = vec3(0.30, 0.25, 0.25);
uniform vec3 ash : source_color = vec3(0.55, 0.47, 0.42);

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
		c = mix(dry_grass, c, smoothstep(0.28, 0.48, v_climate.x));
		float wetland = smoothstep(0.66, 0.80, v_climate.x) * (1.0 - smoothstep(70.0, 120.0, v_height));
		c = mix(c, wet_grass, wetland * 0.85);
		float alpine = max(1.0 - smoothstep(0.20, 0.30, v_climate.y), smoothstep(1150.0, 1400.0, v_height));
		c = mix(c, cold_grass, alpine * 0.8);
		float woodland = v_grove * smoothstep(0.34, 0.62, v_climate.x) * smoothstep(0.24, 0.36, v_climate.y) * (1.0 - smoothstep(1150.0, 1400.0, v_height)) * (1.0 - wetland);
		vec3 forest_color = mix(forest_ground * vec3(0.91, 1.0, 1.13), forest_ground, smoothstep(0.45, 0.55, v_climate.y));
		c = mix(c, forest_color, woodland * 0.57 * smoothstep(10.0, 25.0, v_height));
	}
	float meadow = patch(v_position / 110.0) * 0.5 + 0.5;
	c = mix(c, c * vec3(1.08, 1.02, 0.88), meadow * 0.45);
	c = mix(sand * 0.82, sand, smoothstep(-1.0, 3.0, v_height)) * (1.0 - smoothstep(2.0, beach_height, v_height)) + c * smoothstep(2.0, beach_height, v_height);
	c = mix(c, rock, smoothstep(0.22, 0.34, v_slope));
	if (volcano_radius > 0.0) {
		// 火山上半部是深色玄武岩，山腰过渡为灰褐色火山灰，岩面带少量色块。
		float reach = 1.0 - distance(normalize(v_position) * planet_radius, volcano_center) / volcano_radius;
		float rock_cover = smoothstep(0.35, 0.62, reach + patch(v_position / 45.0) * 0.06);
		float ash_cover = smoothstep(0.12, 0.35, reach) * (1.0 - rock_cover);
		c = mix(c, ash * (0.95 + patch(v_position / 20.0) * 0.08), ash_cover * 0.7);
		c = mix(c, basalt * (0.9 + patch(v_position / 12.0) * 0.12), rock_cover);
	}
	float snow_line = smoothstep(snow_height - 80.0, snow_height + 120.0, v_height + patch(v_position / 150.0) * 65.0) * (1.0 - smoothstep(0.30, 0.45, v_slope));
	c = mix(c, snow, snow_line);
	float variation = patch(v_position / 32.0) * 0.07 + patch(v_position / 3.0) * 0.028;
	float exposed = smoothstep(0.20, 0.40, v_slope);
	c = mix(c, rock * (0.85 + patch(v_position / 14.0) * 0.12), exposed * 0.45);
	// 岩壁用宽色带表现层理，保持色块风格，不增加照片纹理。
	float strata = sin(v_height * 0.11 + patch(v_position / 70.0));
	c *= 1.0 + strata * exposed * 0.045;
	c *= 1.0 + variation;
	if (terrestrial) {
		// 自绘短笔触采用三轴投影，近景补充细节，远景淡出以避免闪烁和规则网格。
		vec3 weights = pow(abs(normalize(v_position)), vec3(4.0));
		weights /= weights.x + weights.y + weights.z;
		float brush = dot(vec3(texture(ground_paint, v_position.yz / 9.0).r, texture(ground_paint, v_position.xz / 9.0).r, texture(ground_paint, v_position.xy / 9.0).r), weights);
		float near_detail = 1.0 - smoothstep(35.0, 160.0, distance(v_position + planet_center, CAMERA_POSITION_WORLD));
		c *= 1.0 + (brush * 2.0 - 1.0) * near_detail * 0.25 * (1.0 - snow_line);
	}
	// 雨后地面颜色变深，雨停后慢慢变干。
	c *= 1.0 - wetness * 0.2;
	float haze = mist_amount(v_position + planet_center, distance(v_position + planet_center, CAMERA_POSITION_WORLD));
	ALBEDO = c * (1.0 - haze);
	v_sunlit = cloud_sunlit(v_position + planet_center);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = ALBEDO * rim * rim_strength + mist_color * haze;
}
