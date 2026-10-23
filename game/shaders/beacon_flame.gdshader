shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float flame_time = 0.0;
uniform float strength = 1.0;
uniform float phase = 0.0;
uniform bool detached = false;
void vertex() {
 float tip = 1.0 - UV.y;
 if (detached) {
  float age = fract(flame_time * 0.33 + phase * 0.27);
  VERTEX *= sin(age * PI) * 0.25;
  VERTEX.y += 1.2 + age * 1.4;
 }
 VERTEX.x += sin(flame_time * (2.2 + phase * 0.17) + phase + tip * 2.0) * 0.16 * tip;
 VERTEX.y *= 1.0 + sin(flame_time * (3.0 + phase * 0.21) + phase) * 0.09;
}
void fragment() {
 float height = 1.0 - UV.y;
 float center = 0.5 + sin(height * 8.0 - flame_time * 3.0 + phase) * 0.045 * height;
 float width = pow(max(1.0 - height, 0.0), 0.75) * 0.47;
 float edge = abs(UV.x - center);
 if (edge > width || height < 0.015) { discard; }
 float core = edge / max(width, 0.001);
 vec3 color = vec3(1.0, 0.21, 0.035);
 if (core < 0.72 && height < 0.80) { color = vec3(1.0, 0.61, 0.10); }
 if (core < 0.32 && height < 0.48) { color = vec3(1.0, 0.95, 0.68); }
 ALBEDO = color;
 EMISSION = color * strength * 1.7;
}
