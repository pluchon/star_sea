extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var up: Vector3 = planet.site["direction"]
	player.mode = StarSeaPlayer.Mode.FLY
	player.place_at(planet.global_position + up * (planet.radius + 10000.0), Vector3.FORWARD, Vector3.UP)
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var original: Basis = player.global_basis
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(150.0, 0.0)
	motion.screen_relative = Vector2(100.0, 0.0)
	player._unhandled_input(motion)
	var expected: Basis = Basis(original.y, -100.0 * StarSeaSettings.sensitivity) * original
	var yaw_error: float = player.global_basis.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion())
	var roll_error: float = player.global_basis.y.angle_to(original.y)
	if yaw_error > 0.0005 or roll_error > 0.0005:
		_failures.append("太空水平转动使用了错误的轴或缩放后的鼠标位移。")
	player.global_basis = original
	motion.relative = Vector2(50.0, 0.0)
	player._unhandled_input(motion)
	var scaling_error: float = player.global_basis.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion())
	if scaling_error > 0.0005:
		_failures.append("相同屏幕鼠标位移在不同界面缩放下产生不同转角。")
	player.global_basis = original
	player.controls_enabled = false
	var before: Basis = player.camera.global_basis
	for frame: int in 20:
		await physics_frame
	var drift: float = player.camera.global_basis.get_rotation_quaternion().angle_to(before.get_rotation_quaternion())
	if drift > 0.0005:
		_failures.append("飞行时没有鼠标输入仍自动改变观察方向。")
	var ember: Planet = scene.get_node("Universe/PlanetEmber") as Planet
	var ember_up: Vector3 = ember.site["direction"]
	player.global_position = ember.global_position + ember_up * (ember.radius + 5000.0)
	for frame: int in 20:
		await physics_frame
	var crossing_drift: float = player.camera.global_basis.get_rotation_quaternion().angle_to(before.get_rotation_quaternion())
	if crossing_drift > 0.0005 or player.current_planet() != ember:
		_failures.append("最近星球发生变化时，飞行朝向不稳定。")
	var forward: Vector3 = SurfaceSites.tangent_forward(up)
	player.place_at(planet.global_position + up * (planet.surface_radius(up) + 1.2), forward, up.rotated(forward, 0.4))
	player.set_head_pitch(0.25)
	player.controls_enabled = true
	var landing_view: Vector3 = -player.camera.global_basis.z
	var toggle: InputEventKey = InputEventKey.new()
	toggle.physical_keycode = KEY_F
	toggle.pressed = true
	player._unhandled_input(toggle)
	var landing_error: float = landing_view.angle_to(-player.camera.global_basis.z)
	if player.mode != StarSeaPlayer.Mode.WALK or landing_error > 0.0005 or player.global_basis.y.dot(up) < 0.9999:
		_failures.append("切回步行时未能对齐地面并保留观察方向。")
	player.mode = StarSeaPlayer.Mode.FLY
	player.set_head_pitch(0.0)
	motion.relative = Vector2(0.0, -500.0)
	motion.screen_relative = Vector2(0.0, -100.0)
	player._unhandled_input(motion)
	var pitch_error: float = absf(player.head_pitch() - 100.0 * StarSeaSettings.sensitivity)
	if pitch_error > 0.00001:
		_failures.append("俯仰灵敏度仍受界面缩放影响。")
	var report: Dictionary = {
		"passed": _failures.is_empty(),
		"failures": _failures,
		"yaw_error_degrees": rad_to_deg(yaw_error),
		"roll_error_degrees": rad_to_deg(roll_error),
		"scaling_error_degrees": rad_to_deg(scaling_error),
		"idle_flight_drift_degrees": rad_to_deg(drift),
		"interplanetary_drift_degrees": rad_to_deg(crossing_drift),
		"walk_transition_view_error_degrees": rad_to_deg(landing_error),
		"pitch_error_degrees": rad_to_deg(pitch_error),
	}
	VerificationMetrics.write_json("res://../test-output/p3/camera_checks.json", report)
	print(JSON.stringify(report))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)
