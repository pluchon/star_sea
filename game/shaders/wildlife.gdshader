shader_type spatial;
render_mode cull_disabled;

#define CLOUD_SHADE
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/toon_light.gdshaderinc"
global uniform float rim_strength;

// 鸟群：UV2.x 是离身体中线的距离，越靠翼尖扇得越高；INSTANCE_CUSTOM.r 是每只鸟的扇翅相位。
// 鹿：UV2.x 为零，不受扇翅影响。
uniform float flap_speed = 0.0;
// 鹿的各部分用同一个材质，颜色按实例单独设置。
instance uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	if (flap_speed > 0.0) {
		float phase = INSTANCE_CUSTOM.r * 6.28318;
		// 扇几下后滑翔一会儿，鸟群不会整齐划一地扑腾。
		float glide = smoothstep(-0.2, 0.6, sin(TIME * 0.7 + phase * 1.3));
		VERTEX.y += sin(TIME * flap_speed + phase) * UV2.x * 0.55 * glide;
	}
	v_sunlit = cloud_sunlit((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	EMISSION = ALBEDO * rim * rim_strength;
}
