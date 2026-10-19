class_name SkyDirector
extends Node

var sun_direction: Vector3 = Vector3(0.35, 0.35, -0.87).normalized()
var time_paused: bool = false
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
	_update_environment()


func set_sun_altitude(up: Vector3, horizontal: Vector3, angle_degrees: float) -> void:
	var tangent: Vector3 = (horizontal - up * horizontal.dot(up)).normalized()
	var angle: float = deg_to_rad(angle_degrees)
	sun_direction = (up * sin(angle) + tangent * cos(angle)).normalized()
	_update_environment()


func _process(delta: float) -> void:
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
	_sun.light_energy = lerpf(smoothstep(-0.08, 0.05, sun_height), 1.0, space)
	_environment.ambient_light_color = Color(0.10, 0.12, 0.28).lerp(Color(0.42, 0.45, 0.70), day).lerp(Color(0.08, 0.08, 0.16), space)
	_environment.ambient_light_energy = lerpf(lerpf(0.35, 0.55, day), 0.3, space)
	for node: Node in get_tree().get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		if planet.atmosphere_material != null:
			planet.atmosphere_material.set_shader_parameter("planet_center", planet.global_position)
