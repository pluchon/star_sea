shader_type spatial;
render_mode cull_disabled;
#include "weather.gdshaderinc"
uniform float awake = 0.15;
uniform float echo_rise = -1.0;
uniform bool hide_base = false;
varying vec3 stable_position;
void vertex() { stable_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - focus_center; }
void fragment() {
	if (hide_base && UV.y < 300.0) { discard; }
	float collar = 1.0 - step(3.0, abs(mod(UV.y + 60.0, 120.0) - 60.0));
	float ring = 1.0 - step(3.0, abs(mod(UV.y + 300.0, 600.0) - 300.0));
	float line = 1.0 - smoothstep(0.0015, 0.003, abs(fract(UV.x * 4.0 + 0.5) - 0.5));
	vec3 stone = vec3(0.72, 0.69, 0.61);
	ALBEDO = mix(stone, vec3(0.16, 0.32, 0.27), collar);
	float response = (echo_rise >= 0.0 && UV.y <= echo_rise * 6200.0) ? 1.0 : 0.0;
	EMISSION = vec3(1.0, 0.61, 0.20) * (ring + line * 0.7) * max(awake, response) * 1.8;
	ROUGHNESS = 0.85;
}
#include "toon_light.gdshaderinc"
