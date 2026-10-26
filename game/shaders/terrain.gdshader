shader_type spatial;
render_mode cull_back;

#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"

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
uniform sampler2D rock_paint : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 volcano_center = vec3(0.0);
uniform float volcano_radius = 0.0;
uniform vec3 basalt : source_color = vec3(0.30, 0.25, 0.25);
uniform vec3 ash : source_color = vec3(0.55, 0.47, 0.42);

varying float v_height;
varying float v_slope;
varying vec3 v_position;
varying vec2 v_climate;
varying float v_grove;
varying vec4 v_marks;
varying float v_cavity;
varying vec3 v_normal;

float patch(vec3 p) {
	// 三轴连续变化，避免两极附近的色块拉伸成条纹。
	return sin(p.x * 1.3 + sin(p.y * 0.7)) * sin(p.z * 0.9 + p.y * 0.5);
}

void vertex() {
	v_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - planet_center;
	// 顶点颜色只有八位精度，不能承载公里范围内的海岸高度。
	v_height = length(v_position) - planet_radius;
	v_slope = COLOR.g;
	v_cavity = COLOR.r;
	v_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_climate = vec2(COLOR.b, clamp(1.05 - abs(normalize(v_position).y) * 0.72 - max(v_height, 0.0) / 2800.0, 0.0, 1.0));
	v_grove = COLOR.a;
	v_marks = CUSTOM0;
	// 云影变化尺度约 700 米，沿地形顶点插值，避免每个像素重复计算噪声。
	v_sunlit = cloud_sunlit(v_position + planet_center);
}

void fragment() {
	toon_distance = length(VERTEX);
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
		if (reach > 0.12) {
			float rock_cover = smoothstep(0.35, 0.62, reach + patch(v_position / 45.0) * 0.06);
			float ash_cover = smoothstep(0.12, 0.35, reach) * (1.0 - rock_cover);
			c = mix(c, ash * (0.95 + patch(v_position / 20.0) * 0.08), ash_cover * 0.7);
			c = mix(c, basalt * (0.9 + patch(v_position / 12.0) * 0.12), rock_cover);
		}
	}
	float snow_line = 0.0;
	if (v_height > snow_height - 145.0) {
		snow_line = smoothstep(snow_height - 80.0, snow_height + 120.0, v_height + patch(v_position / 150.0) * 65.0) * (1.0 - smoothstep(0.30, 0.45, v_slope));
	}
	c = mix(c, snow, snow_line);
	float variation = patch(v_position / 32.0) * 0.07 + patch(v_position / 3.0) * 0.028;
	float exposed = smoothstep(0.20, 0.40, v_slope);
	c = mix(c, rock * (0.85 + patch(v_position / 14.0) * 0.12), exposed * 0.45);
	// 岩壁用宽色带表现层理，保持色块风格，不增加照片纹理。
	float strata = sin(v_height * 0.11 + patch(v_position / 70.0));
	c *= 1.0 + strata * exposed * 0.045;
	c *= 1.0 + variation;
	// 雨后地面颜色变深，雨停后慢慢变干。
	if (terrestrial) {
		float warped_height = v_height + sin(v_height * 0.031) * 11.0 + patch(v_position / 160.0) * 7.0;
		float band = sin(warped_height * 0.17 + sin(warped_height * 0.043) * 2.3);
		vec3 strata_color = mix(vec3(0.673, 0.571, 0.371), vec3(0.479, 0.376, 0.254), band * 0.5 + 0.5);
		strata_color = mix(strata_color, vec3(0.434, 0.195, 0.102), smoothstep(0.80, 0.99, sin(warped_height * 0.037)) * 0.32);
		vec3 radial = normalize(v_position);
		vec3 flow_position = (v_position - radial * v_height) / 16.0 + radial * v_height / 350.0;
		float streak = smoothstep(0.15, 0.70, patch(flow_position)) * 0.10;
		strata_color *= 1.0 - streak;
		float upward = 1.0 - smoothstep(0.13, 0.38, v_slope);
		strata_color = mix(strata_color, mix(vec3(0.285, 0.233, 0.119), vec3(0.196, 0.233, 0.100), patch(v_position / 30.0) * 0.5 + 0.5), upward * 0.45);
		// 峡谷台面使用土与草的色块，冰川仍由独立通道保持原色。
		c = mix(c, strata_color, max(v_marks.r, v_marks.b));
		vec3 ice = vec3(0.624, 0.791, 0.855) * (0.95 + smoothstep(0.92, 0.98, sin(v_position.x * 0.035 + v_position.z * 0.012)) * 0.05);
		c = mix(c, ice, v_marks.g);
	}
	// 地貌色先合成，再叠加笔触，避免峡谷和冰川覆盖中近景细节。
	float camera_distance = distance(v_position + planet_center, CAMERA_POSITION_WORLD);
	float middle_detail = 1.0 - smoothstep(160.0, 400.0, camera_distance);
	if (middle_detail > 0.001) {
		vec3 weights = pow(abs(v_normal), vec3(4.0));
		weights /= max(weights.x + weights.y + weights.z, 0.001);
		float brush = 0.0;
		if (exposed < 0.95) {
			vec3 grass_samples = vec3(0.5);
			if (weights.x > 0.06) { grass_samples.x = texture(ground_paint, v_position.yz / 42.0).r; }
			if (weights.y > 0.06) { grass_samples.y = texture(ground_paint, v_position.xz / 42.0).r; }
			if (weights.z > 0.06) { grass_samples.z = texture(ground_paint, v_position.xy / 42.0).r; }
			float grass_brush = dot(grass_samples, weights);
			brush = (grass_brush - 0.5) * 1.7 * (1.0 - exposed);
		}
		if (exposed > 0.05) {
			vec3 stone_samples = vec3(0.76);
			if (weights.x > 0.06) { stone_samples.x = texture(rock_paint, v_position.yz / 24.0).r; }
			if (weights.y > 0.06) { stone_samples.y = texture(rock_paint, v_position.xz / 24.0).r; }
			if (weights.z > 0.06) { stone_samples.z = texture(rock_paint, v_position.xy / 24.0).r; }
			float stone_brush = dot(stone_samples, weights);
			brush += (stone_brush - 0.76) * 0.9 * exposed;
		}
		c *= 1.0 + brush * middle_detail * (1.0 - snow_line);
		vec3 rock_temperature = mix(vec3(0.86, 0.94, 1.04), vec3(1.06, 1.015, 0.91), smoothstep(-0.15, 0.5, dot(v_normal, sun_dir)));
		c *= mix(vec3(1.0), rock_temperature, exposed * middle_detail);
	}
	if (terrestrial && middle_detail > 0.001 && exposed < 0.99 && snow_line < 0.99) {
		vec3 side = normalize(cross(normalize(v_position), wind_dir));
		float wave = sin(dot(v_position, wind_dir) / 9.0 - weather_time * 2.3 + sin(dot(v_position, side) / 17.0) * 1.6);
		float sweep = smoothstep(0.5, 0.95, wave) * (1.0 - exposed) * (1.0 - snow_line);
		c *= 1.0 + sweep * 0.065 * middle_detail * wind_speed;
	}
	float near_detail = 1.0 - smoothstep(35.0, 160.0, distance(v_position + planet_center, CAMERA_POSITION_WORLD));
	if (terrestrial && near_detail > 0.0) {
		// 自绘短笔触采用三轴投影，近景补充细节，远景淡出以避免闪烁和规则网格。
		vec3 weights = pow(abs(normalize(v_position)), vec3(4.0));
		weights /= weights.x + weights.y + weights.z;
		float brush = dot(vec3(texture(ground_paint, v_position.yz / 9.0).r, texture(ground_paint, v_position.xz / 9.0).r, texture(ground_paint, v_position.xy / 9.0).r), weights);
		c *= 1.0 + (brush * 2.0 - 1.0) * near_detail * 0.25 * (1.0 - snow_line);
	}
	c *= 1.0 - wetness * 0.2;
	float haze = mist_amount(v_position + planet_center, distance(v_position + planet_center, CAMERA_POSITION_WORLD));
	ALBEDO = c * (1.0 - haze);
	ROUGHNESS = 1.0;
	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.15;
	EMISSION = mist_color * haze;
}
