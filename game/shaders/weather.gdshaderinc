// 风与云影：由 SkyDirector 设置全局参数，地形、植被和探索者共用同一套计算
// 包含本文件的着色器需在之前定义 CLOUD_SHADE，并在顶点或片元中写入 v_sunlit

global uniform vec3 sun_dir;
global uniform vec3 focus_center;
global uniform vec3 wind_dir;
global uniform float wind_speed;
global uniform vec3 cloud_offset;
global uniform float cloud_cover;
global uniform float cloud_shadow;

// 云影系数：1 为全受光，越小表示越处于云影中
varying float v_sunlit;

float weather_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float weather_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(weather_hash(i), weather_hash(i + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(weather_hash(i + vec3(0.0, 1.0, 0.0)), weather_hash(i + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(weather_hash(i + vec3(0.0, 0.0, 1.0)), weather_hash(i + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(weather_hash(i + vec3(0.0, 1.0, 1.0)), weather_hash(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// 沿太阳方向把地面点投到约 1100 米高的云层，太阳越低影子拉得越远
float cloud_sunlit(vec3 world_position) {
	if (cloud_shadow <= 0.001) {
		return 1.0;
	}
	vec3 relative = world_position - focus_center;
	vec3 up = normalize(relative);
	float sun_up = max(dot(up, sun_dir), 0.15);
	vec3 p = (relative + sun_dir * (1100.0 / sun_up) + cloud_offset) / 700.0;
	float shape = weather_noise(p) * 0.64 + weather_noise(p * 2.7 + vec3(7.1, 3.3, 5.9)) * 0.36;
	float threshold = mix(0.66, 0.42, cloud_cover);
	float cover = smoothstep(threshold - 0.05, threshold + 0.06, shape);
	return 1.0 - cover * cloud_shadow;
}

// 风的世界坐标位移：整体朝风向倾斜，阵风以波的形式扫过地面，另有逐株的细小抖动
vec3 wind_push(vec3 world_position, float phase) {
	vec3 relative = world_position - focus_center;
	vec3 side = normalize(cross(normalize(relative), wind_dir));
	float along = dot(relative, wind_dir);
	float wave = sin(along / 9.0 - TIME * 2.3 + sin(dot(relative, side) / 17.0) * 1.6);
	float gust = 0.5 + 0.5 * wave;
	float flutter = sin(TIME * 3.4 + phase) * 0.22;
	return (wind_dir * (0.35 + gust * 0.65) + side * flutter * 0.4) * wind_speed;
}
