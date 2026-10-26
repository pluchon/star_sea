class_name RenderPalette
extends Resource

# 色板保存显示空间颜色；传入光照着色器前统一转换为线性空间。
@export var periods: Array[Dictionary] = []


func grade(color: Color, index: int) -> Color:
	var period: Dictionary = periods[index]
	var luminance: float = color.get_luminance()
	var shadow: Color = period["lift"]
	var gain: Color = period["gain"]
	var saturation: float = period["saturation"]
	var result: Color = Color(luminance, luminance, luminance).lerp(color, saturation)
	# 阴影和亮部采用不同色温，避免一维曲线把所有颜色一并染色。
	var dark: float = pow(1.0 - luminance, 2.0)
	for channel: int in 3:
		var value: float = result[channel]
		var curve: float = lerpf(value, value * value * (3.0 - 2.0 * value), 0.12)
		result[channel] = clampf(curve * gain[channel] + shadow[channel] * dark, 0.0, 1.0)
	result.a = 1.0
	return result


func daylight(sun_height: float, rising: bool) -> Vector3:
	if sun_height < -0.12:
		return Vector3(3, 3, 0)
	var golden: int = 0 if rising else 2
	if sun_height < 0.04:
		return Vector3(3, golden, smoothstep(-0.12, 0.04, sun_height))
	return Vector3(golden, 1, smoothstep(0.04, 0.38, sun_height))


func tint(key: String, phase: Vector3, cave: float) -> Color:
	var a: Color = periods[int(phase.x)][key]
	var b: Color = periods[int(phase.y)][key]
	return a.lerp(b, phase.z).lerp(periods[4][key], cave)
