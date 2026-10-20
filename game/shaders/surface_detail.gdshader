shader_type spatial;
render_mode cull_disabled;

#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
global uniform float rim_strength;

uniform float wind_strength = 0.0;
uniform bool is_grass = false;
uniform sampler2D bark_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaf_color : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 v_color;
varying float v_root;
varying float v_surface;
varying float v_distance;
varying float v_up;
varying float v_moss;
varying float v_haze;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	vec3 root_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (wind_strength > 0.0) {
		// 位移在世界坐标里算出，再换回实例的局部坐标，使整片植被朝同一风向摆动
		mat3 model = mat3(MODEL_MATRIX);
		vec3 push = wind_push(root_world, phase + VERTEX.y * 0.35) * UV2.x * wind_strength;
		VERTEX += transpose(model) * push / dot(model[0], model[0]);
	}
	v_sunlit = cloud_sunlit(root_world);
	v_color = COLOR.rgb;
	v_root = is_grass ? smoothstep(0.0, 0.35, VERTEX.y) : 1.0;
	v_surface = UV2.y;
	v_up = NORMAL.y;
	v_moss = INSTANCE_CUSTOM.g;
	vec3 vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_distance = distance(vertex_world, CAMERA_POSITION_WORLD);
	// 雾按顶点的实际高度计算，高大的石柱和树冠上部不会整体被雾染白。
	v_haze = mist_amount(vertex_world, v_distance);
}

void fragment() {
	ALBEDO = v_color * mix(0.68, 1.0, v_root);
	float detail = 1.0 - smoothstep(35.0, 150.0, v_distance);
	if (detail > 0.01 && v_surface > 0.5 && v_surface < 2.5) {
		bool stone = v_surface > 1.5;
		vec3 sample_color = stone ? texture(rock_color, UV * 0.75).rgb : texture(bark_color, UV).rgb;
		// 自绘色块只补充近景层次，远景逐渐恢复固有色。
		float pigment = mix(0.88, 1.08, smoothstep(0.40, 0.78, sample_color.r));
		ALBEDO *= mix(1.0, pigment, detail);
		if (stone) {
			float moss = smoothstep(-0.04, 0.08, sample_color.g - sample_color.r) * smoothstep(0.05, 0.6, v_up) * v_moss;
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.68, 0.88, 0.48), moss * detail * 0.65);
		}
	} else if (v_surface > 2.5) {
		float pigment = texture(leaf_color, UV * vec2(2.0, 1.0)).r;
		ALBEDO *= mix(1.0, mix(0.93, 1.06, smoothstep(0.40, 0.78, pigment)), detail);
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO *= (1.0 - wetness * 0.15) * (1.0 - v_haze);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	EMISSION = ALBEDO * rim * rim_strength * 0.6 + mist_color * v_haze;
}
