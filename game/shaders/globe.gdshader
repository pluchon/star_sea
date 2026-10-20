shader_type spatial;
render_mode cull_back, specular_disabled;

// 地图里的立体地球仪：用全球高度图按海拔分层设色，顶点按海拔外推并适度夸大，看得出山脉的起伏。
uniform sampler2D height_map : filter_linear, repeat_enable;
uniform float relief = 0.00004;
uniform vec2 map_step = vec2(0.0009765625, 0.001953125);

varying vec3 v_direction;

vec2 map_uv(vec3 direction) {
	return vec2(atan(direction.z, direction.x) / TAU + 0.5, 0.5 - asin(clamp(direction.y, -1.0, 1.0)) / PI);
}

vec3 altitude_color(float height) {
	if (height < 0.0) {
		return mix(vec3(0.09, 0.22, 0.30), vec3(0.29, 0.53, 0.55), smoothstep(-420.0, 0.0, height));
	}
	vec3 pigment = mix(vec3(0.48, 0.64, 0.42), vec3(0.69, 0.73, 0.45), smoothstep(0.0, 400.0, height));
	pigment = mix(pigment, vec3(0.68, 0.52, 0.35), smoothstep(400.0, 1000.0, height));
	pigment = mix(pigment, vec3(0.55, 0.51, 0.47), smoothstep(1000.0, 1700.0, height));
	return mix(pigment, vec3(0.92, 0.92, 0.83), smoothstep(1700.0, 2400.0, height));
}

void vertex() {
	v_direction = normalize(VERTEX);
	float height = textureLod(height_map, map_uv(v_direction), 0.0).r;
	VERTEX = v_direction * (1.0 + max(height, 0.0) * relief);
}

void fragment() {
	vec2 uv = map_uv(normalize(v_direction));
	vec2 texel = texture(height_map, uv).rg;
	vec3 pigment = altitude_color(texel.r);
	pigment = mix(pigment, vec3(0.30, 0.56, 0.62), smoothstep(0.05, 0.4, texel.g));
	// 用相邻像素的高差做山体阴影，让平面贴图也有立体感。
	float east = texture(height_map, uv + vec2(map_step.x, 0.0)).r - texture(height_map, uv - vec2(map_step.x, 0.0)).r;
	float north = texture(height_map, uv - vec2(0.0, map_step.y)).r - texture(height_map, uv + vec2(0.0, map_step.y)).r;
	float shade = clamp(0.5 + (east * -0.6 + north * 0.6) / 900.0, 0.0, 1.0);
	ALBEDO = pigment * mix(0.82, 1.12, shade * step(0.0, texel.r) + 0.5 * step(texel.r, 0.0));
	ROUGHNESS = 1.0;
}
