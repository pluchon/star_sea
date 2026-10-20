class_name SkyDirector
extends Node

# 各星球的云量与风力，顺序与 Planet.profile 一致：晨、烬、霜。
const CLOUD_COVER: Array[float] = [0.45, 0.12, 0.32]
const WIND_BASE: Array[float] = [0.75, 1.0, 0.85]

var sun_direction: Vector3 = Vector3(0.35, 0.35, -0.87).normalized()
var time_paused: bool = false
# 当前地面上的风向（世界坐标切向量）与风力，供探索者的围巾等脚本读取。
var wind_direction: Vector3 = Vector3.RIGHT
var wind_strength: float = 0.0
# 天气：0 为晴，0.5 为多云，1 为雨；在几分钟的尺度上缓慢变化。验收机位暂停时间时天气也保持不变。
var weather: float = 0.0
var rain: float = 0.0
var moon_direction: Vector3 = Vector3.DOWN
var _weather_target: float = 0.0
var _weather_hold: float = 300.0
var _weather_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wetness: float = 0.0
var _mist: float = 0.0
var _previous_sun_height: float = 0.0
var _rain_curtain: MeshInstance3D
var _weather_time: float = 0.0
var _cloud_offset: Vector3 = Vector3.ZERO
var _grade_gradient: Gradient
var _grade_key: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
var _planet: Planet
var _sun: DirectionalLight3D
var _environment: Environment
var _camera: Camera3D


func _ready() -> void:
	# 暂停时仍更新原点偏移和大气中心，只停止太阳推进。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_tree().get_first_node_in_group("planets") as Planet
	_sun = get_parent().get_node("Sun") as DirectionalLight3D
	_environment = (get_parent().get_node("WorldEnvironment") as WorldEnvironment).environment
	var up: Vector3 = _planet.site["direction"]
	# 太阳轨道保持在赤道平面，避免高纬度出生点因初始偏角永久处于白昼。
	sun_direction = Vector3(up.x, 0.0, up.z).normalized().rotated(Vector3.UP, -0.3)
	add_to_group("sky_director")
	_grade_gradient = Gradient.new()
	var lut: GradientTexture1D = GradientTexture1D.new()
	lut.gradient = _grade_gradient
	lut.width = 64
	_environment.adjustment_enabled = true
	_environment.adjustment_color_correction = lut
	_weather_rng.seed = 20261020
	_rain_curtain = _build_rain_curtain()
	get_parent().add_child.call_deferred(_rain_curtain)
	_update_environment()


func set_sun_altitude(up: Vector3, horizontal: Vector3, angle_degrees: float) -> void:
	var tangent: Vector3 = (horizontal - up * horizontal.dot(up)).normalized()
	var angle: float = deg_to_rad(angle_degrees)
	sun_direction = (up * sin(angle) + tangent * cos(angle)).normalized()
	_update_environment()


func _process(delta: float) -> void:
	if not get_tree().paused:
		# 风和云在暂停时间推进时照常流动，验收机位固定太阳但画面仍然是活的。
		_weather_time += delta
		_cloud_offset -= wind_direction * wind_strength * 14.0 * delta
	if not time_paused and not get_tree().paused:
		var multiplier: float = 60.0 if Input.is_action_pressed("time_fast") else 1.0
		sun_direction = sun_direction.rotated(Vector3.UP, delta * TAU / 1200.0 * multiplier)
		_advance_weather(delta * multiplier)
	_update_environment()


func _advance_weather(delta: float) -> void:
	# 每段天气持续三到七分钟；一半时间晴，三成多云，两成下雨。转换用一分半钟左右慢慢过渡。
	_weather_hold -= delta
	if _weather_hold <= 0.0:
		var roll: float = _weather_rng.randf()
		_weather_target = 0.0 if roll < 0.5 else (0.5 if roll < 0.8 else 1.0)
		_weather_hold = _weather_rng.randf_range(180.0, 420.0)
	weather = move_toward(weather, _weather_target, delta / 90.0)
	# 地面雨中逐渐变湿，雨停后用更长时间变干。
	var wet_target: float = smoothstep(0.7, 1.0, weather)
	_wetness = move_toward(_wetness, wet_target, delta / (40.0 if wet_target > _wetness else 160.0))


func _update_environment() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	_planet = Planet.nearest(get_tree(), _camera.global_position)
	var offset: Vector3 = _camera.global_position - _planet.global_position
	var up: Vector3 = offset.normalized()
	var altitude: float = offset.length() - _planet.radius
	var sun_height: float = up.dot(sun_direction)
	var day: float = smoothstep(-0.12, 0.18, sun_height)
	var space: float = smoothstep(_planet.atmosphere_height * 0.5, _planet.atmosphere_height * 1.5, altitude)
	RenderingServer.global_shader_parameter_set("sun_dir", sun_direction)
	RenderingServer.global_shader_parameter_set("sky_up", up)
	RenderingServer.global_shader_parameter_set("surface_sky", 1.0 - space)
	RenderingServer.global_shader_parameter_set("star_visibility", maxf(1.0 - day, space))
	# 只有晨会下雨；其他星球的天气只改变云量。
	rain = smoothstep(0.7, 1.0, weather) if _planet.profile == 0 else 0.0
	var overcast: float = smoothstep(0.2, 0.9, weather) * (1.0 - space)
	# 月亮大致在太阳对面，略偏开一些，避免每晚都是月全食的位置。
	moon_direction = (-sun_direction).rotated(Vector3.UP, 0.35)
	moon_direction = (moon_direction + Vector3.UP * 0.3).normalized()
	var moon_height: float = up.dot(moon_direction)
	# 太阳落下后同一盏平行光改由月亮的方向照射，冷色、很弱，夜里也能看出地形的轮廓。
	var moonlight: float = smoothstep(-0.08, -0.16, sun_height) * smoothstep(-0.02, 0.15, moon_height) * (1.0 - space) * (1.0 - rain * 0.7)
	var light_direction: Vector3 = sun_direction if moonlight <= 0.0 else moon_direction
	var light_up: Vector3 = Vector3.UP if absf(light_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sun.global_basis = Basis.looking_at(-light_direction, light_up)
	var sunset: Color = Color(1.0, 0.62, 0.42)
	var noon: Color = Color(1.0, 0.97, 0.92)
	_sun.light_color = sunset.lerp(noon, smoothstep(0.0, 0.35, sun_height)).lerp(noon, space)
	_sun.light_energy = lerpf(smoothstep(-0.08, 0.05, sun_height) * 1.25 * (1.0 - overcast * 0.45), 1.0, space)
	if moonlight > 0.0:
		_sun.light_color = Color(0.62, 0.72, 1.0)
		_sun.light_energy = moonlight * 0.34
	# 日出日落前后天空最亮最暖，背光的地面也应映出暖淡紫色，而不是沉成黑褐色。
	# 环境色会与地表固有色相乘，饱和的紫色乘上草绿会发黑，所以这里用低饱和的颜色并提高强度。
	var golden: float = smoothstep(-0.10, 0.02, sun_height) * (1.0 - smoothstep(0.10, 0.35, sun_height))
	var ambient: Color = Color(0.12, 0.16, 0.30).lerp(Color(0.46, 0.56, 0.72), day).lerp(Color(0.80, 0.66, 0.76), golden * 0.8)
	_environment.ambient_light_color = ambient.lerp(Color(0.08, 0.08, 0.16), space)
	# 晨的日间阴影保留蓝色环境光，并适度抬亮林下和背光山坡。
	var daytime_energy: float = 0.39 if _planet.profile == 0 else 0.32
	_environment.ambient_light_energy = lerpf(lerpf(0.18, daytime_energy, day) + golden * 0.55 + overcast * day * 0.12, 0.20, space)
	RenderingServer.global_shader_parameter_set("shadow_fill", golden * 0.32 * (1.0 - space) * (1.0 - overcast))
	RenderingServer.global_shader_parameter_set("moon_dir", moon_direction)
	RenderingServer.global_shader_parameter_set("rain", rain * (1.0 - space))
	RenderingServer.global_shader_parameter_set("wetness", _wetness if _planet.profile == 0 else 0.0)
	_rain_curtain.visible = rain > 0.01 and altitude < 2000.0
	# 晨雾：日出前后低地起雾，太阳升高后散去；下雨时也有一层薄雾。只在晨上出现。
	var rising: bool = sun_height > _previous_sun_height
	_previous_sun_height = sun_height
	var dawn: float = smoothstep(-0.12, 0.0, sun_height) * (1.0 - smoothstep(0.12, 0.32, sun_height)) * (1.0 if rising else 0.0)
	var mist_target: float = (dawn * 0.85 + rain * 0.45) * (1.0 if _planet.profile == 0 else 0.0)
	_mist = lerpf(_mist, mist_target, 0.02)
	RenderingServer.global_shader_parameter_set("mist", _mist * (1.0 - space))
	RenderingServer.global_shader_parameter_set("focus_radius", _planet.radius)
	var mist_tint: Color = Color(0.86, 0.88, 0.92).lerp(Color(0.98, 0.84, 0.78), golden).lerp(Color(0.22, 0.26, 0.36), 1.0 - day)
	RenderingServer.global_shader_parameter_set("mist_color", Vector3(mist_tint.r, mist_tint.g, mist_tint.b) * (0.75 + 0.25 * day))
	# 极光只在晨的晴朗夜里出现，强弱以十几分钟为周期起伏，有的夜里几乎看不见。
	var aurora_cycle: float = clampf(sin(_weather_time / 700.0) * 0.8 + 0.2, 0.0, 1.0)
	var aurora_value: float = (1.0 - smoothstep(-0.2, -0.08, sun_height)) * aurora_cycle * (1.0 - overcast) * (1.0 if _planet.profile == 0 else 0.0)
	RenderingServer.global_shader_parameter_set("aurora", aurora_value)
	_update_weather(up, altitude, day)
	_update_grade(sun_height, space)
	for node: Node in get_tree().get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		if planet.atmosphere_material != null:
			planet.atmosphere_material.set_shader_parameter("planet_center", planet.global_position)


func _update_weather(up: Vector3, altitude: float, day: float) -> void:
	# 风向在当地切平面内缓慢摆动，风力有几分钟一次的起伏，不做随机突变。
	var heading: float = sin(_weather_time / 310.0) * 0.9 + sin(_weather_time / 83.0) * 0.25
	wind_direction = SurfaceSites.tangent_forward(up).rotated(up, heading)
	var swell: float = 0.8 + sin(_weather_time / 57.0) * 0.12 + sin(_weather_time / 23.0) * 0.08
	wind_strength = WIND_BASE[_planet.profile] * swell
	# 云影在高空淡出：从太空看不到云层，地面也不应留下影子。
	var shadow: float = 0.5 * day * (1.0 - smoothstep(2500.0, 6000.0, altitude))
	RenderingServer.global_shader_parameter_set("focus_center", _planet.global_position)
	RenderingServer.global_shader_parameter_set("wind_dir", wind_direction)
	RenderingServer.global_shader_parameter_set("wind_speed", wind_strength)
	RenderingServer.global_shader_parameter_set("cloud_offset", _cloud_offset)
	RenderingServer.global_shader_parameter_set("cloud_cover", CLOUD_COVER[_planet.profile] + weather * 0.42)
	RenderingServer.global_shader_parameter_set("cloud_shadow", shadow * (1.0 - smoothstep(0.6, 1.0, weather) * 0.6))


func _update_grade(sun_height: float, space: float) -> void:
	# 正午、黄金时段和夜晚三组调色按太阳高度混合，太空中回到中性。
	var noon: float = smoothstep(0.10, 0.40, sun_height)
	var night: float = 1.0 - smoothstep(-0.16, -0.02, sun_height)
	var golden: float = clampf(1.0 - noon - night, 0.0, 1.0)
	var key: Vector4 = Vector4(noon, golden, night, space)
	if key.distance_to(_grade_key) < 0.01:
		return
	_grade_key = key
	var surface: float = 1.0 - space
	# 暗部抬起的颜色与亮部增益，按通道给出；暗部偏紫蓝，黄金时段亮部偏暖。
	var lift: Vector3 = (Vector3(0.0, 0.004, 0.016) * noon + Vector3(0.03, 0.004, 0.045) * golden + Vector3(0.0, 0.008, 0.03) * night) * surface
	var gain: Vector3 = Vector3.ONE.lerp(Vector3(1.0, 1.0, 0.985) * noon + Vector3(1.05, 0.975, 0.87) * golden + Vector3(0.88, 0.94, 1.05) * night, surface)
	var points: PackedFloat32Array = []
	var colors: PackedColorArray = []
	for index: int in 9:
		var level: float = float(index) / 8.0
		# 轻微的 S 形曲线提高中间调对比，保留卡通色块的干净边界。
		var curved: float = lerpf(level, level * level * (3.0 - 2.0 * level), 0.18 * surface)
		var channel: Vector3 = lift + (gain - lift) * curved
		points.append(level)
		colors.append(Color(channel.x, channel.y, channel.z))
	_grade_gradient.offsets = points
	_grade_gradient.colors = colors
	_environment.adjustment_saturation = lerpf(1.0, 1.05 * noon + 1.14 * golden + 0.86 * night, surface)


func _build_rain_curtain() -> MeshInstance3D:
	# 八百条雨丝合在一个网格里，每条带三个随机数，位置由 rain 着色器计算。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var uv2s: PackedVector2Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	for streak: int in 800:
		var seed_value: Vector3 = Vector3(rng.randf(), rng.randf(), rng.randf())
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			vertices.append(Vector3.ZERO)
			uvs.append(corner)
			uv2s.append(Vector2(seed_value.x, seed_value.y))
			colors.append(Color(seed_value.z, 0.0, 0.0))
		var base: int = streak * 4
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/rain.gdshader") as Shader
	var curtain: MeshInstance3D = MeshInstance3D.new()
	curtain.name = "RainCurtain"
	curtain.mesh = mesh
	curtain.material_override = material
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 顶点都在原点，真实位置在着色器里算，所以把剔除范围放得足够大。
	curtain.extra_cull_margin = 16384.0
	curtain.visible = false
	return curtain
