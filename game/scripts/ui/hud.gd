extends CanvasLayer

var _player: StarSeaPlayer
var _terrain: PlanetTerrain
var _status: Label
var _performance: Label
var _help: PanelContainer
var _elapsed: float = 0.0
var _interaction: Label


func _ready() -> void:
	_player = get_parent().get_node("Player") as StarSeaPlayer
	_terrain = get_parent().get_node("Universe/PlanetDawn/Terrain") as PlanetTerrain
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color(0.84, 0.89, 0.96, 0.85))
	theme.set_color("font_shadow_color", "Label", Color(0.02, 0.04, 0.08, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	var layout: Control = Control.new()
	layout.name = "Layout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.theme = theme
	add_child(layout)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_status.offset_left = -420.0
	_status.offset_top = -48.0
	_status.offset_right = -28.0
	_status.offset_bottom = -20.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layout.add_child(_status)
	_interaction = Label.new()
	_interaction.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_interaction.offset_left = -240.0
	_interaction.offset_right = 240.0
	_interaction.offset_top = -115.0
	_interaction.offset_bottom = -80.0
	_interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction.add_theme_font_size_override("font_size", 13)
	layout.add_child(_interaction)
	_performance = Label.new()
	_performance.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_performance.offset_top = 24.0
	_performance.offset_bottom = 140.0
	# 小地图固定在右上角，性能面板在其左侧显示。
	_performance.offset_left = -470.0
	_performance.offset_right = -310.0
	_performance.visible = false
	layout.add_child(_performance)
	_help = PanelContainer.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_help.offset_left = 28.0
	_help.offset_top = 28.0
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.085, 0.88)
	background.set_corner_radius_all(8)
	background.content_margin_left = 22.0
	background.content_margin_right = 22.0
	background.content_margin_top = 18.0
	background.content_margin_bottom = 18.0
	_help.add_theme_stylebox_override("panel", background)
	var text: Label = Label.new()
	text.text = "星海尽头\n\nW A S D　移动\n鼠标　环顾\nShift　加速\n空格　跳跃 / 上升\nCtrl　下降\nF　降落 / 登船（长按召唤飞船）\nV　第一 / 第三人称\nM　全球地形图（可切换立体地球、插旗）\nT　加速时间\nH　显示 / 隐藏帮助\nF3　性能\nF12　截图\nEsc　暂停菜单\n\n晨 · 海岸草原　烬 · 赤色沙丘　霜 · 冰蓝高地"
	_help.add_child(text)
	_help.visible = false
	layout.add_child(_help)
	var atlas: TerrainAtlas = TerrainAtlas.new()
	atlas.name = "TerrainAtlas"
	layout.add_child(atlas)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_interaction.text = _player.interaction_hint()
	_interaction.modulate.a = minf(_player._message_time * 3.0, 1.0) if _player._message_time > 0.0 else 0.8
	_elapsed += delta
	if _elapsed < 0.2:
		return
	_elapsed = 0.0
	var planet: Planet = _player.current_planet()
	_terrain = planet.get_node("Terrain") as PlanetTerrain
	var offset: Vector3 = _player.global_position - planet.global_position
	var altitude: float = offset.length() - planet.surface_radius(offset.normalized())
	var mode_name: String = "步行" if _player.mode == StarSeaPlayer.Mode.WALK else "飞行"
	_status.text = "%s · %s · %s　离地 %.0f m　%.1f m/s　H 帮助" % [planet.planet_name, mode_name, "第三人称" if _player.third_person else "第一人称", altitude, _player.velocity.length()]
	if _performance.visible:
		var cpu: float = (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_performance.text = "FPS   %d\nCPU   %.1f ms\nGPU   %.1f ms\n块数  %d" % [Engine.get_frames_per_second(), cpu, gpu, _terrain.visible_chunks]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_perf"):
		_performance.visible = not _performance.visible
	elif event.is_action_pressed("screenshot"):
		await RenderingServer.frame_post_draw
		var directory: String = ProjectSettings.globalize_path("user://screenshots")
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK:
			push_error("无法创建截图目录：" + error_string(directory_error))
			return
		var filename: String = Time.get_datetime_string_from_system().replace(":", "-") + "-%d.png" % Time.get_ticks_msec()
		var save_error: Error = get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
		if save_error != OK:
			push_error("截图保存失败：" + error_string(save_error))
