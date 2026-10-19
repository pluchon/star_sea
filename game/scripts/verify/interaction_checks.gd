class_name InteractionChecks
extends RefCounted


static func run(scene: Node3D) -> Dictionary:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var terrain: PlanetTerrain = scene.get_node("Universe/PlanetDawn/Terrain") as PlanetTerrain
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var window: Window = scene.get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(1920, 1080)
	player.controls_enabled = false
	director.time_paused = true
	var deadline: int = Time.get_ticks_msec() + 120000
	while not terrain.is_settled() or terrain.visible_chunks < 6:
		await scene.get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			return {"passed": false, "failures": ["交互验证等待地形超时。"]}
	for frame: int in 120:
		await scene.get_tree().process_frame
	player.controls_enabled = true
	var failures: Array[String] = []
	_emit_key(KEY_F, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_F, false)
	if player.mode != StarSeaPlayer.Mode.FLY:
		failures.append("F 未能切换到飞行模式。")
	_emit_key(KEY_F, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_F, false)
	if player.mode != StarSeaPlayer.Mode.WALK:
		failures.append("近地按 F 未能切回步行模式。")
	_emit_key(KEY_F, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_F, false)
	_emit_key(KEY_H, true)
	_emit_key(KEY_F3, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_H, false)
	_emit_key(KEY_F3, false)
	await scene.get_tree().create_timer(0.3).timeout
	var help_visible: bool = false
	var performance_visible: bool = false
	for node: Node in scene.get_node("HUD").find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and label.text.contains("W A S D"):
			help_visible = true
		if label.is_visible_in_tree() and label.text.contains("FPS"):
			performance_visible = true
	if not help_visible or not performance_visible:
		failures.append("H 或 F3 未能显示对应面板。")
	_emit_key(KEY_ESCAPE, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_ESCAPE, false)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		failures.append("Esc 未能释放鼠标。")
	var directory: String = ProjectSettings.globalize_path("user://screenshots")
	var previous_files: PackedStringArray = DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	_emit_key(KEY_F12, true)
	await scene.get_tree().process_frame
	_emit_key(KEY_F12, false)
	for frame: int in 10:
		await scene.get_tree().process_frame
	var current_files: PackedStringArray = DirAccess.get_files_at(directory)
	if current_files.size() <= previous_files.size():
		failures.append("F12 未能创建截图文件。")
	# 界面留图不使用刚完成 PNG 编码时的一秒峰值读数。
	await scene.get_tree().create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	var image_path: String = ProjectSettings.globalize_path("res://../test-output/p1/interface.png")
	var image_error: Error = window.get_texture().get_image().save_png(image_path)
	if image_error != OK:
		failures.append("交互验收截图保存失败。")
	return {"passed": failures.is_empty(), "failures": failures, "help_visible": help_visible, "performance_visible": performance_visible, "screenshot_created": current_files.size() > previous_files.size()}


static func _emit_key(key: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
