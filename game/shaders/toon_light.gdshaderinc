// 卡通光照：亮面、半亮、暗面三档，交界处保留一点柔和
// 暗面只剩环境色（由 SkyDirector 设为蓝紫），所以暗部偏冷而不是发黑
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.05, ndl);
	float tier = mix(0.72, 1.0, smoothstep(0.30, 0.36, ndl));
	float shadow = smoothstep(0.0, 1.0, ATTENUATION);
#ifdef CLOUD_SHADE
	// 云影只削弱直射光，暗面仍由环境色托底
	shadow *= v_sunlit;
#endif
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * tier * shadow;
}
