class_name EarthChecks
extends RefCounted


static func run(scene: Node3D, output: String) -> Dictionary:
	var failures: Array[String] = []
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var hud: CanvasLayer = scene.get_node("HUD") as CanvasLayer
	var atlas: TerrainAtlas = hud.get_node("Layout/TerrainAtlas") as TerrainAtlas
	var tree: SceneTree = scene.get_tree()
	var menu: VoyageMenu = scene.get_node("VoyageMenu") as VoyageMenu
	if menu._panel == null:
		menu.initialize()
	menu.visible = false
	menu._started = true
	var up: Vector3 = planet.site["direction"]
	var forward: Vector3 = planet.site["forward"]
	player.place_at(planet.global_position + up * (planet.surface_radius(up) + 0.1), forward, up)
	player.mode = StarSeaPlayer.Mode.WALK
	player.controls_enabled = true
	(scene.get_node("SkyDirector") as SkyDirector).set_sun_altitude(up, -forward, 35.0)
	hud.visible = true
	if not await AcceptanceChecks._settle(scene, planet):
		return {"passed": false, "failures": ["地球专项检查等待地形超时。"]}
	var deadline: int = Time.get_ticks_msec() + 120000
	while atlas.global_view.texture == null or atlas.local_view.texture == null:
		await tree.process_frame
		if Time.get_ticks_msec() > deadline:
			return {"passed": false, "failures": ["地形图后台生成超时。"]}
	# 经度接缝和两极附近均检查往返投影，不能只验证出生点。
	var projection_error: float = 0.0
	for uv: Vector2 in [Vector2(0.001, 0.5), Vector2(0.999, 0.5), Vector2(0.2, 0.01), Vector2(0.7, 0.99), Vector2(0.3, 0.4)]:
		var direction: Vector3 = TerrainMapData.direction_at(uv)
		projection_error = maxf(projection_error, direction.distance_to(TerrainMapData.direction_at(TerrainMapData.coordinates(direction))))
	if projection_error > 0.00001:
		failures.append("全球地图投影往返不一致。")
	var data: Dictionary = TerrainMapData.generate(planet.noise, Vector2i(40, 20))
	var image: Image = data["image"]
	var height_error: float = 0.0
	for row: int in 20:
		for column: int in 40:
			var direction: Vector3 = TerrainMapData.direction_at((Vector2(column, row) + Vector2.ONE * 0.5) / Vector2(40, 20))
			height_error = maxf(height_error, absf(image.get_pixel(column, row).r - planet.noise.height(direction)))
	if height_error > 0.001:
		failures.append("地图高度与实际地形函数不一致。")
	var view_before: Vector3 = -player.camera.global_basis.z
	_emit(KEY_V)
	await tree.physics_frame
	await tree.physics_frame
	if not player.third_person or not player.explorer.visible or view_before.angle_to(-player.camera.global_basis.z) > 0.001:
		failures.append("V 没有切换第三人称或切换改变了观察方向。")
	# 状态栏按 0.2 秒刷新，截图应与切换后的视角名称保持一致。
	await tree.create_timer(0.25).timeout
	await AcceptanceChecks._capture(scene, output.path_join("third_person_ground.png"))
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 2
	wall.global_transform = Transform3D(player.global_basis, player.camera_boom.global_position + player.global_basis.z * 2.0)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(5, 5, 0.3)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	for frame: int in 4:
		await tree.physics_frame
	var blocked_length: float = player.camera_boom.get_hit_length()
	if blocked_length > 2.1 or blocked_length < 0.3:
		failures.append("第三人称相机没有避开身后障碍。")
	wall.queue_free()
	for frame: int in 4:
		await tree.physics_frame
	var restored_length: float = player.camera_boom.get_hit_length()
	if restored_length < 4.0:
		failures.append("障碍消失后相机没有恢复距离。")
	player.set_head_pitch(deg_to_rad(80.0))
	for frame: int in 4:
		await tree.physics_frame
	var camera_offset: Vector3 = player.camera.global_position - planet.global_position
	var camera_clearance: float = camera_offset.length() - planet.surface_radius(camera_offset.normalized())
	if camera_clearance < 0.15:
		failures.append("大幅仰视时第三人称相机进入地下。")
	player.set_head_pitch(0.0)
	var map_transition: Dictionary = {"before_open": atlas.is_open, "before_controls": player.controls_enabled, "paused": tree.paused, "input_enabled": atlas.is_processing_input()}
	_emit(KEY_M)
	for frame: int in 3:
		await tree.process_frame
	map_transition["after_open"] = atlas.is_open
	map_transition["after_controls"] = player.controls_enabled
	map_transition["mouse_mode"] = Input.mouse_mode
	if not atlas.is_open or player.controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		failures.append("地图打开后没有正确释放鼠标并停用移动输入。")
	atlas.global_view.change_zoom(2.0)
	atlas.global_view.center_on_player()
	atlas._select(up)
	await AcceptanceChecks._capture(scene, output.path_join("global_relief_map.png"))
	var center_before: Vector2 = atlas.global_view._position(up)
	(scene.get_node("Universe") as Node3D).global_position += Vector3(2500, -1700, 3400)
	player.global_position += Vector3(2500, -1700, 3400)
	atlas._process(0.2)
	var origin_error: float = center_before.distance_to(atlas.global_view._position((player.global_position - planet.global_position).normalized()))
	if origin_error > 0.05:
		failures.append("原点平移改变了地图标记。")
	_emit(KEY_ESCAPE)
	await tree.process_frame
	if atlas.is_open or not player.controls_enabled:
		failures.append("Esc 没有关闭地图并恢复输入。")
	menu.open()
	_emit(KEY_M)
	for frame: int in 3:
		await tree.process_frame
	if atlas.is_open or not tree.paused:
		failures.append("暂停菜单与地图争夺输入。")
	menu.resume()
	scene.get_window().mode = Window.MODE_WINDOWED
	scene.get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	player.set_third_person(false)
	await tree.physics_frame
	await tree.physics_frame
	if player.camera.position.length() > 0.01:
		failures.append("返回第一人称后相机仍有第三人称偏移。")
	var save_path: String = "user://verify_earth_perspective.cfg"
	player.set_third_person(true)
	JourneyStore.save(scene, save_path)
	player.set_third_person(false)
	var restore_error: Error = JourneyStore.restore(scene, save_path)
	if restore_error != OK or not player.third_person:
		failures.append("读取旅程没有恢复第三人称。")
	var legacy: ConfigFile = ConfigFile.new()
	legacy.load(save_path)
	legacy.erase_section_key("journey", "third_person")
	legacy.save(save_path)
	var legacy_error: Error = JourneyStore.restore(scene, save_path)
	if legacy_error != OK or player.third_person:
		failures.append("旧旅程缺少视角字段时没有使用第一人称。")
	legacy.set_value("journey", "third_person", [])
	legacy.save(save_path)
	if JourneyStore.restore(scene, save_path) != ERR_INVALID_DATA:
		failures.append("损坏的视角字段没有安全拒绝。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	player.set_third_person(true)
	player.mode = StarSeaPlayer.Mode.FLY
	player.place_at(planet.global_position + up * (planet.surface_radius(up) + 35.0), forward, up)
	player.set_head_pitch(-0.20)
	for frame: int in 8:
		await tree.physics_frame
	await AcceptanceChecks._capture(scene, output.path_join("third_person_flight.png"))
	player.controls_enabled = true
	atlas.set_open(true)
	scene.get_window().size = Vector2i(1280, 720)
	for frame: int in 8:
		await tree.process_frame
	await AcceptanceChecks._capture(scene, output.path_join("map_720p.png"))
	var captured_size: Vector2i = scene.get_viewport().get_texture().get_image().get_size()
	var small_layout: bool = captured_size == Vector2i(1280, 720) and atlas.global_view.size.x > 600.0 and Rect2(Vector2.ZERO, atlas.size).encloses(atlas.global_view.get_global_rect())
	if not small_layout:
		failures.append("720p 地图布局越界或过小。")
	scene.get_window().size = Vector2i(1920, 1080)
	atlas.set_open(false)
	await tree.create_timer(0.2).timeout
	var mini_rect: Rect2 = atlas._mini.get_global_rect()
	var minimap_top_right: bool = mini_rect.position.x > 1500.0 and mini_rect.position.y < 40.0 and mini_rect.end.x <= 1920.0
	if not minimap_top_right:
		failures.append("小地图没有保持在右上角。")
	player.set_third_person(false)
	var music_report: Dictionary = await _music_check(scene, output)
	if not music_report["passed"]:
		failures.append("晨的音乐播放、独立静音或离开星球淡出检查失败。")
	return {"passed": failures.is_empty(), "failures": failures, "map_capture_size": str(captured_size), "atlas_size": str(atlas.size), "map_rect": str(atlas.global_view.get_global_rect()), "map_input_transition": map_transition, "global_projection_error": projection_error, "map_height_error_m": height_error, "map_height_samples": 800, "camera_blocked_length_m": blocked_length, "camera_restored_length_m": restored_length, "camera_upward_view_clearance_m": camera_clearance, "floating_origin_marker_error_px": origin_error, "perspective_save_restored": restore_error == OK, "map_720p_layout": small_layout, "minimap_top_right": minimap_top_right, "music": music_report}


static func _music_check(scene: Node3D, output: String) -> Dictionary:
	var sound: Soundscape = scene.get_node("Soundscape") as Soundscape
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var relative: Vector3 = (scene.get_node("Player") as StarSeaPlayer).global_position - planet.global_position
	var original_volume: float = StarSeaSettings.music_volume
	sound._music.stop()
	sound._music_wait = 0.0
	sound._update_music(1.0, planet, relative)
	var started: bool = sound._music.playing
	StarSeaSettings.music_volume = 0.0
	sound._update_music(0.016, planet, relative)
	var muted: bool = sound._music.volume_linear < 0.00001
	sound._update_music(30.0, planet, relative.normalized() * (planet.radius + 5000.0))
	var faded: bool = not sound._music.playing
	StarSeaSettings.music_volume = original_volume
	# 单独录制音乐的实际播放输出，检查其已进入混音且没有削波。
	sound.set_process(false)
	for audio: AudioStreamPlayer in sound._loops.values():
		audio.volume_linear = 0.0
	sound._step.stop()
	var effect: AudioEffectRecord = AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, effect)
	effect.set_recording_active(true)
	sound._music.volume_linear = 0.108
	sound._music.play()
	await scene.get_tree().create_timer(5.0).timeout
	effect.set_recording_active(false)
	var recording: AudioStreamWAV = effect.get_recording()
	var path: String = ProjectSettings.globalize_path(output.path_join("dawn_music_mix.wav"))
	var error: Error = recording.save_to_wav(path)
	AudioServer.remove_bus_effect(0, effect_index)
	sound._music.stop()
	sound.set_process(true)
	return {"passed": started and muted and faded and error == OK and recording.data.size() > 22050, "started": started, "independent_mute": muted, "left_dawn_surface_faded": faded, "recorded_seconds": recording.get_length()}


static func _emit(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
