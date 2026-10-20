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
	_update_environment()


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
	var light_up: Vector3 = Vector3.UP if absf(sun_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sun.global_basis = Basis.looking_at(-sun_direction, light_up)
	var sunset: Color = Color(1.0, 0.62, 0.42)
	var noon: Color = Color(1.0, 0.97, 0.92)
	_sun.light_color = sunset.lerp(noon, smoothstep(0.0, 0.35, sun_height)).lerp(noon, space)
	_sun.light_energy = lerpf(smoothstep(-0.08, 0.05, sun_height) * 1.25, 1.0, space)
	# 日出日落前后天空最亮最暖，背光的地面也应映出紫粉色，而不是沉成黑褐色。
	var golden: float = smoothstep(-0.10, 0.02, sun_height) * (1.0 - smoothstep(0.10, 0.35, sun_height))
	var ambient: Color = Color(0.12, 0.16, 0.30).lerp(Color(0.46, 0.56, 0.72), day).lerp(Color(0.70, 0.52, 0.70), golden * 0.75)
	_environment.ambient_light_color = ambient.lerp(Color(0.08, 0.08, 0.16), space)
	# 晨的日间阴影保留蓝色环境光，并适度抬亮林下和背光山坡。
	var daytime_energy: float = 0.39 if _planet.profile == 0 else 0.32
	_environment.ambient_light_energy = lerpf(lerpf(0.18, daytime_energy, day) + golden * 0.30, 0.20, space)
	RenderingServer.global_shader_parameter_set("shadow_fill", golden * 0.32 * (1.0 - space))
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
	RenderingServer.global_shader_parameter_set("cloud_cover", CLOUD_COVER[_planet.profile])
	RenderingServer.global_shader_parameter_set("cloud_shadow", shadow)


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
