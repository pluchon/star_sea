shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
global uniform vec3 focus_center;
global uniform float focus_radius;
varying vec3 planet_view_center;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	planet_view_center = (VIEW_MATRIX * vec4(focus_center, 1.0)).xyz;
}

float linear_depth(vec2 uv, vec2 inverse_projection) {
	float depth = textureLod(depth_texture, uv, 0.0).r;
	return 1.0 / (depth * inverse_projection.x + inverse_projection.y);
}

void fragment() {
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec2 inverse_projection = vec2(INV_PROJECTION_MATRIX[2].w, INV_PROJECTION_MATRIX[3].w);
	float depth = linear_depth(SCREEN_UV, inverse_projection);
	if (raw_depth <= 0.000001 || depth > 400.0) {
		discard;
	}
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec3 point = view.xyz / view.w;
	// 海床不应隔着透明水面出现线条。天空、回声和粒子不写入不透明深度。
	if (length(point - planet_view_center) < focus_radius + 0.15) {
		discard;
	}
	vec2 pixel = vec2(1.0) / VIEWPORT_SIZE;
	// 1080p 下近景两像素、中景一点五像素；更高分辨率保持相同视角宽度。
	float width = mix(2.0, 1.5, smoothstep(60.0, 200.0, depth)) * VIEWPORT_SIZE.y / 1080.0;
	float edge = 0.0;
	vec3 neighbors[2];
	// 四方向只在近侧物体内部落线，避免只画右边和下边而断开轮廓。
	for (int i = 0; i < 4; i++) {
		vec2 axis = i % 2 == 0 ? vec2(1, 0) : vec2(0, 1);
		vec2 offset = axis * (i < 2 ? 1.0 : -1.0) * pixel * width;
		vec2 uv = clamp(SCREEN_UV + offset, vec2(0), vec2(1));
		float neighbor = linear_depth(uv, inverse_projection);
		float depth_edge = smoothstep(0.018, 0.045, (neighbor - depth) / max(depth, 1.0));
		if (depth < 45.0 && i < 2) {
			vec4 ray = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
			neighbors[i] = ray.xyz / max(-ray.z, 0.000001) * neighbor;
		}
		edge = max(edge, depth_edge);
	}
	// 从深度恢复表面法线，避免为全场景增加法线预通道；差分保留建筑折角。
	// 深度法线在亚像素草叶和远处小三角形上不稳定，只补充近处的明显折角。
	float normal_edge = 0.0;
	if (depth < 45.0) {
		vec3 normal = normalize(cross(neighbors[0] - point, neighbors[1] - point));
		float normal_change = length(dFdx(normal)) + length(dFdy(normal));
		normal_edge = smoothstep(0.65, 1.25, normal_change) * (1.0 - smoothstep(15.0, 45.0, depth));
	}
	edge = max(edge, normal_edge * 0.25);
	// 外轮廓保留原像素三成明度，折角较淡；不复制整帧颜色。
	ALBEDO = vec3(0.0);
	ALPHA = 0.70 * edge * (1.0 - smoothstep(200.0, 400.0, depth));
}
