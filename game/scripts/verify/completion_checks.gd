extends SceneTree

const OUTPUT: String = "res://../test-output/p2"
var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	player.controls_enabled = false
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	director.time_paused = true
	var path: String = "user://verify_journey.cfg"
	var records: Array[Dictionary] = []
	for node: Node in get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var up: Vector3 = planet.site["direction"]
		var forward: Vector3 = planet.site["forward"]
		player.place_at(planet.global_position + up * (planet.surface_radius(up) + 10.0), forward, up)
		player.mode = StarSeaPlayer.Mode.FLY
		player.set_head_pitch(0.37)
		director.sun_direction = Vector3(0.2, 0.7, -0.4).normalized()
		await physics_frame
		await physics_frame
		var expected: Vector3 = player.global_position - planet.global_position
		var expected_basis: Quaternion = player.global_basis.get_rotation_quaternion()
		var expected_sun: Vector3 = director.sun_direction
		var saved: Error = JourneyStore.save(scene, path)
		# 同一路径再次保存，验证覆盖写入与临时文件替换。
		var replaced: Error = JourneyStore.save(scene, path)
		player.global_position += up * 5000.0
		player.global_basis = Basis.IDENTITY
		player.set_head_pitch(0.0)
		player.mode = StarSeaPlayer.Mode.WALK
		director.sun_direction = Vector3.UP
		var restored: Error = JourneyStore.restore(scene, path)
		var position_error: float = (player.global_position - planet.global_position).distance_to(expected)
		var orientation_error: float = player.global_basis.get_rotation_quaternion().angle_to(expected_basis)
		var view_restored: bool = orientation_error < 0.001 and absf(player.head_pitch() - 0.37) < 0.0001
		var state_restored: bool = player.mode == StarSeaPlayer.Mode.FLY and director.sun_direction.angle_to(expected_sun) < 0.001
		if saved != OK or replaced != OK or restored != OK or position_error > 0.1 or not view_restored or not state_restored:
			_failures.append(planet.planet_name + "的存档往返失败。")
		records.append({"planet": planet.planet_name, "save": saved, "replace": replaced, "restore": restored, "position_error_m": position_error, "orientation_error_degrees": rad_to_deg(orientation_error), "view_restored": view_restored, "mode_and_sun_restored": state_restored})
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("journey", "version", 999)
	invalid.save(path)
	var before: Vector3 = player.global_position
	var rejected: bool = JourneyStore.restore(scene, path) == ERR_FILE_UNRECOGNIZED and player.global_position == before
	if not rejected:
		_failures.append("无效版本存档未能安全拒绝。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var menu: VoyageMenu = scene.get_node("VoyageMenu") as VoyageMenu
	menu.initialize()
	menu.open()
	await process_frame
	if not paused or player.controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_failures.append("菜单未能暂停世界并释放鼠标。")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080)
		await _capture("menu.png")
	var settings: Button = menu.find_child("Settings", true, false) as Button
	settings.pressed.emit()
	await process_frame
	if menu.find_children("*", "HSlider", true, false).size() != 4:
		_failures.append("设置页面缺少滑动控件。")
	if DisplayServer.get_name() != "headless":
		await _capture("settings.png")
		root.size = Vector2i(1280, 720)
		await _capture("settings720.png")
		root.size = Vector2i(1920, 1080)
	var settings_node: StarSeaSettings = root.get_node("GameSettings") as StarSeaSettings
	var original_volume: float = StarSeaSettings.volume
	var original_sensitivity: float = StarSeaSettings.sensitivity
	StarSeaSettings.volume = 0.37
	StarSeaSettings.sensitivity = 0.0031
	var settings_path: String = "user://verify_settings.cfg"
	var settings_saved: Error = settings_node.save(settings_path)
	StarSeaSettings.volume = 0.1
	StarSeaSettings.sensitivity = 0.001
	var settings_loaded: Error = settings_node.load_settings(settings_path)
	var settings_roundtrip: bool = settings_saved == OK and settings_loaded == OK and is_equal_approx(StarSeaSettings.volume, 0.37) and is_equal_approx(StarSeaSettings.sensitivity, 0.0031)
	if not settings_roundtrip:
		_failures.append("设置持久化往返失败。")
	StarSeaSettings.volume = original_volume
	StarSeaSettings.sensitivity = original_sensitivity
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	menu.resume()
	if paused or not player.controls_enabled:
		_failures.append("继续漂流未能恢复世界。")
	await process_frame
	await process_frame
	var sound: Soundscape = scene.get_node("Soundscape") as Soundscape
	var audio_players: Array[Node] = sound.find_children("*", "AudioStreamPlayer", true, false)
	var loop_count: int = 0
	for node: Node in audio_players:
		var audio: AudioStreamPlayer = node as AudioStreamPlayer
		if audio.playing:
			loop_count += 1
	if DisplayServer.get_name() != "headless" and (audio_players.size() != 5 or loop_count != 4):
		_failures.append("环境音未能正常开始循环。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "journey_roundtrips": records, "invalid_save_rejected": rejected, "settings_roundtrip": settings_roundtrip, "audio_players": audio_players.size(), "ambient_loops_playing": loop_count}
	VerificationMetrics.write_json(OUTPUT.path_join("completion_checks.json"), report)
	print(JSON.stringify(report))
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _capture(filename: String) -> void:
	for frame: int in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var error: Error = root.get_texture().get_image().save_png(directory.path_join(filename))
	if error != OK:
		_failures.append("菜单截图保存失败。")
