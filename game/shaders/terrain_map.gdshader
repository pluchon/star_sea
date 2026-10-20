shader_type canvas_item;
render_mode unshaded;
uniform sampler2D height_map : filter_linear, repeat_disable;

uniform vec2 map_step = vec2(0.0009765625, 0.001953125);
uniform vec2 meters_per_pixel = vec2(245.437, 245.437);
uniform float contour_interval = 100.0;
uniform bool global_map = true;
uniform float zoom = 1.0;
uniform vec2 center = vec2(0.5);

float elevation(vec2 uv) {
	vec2 sample_uv = global_map ? vec2(fract(uv.x), clamp(uv.y, map_step.y * 0.5, 1.0 - map_step.y * 0.5)) : clamp(uv, vec2(0.0), vec2(1.0));
	return texture(height_map, sample_uv).r;
}

vec3 altitude_color(float height) {
	if (height < 0.0) {
		return mix(vec3(0.09, 0.22, 0.30), vec3(0.29, 0.53, 0.55), smoothstep(-420.0, 0.0, height));
	}
	vec3 pigment = mix(vec3(0.48, 0.64, 0.42), vec3(0.69, 0.73, 0.45), smoothstep(0.0, 400.0, height));
	pigment = mix(pigment, vec3(0.68, 0.52, 0.35), smoothstep(400.0, 1000.0, height));
	pigment = mix(pigment, vec3(0.55, 0.51, 0.47), smoothstep(1000.0, 1700.0, height));
	pigment = mix(pigment, vec3(0.92, 0.92, 0.83), smoothstep(1700.0, 2400.0, height));
	return mix(pigment, vec3(0.96, 0.98, 1.0), smoothstep(2400.0, 4000.0, height));
}

float inland_water(vec2 uv) {
	vec2 sample_uv = global_map ? vec2(fract(uv.x), clamp(uv.y, map_step.y * 0.5, 1.0 - map_step.y * 0.5)) : clamp(uv, vec2(0.0), vec2(1.0));
	return texture(height_map, sample_uv).g;
}

void fragment() {
	vec2 uv = center + (UV - 0.5) / zoom;
	float height = elevation(uv);
	float dx = elevation(uv + vec2(map_step.x, 0.0)) - elevation(uv - vec2(map_step.x, 0.0));
	float dy = elevation(uv + vec2(0.0, map_step.y)) - elevation(uv - vec2(0.0, map_step.y));
	float latitude_scale = global_map ? max(cos((0.5 - uv.y) * PI), 0.08) : 1.0;
	vec3 normal = normalize(vec3(-dx / (meters_per_pixel.x * 2.0 * latitude_scale), 1.0, -dy / (meters_per_pixel.y * 2.0)) * vec3(2.2, 1.0, 2.2));
	float illumination = 0.68 + 0.38 * max(dot(normal, normalize(vec3(-0.6, 0.85, -0.55))), 0.0);
	vec3 pigment = altitude_color(height) * illumination;
	float level = height / contour_interval;
	float line = abs(fract(level + 0.5) - 0.5) / max(fwidth(level), 0.001);
	float contour = 1.0 - smoothstep(0.35, 1.05, line);
	pigment = mix(pigment, pigment * 0.66, contour * 0.48 * step(2.0, height));
	float coast = 1.0 - smoothstep(0.7, 1.8, abs(height) / max(fwidth(height), 0.02));
	pigment = mix(pigment, vec3(0.89, 0.84, 0.62), coast * 0.65);
	// 河湖用比海略浅的蓝绿色，水深越大颜色越深。
	float water = inland_water(uv);
	pigment = mix(pigment, mix(vec3(0.36, 0.62, 0.66), vec3(0.20, 0.42, 0.52), smoothstep(1.0, 12.0, water)) * illumination, smoothstep(0.05, 0.4, water));
	COLOR = vec4(pigment, 1.0);
}
