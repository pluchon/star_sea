shader_type sky;

global uniform vec3 sun_dir;
global uniform float star_visibility;
global uniform vec3 sky_up;
global uniform float surface_sky;
global uniform float cloud_cover;
global uniform float rain;
global uniform vec3 moon_dir;
global uniform float aurora;
global uniform float weather_time;

uniform vec3 nebula_a : source_color = vec3(0.10, 0.06, 0.22);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.14, 0.24);
uniform vec3 space_base : source_color = vec3(0.004, 0.006, 0.016);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// 一层星点：把方向放大到网格里，每格最多一颗星，位置和亮度随机
float star_layer(vec3 dir, float scale, float density) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	vec3 offset = (hash33(cell) - 0.5) * 0.7;
	float present = step(1.0 - density, hash13(cell + 17.0));
	float d = length(local - offset);
	float size = 0.06 + hash13(cell + 5.0) * 0.08;
	return present * smoothstep(size, 0.0, d) * (0.4 + 0.6 * hash13(cell + 9.0));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = space_base;
	} else {
		vec3 dir = EYEDIR;
		float n = fbm(dir * 2.2);
		float band = fbm(dir * 5.0 + vec3(3.1, 0.0, 1.7));
		float galaxy = exp(-pow(dot(dir, normalize(vec3(0.4, 0.7, -0.6))) * 3.8 + (n - 0.5) * 1.8, 2.0));
		vec3 nebula = mix(nebula_a, nebula_b, band) * (smoothstep(0.24, 0.75, n) + galaxy * 0.32);
		float stars = star_layer(dir, 180.0, 0.10) + star_layer(dir, 420.0, 0.06) * 0.6;
		vec3 col = space_base + nebula + vec3(stars) * 2.5;
		float sun = smoothstep(0.9994, 0.9997, dot(dir, sun_dir));
		float halo = pow(max(dot(dir, sun_dir), 0.0), 600.0) * 0.6;
		col = col * star_visibility + sun_color * (sun * 8.0 + halo) * (1.0 - rain * 0.9);
		float elevation = dot(dir, sky_up);
		float day = smoothstep(-0.08, 0.18, dot(sky_up, sun_dir));
		// 月亮：圆盘上有几块暗色月海，周围一圈淡光；白天只剩很淡的影子。
		float moon_facing = dot(dir, moon_dir);
		if (moon_facing > 0.99) {
			float disc = smoothstep(0.99955, 0.99970, moon_facing);
			float maria = value_noise(dir * 900.0) * 0.6 + value_noise(dir * 2300.0) * 0.4;
			vec3 moon = vec3(0.95, 0.94, 0.86) * mix(0.72, 1.0, smoothstep(0.35, 0.6, maria));
			float glow = pow(max(moon_facing, 0.0), 2200.0) * 0.18;
			float strength = mix(1.0, 0.18, day) * (1.0 - rain * 0.85);
			col = mix(col, moon * 1.6, disc * strength) + vec3(0.62, 0.70, 0.90) * glow * strength;
		}
		// 极光：只在夜里出现在天空较高处，竖直的光幕缓慢流动，下绿上紫。
		if (aurora > 0.001 && elevation > 0.05) {
			vec3 flow = dir * vec3(2.6, 0.6, 2.6) + vec3(weather_time * 0.012, 0.0, weather_time * 0.008);
			float curtain = smoothstep(0.52, 0.78, fbm(flow + vec3(0.0, fbm(dir * 3.0 + weather_time * 0.01) * 1.5, 0.0)));
			float band = smoothstep(0.08, 0.3, elevation) * (1.0 - smoothstep(0.55, 0.9, elevation));
			vec3 aurora_color = mix(vec3(0.25, 1.0, 0.62), vec3(0.72, 0.36, 0.95), smoothstep(0.25, 0.7, elevation));
			col += aurora_color * curtain * band * aurora * star_visibility * surface_sky * 0.55;
		}
		// 云层使用球面方向，不随浮动原点偏移；高空逐渐消失。
		vec3 cloud_point = dir / max(elevation, 0.12) * 3.4 + vec3(weather_time * 0.005, 0.0, 0.0);
		float cloud_shape = fbm(cloud_point);
		// 云量越大，成云的阈值越低；晨的基础云量 0.45 时与原来的天空一致。
		float threshold = 0.51 + (0.45 - cloud_cover) * 0.32;
		float clouds = smoothstep(threshold, threshold + 0.14, cloud_shape) * smoothstep(0.04, 0.20, elevation);
		vec3 cloud_color = mix(vec3(0.17, 0.18, 0.32), mix(vec3(1.0, 0.65, 0.46), vec3(0.83, 0.91, 0.97), day), smoothstep(-0.18, 0.04, dot(sky_up, sun_dir)));
		cloud_color *= mix(0.78, 1.05, smoothstep(0.50, 0.70, cloud_shape));
		// 下雨时云变成低沉的灰色，天空整体也褪成灰蓝。
		cloud_color = mix(cloud_color, vec3(0.52, 0.55, 0.60) * mix(0.25, 1.0, day), rain * 0.75);
		col = mix(col, cloud_color, clouds * surface_sky * 0.92);
		col = mix(col, vec3(0.50, 0.54, 0.60) * mix(0.18, 1.0, day), rain * 0.55 * surface_sky * smoothstep(-0.05, 0.1, elevation));
		COLOR = col;
	}
}
