shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float presence : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
varying vec3 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
	float noise = fract(sin(dot(floor(local_point * 24.0), vec3(12.9898, 78.233, 31.37))) * 43758.5453);
	float dissolve = smoothstep(noise - 0.12, noise + 0.12, presence * 1.24 - 0.12);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float lines = 0.86 + 0.14 * sin(local_point.y * 170.0 - phase * 2.0);
	float flicker = 0.97 + 0.03 * sin(phase * 17.0);
	ALBEDO = vec3(0.949, 0.706, 0.353) * (0.65 + rim * 0.55);
	ALPHA = dissolve * (0.35 + rim * 0.45) * lines * flicker;
}
