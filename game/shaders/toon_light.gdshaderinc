// 投影里保留的直射光比例，只在黄金时段由 SkyDirector 调高，模拟低角度时天空和地面的暖色反光
global uniform float shadow_fill;
global uniform vec3 sky_up;
global uniform vec3 shadow_up;
global uniform vec3 shadow_side;
global uniform float rim_strength;
varying float toon_distance;

// 卡通光照：亮面、半亮、暗面三档，交界处保留一点柔和
// 暗面保留环境光和按朝向区分的反光，色温随时段变化。
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.05, ndl);
	float tier = mix(0.72, 1.0, smoothstep(0.30, 0.36, ndl));
	float shadow = smoothstep(0.0, 1.0, ATTENUATION);
#ifdef CLOUD_SHADE
	// 云影只削弱直射光，暗面仍由环境色托底
	shadow *= v_sunlit;
#endif
	vec3 direct = vec3(lit * tier * max(shadow, shadow_fill));
	// 朝上的暗面接收天空色，侧面接收地面反光；局部灯光不能重复叠加环境补光。
	if (LIGHT_IS_DIRECTIONAL) {
		float upward = smoothstep(-0.2, 0.8, dot(NORMAL, mat3(VIEW_MATRIX) * sky_up));
		vec3 bounce = mix(shadow_side, shadow_up, upward);
		direct += bounce * (1.0 - lit * shadow) * 0.22;
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 7.0);
		direct += vec3(rim * lit * shadow * rim_strength * (1.0 - smoothstep(40.0, 280.0, toon_distance)));
	}
	// 窄暖色过渡带仅跟随直射光，不在背光轮廓产生自发光。
	float transition = smoothstep(0.0, 0.025, ndl) * (1.0 - smoothstep(0.045, 0.08, ndl));
	direct *= mix(vec3(1.0), vec3(1.08, 0.97, 0.88), transition * shadow);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * direct;
}
