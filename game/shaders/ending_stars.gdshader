shader_type canvas_item;
uniform float fade = 0.0;
uniform mat3 view_rotation;
uniform vec2 view_half = vec2(1.24, 0.70);
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
float star_layer(vec3 dir, float scale, float density) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 local = fract(p) - 0.5;
	vec3 offset = (hash33(cell) - 0.5) * 0.7;
	float present = step(1.0 - density, hash13(cell + 17.0));
	float size = 0.06 + hash13(cell + 5.0) * 0.08;
	return present * smoothstep(size, 0.0, length(local - offset)) * (0.4 + 0.6 * hash13(cell + 9.0));
}
void fragment() {
	vec3 ray = normalize(view_rotation * vec3((UV.x - 0.5) * 2.0 * view_half.x, (0.5 - UV.y) * 2.0 * view_half.y, -1.0));
	float stars = star_layer(ray, 180.0, 0.10) + star_layer(ray, 420.0, 0.06) * 0.6;
	COLOR = vec4(vec3(0.003, 0.006, 0.015) + stars * vec3(0.65, 0.74, 0.84), fade);
}
