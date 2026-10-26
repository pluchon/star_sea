// 不等宽层理与竖向流痕供地形和峡谷岩石共用，避免固定周期白线。
float strata_hash(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}

float strata_noise(float value) {
	float cell = floor(value);
	return mix(strata_hash(cell), strata_hash(cell + 1.0), smoothstep(0.0, 1.0, fract(value)));
}

vec3 strata_pigment(vec3 position, float altitude, float upward) {
	vec3 radial = normalize(position);
	vec3 lateral = position - radial * altitude;
	float bend = sin(dot(lateral, vec3(0.0017, 0.0011, 0.0023))) * 9.0;
	float height = altitude + bend + strata_noise(altitude / 95.0) * 17.0;
	float band = strata_noise(height / 19.0 + strata_noise(height / 67.0) * 2.0);
	vec3 pigment = mix(vec3(0.673, 0.571, 0.371), vec3(0.479, 0.376, 0.254), 0.25 + band * 0.30);
	pigment = mix(pigment, vec3(0.434, 0.195, 0.102), smoothstep(0.75, 0.95, strata_noise(height / 31.0)) * 0.12);
	float streak = strata_noise(dot(lateral, vec3(0.061, 0.093, 0.057)) + altitude / 380.0);
	pigment *= 1.0 - smoothstep(0.65, 0.90, streak) * 0.10;
	return mix(pigment, mix(vec3(0.285, 0.233, 0.119), vec3(0.196, 0.233, 0.100), band), upward * 0.45);
}
