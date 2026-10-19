shader_type sky;

global uniform vec3 sun_dir;
global uniform float star_visibility;
global uniform vec3 sky_up;
global uniform float surface_sky;

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
		col = col * star_visibility + sun_color * (sun * 8.0 + halo);
		float elevation = dot(dir, sky_up);
		float day = smoothstep(-0.08, 0.18, dot(sky_up, sun_dir));
		// 云层使用球面方向，不随浮动原点偏移；高空逐渐消失。
		float cloud_shape = fbm(dir * vec3(8.0, 13.0, 8.0) + vec3(TIME * 0.003, 0.0, 0.0));
		float clouds = smoothstep(0.49, 0.62, cloud_shape) * smoothstep(0.04, 0.22, elevation) * (1.0 - smoothstep(0.55, 0.90, elevation));
		vec3 cloud_color = mix(vec3(0.17, 0.18, 0.32), mix(vec3(1.0, 0.65, 0.46), vec3(0.83, 0.91, 0.97), day), smoothstep(-0.18, 0.04, dot(sky_up, sun_dir)));
		col = mix(col, cloud_color, clouds * surface_sky * 0.72);
		COLOR = col;
	}
}
