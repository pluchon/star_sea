class_name VoyageMenu
extends CanvasLayer

var _panel: PanelContainer
var _pages: VBoxContainer
var _message: Label
var _player: StarSeaPlayer
var _started: bool = false
var _shade: ColorRect
var _hud: CanvasLayer
var _hud_was_visible: bool = true
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	# 命令行验收直接进入世界，测试脚本单独创建菜单以验证交互。
	if not OS.get_cmdline_user_args().is_empty():
		return
	initialize()
	open()


func initialize() -> void:
	_player = get_parent().get_node("Player") as StarSeaPlayer
	_hud = get_parent().get_node("HUD") as CanvasLayer
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_quit)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.19, 0.23, 0.85)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.36, 0.37, 0.95)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	theme.set_color("font_color", "Label", Color(0.88, 0.92, 0.90))
	var screen: Control = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = theme
	add_child(screen)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.015, 0.035, 0.06, 0.38)
	screen.add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 100.0
	_panel.offset_right = 550.0
	_panel.offset_top = -380.0
	_panel.offset_bottom = 380.0
	var background: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	background.bg_color = Color(0.025, 0.055, 0.075, 0.94)
	background.content_margin_left = 36.0
	background.content_margin_right = 36.0
	background.content_margin_top = 30.0
	background.content_margin_bottom = 30.0
	_panel.add_theme_stylebox_override("panel", background)
	screen.add_child(_panel)
	_pages = VBoxContainer.new()
	_pages.add_theme_constant_override("separation", 12)
	_panel.add_child(_pages)
	_home()


func _input(event: InputEvent) -> void:
	if _panel == null:
		return
	if event.is_action_pressed("release_mouse"):
		if visible and _started:
			resume()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if not _open:
		_hud_was_visible = _hud.visible
	_open = true
	_hud.visible = false
	visible = true
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_home()


func resume() -> void:
	_started = true
	_open = false
	_hud.visible = _hud_was_visible
	visible = false
	get_tree().paused = false
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	(get_node("/root/GameSettings") as StarSeaSettings).apply()


func _clear() -> void:
	for child: Node in _pages.get_children():
		_pages.remove_child(child)
		child.queue_free()


func _label(text: String, size: int = 18) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	_pages.add_child(label)
	return label


func _button(text: String, callback: Callable, id: String = "") -> Button:
	var button: Button = Button.new()
	button.text = text
	if not id.is_empty():
		button.name = id
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	_pages.add_child(button)
	return button


func _home() -> void:
	_clear()
	_label("星 海 尽 头", 42)
	_label("风掠过群山，星海在头顶。", 16)
	var space: Control = Control.new()
	space.custom_minimum_size.y = 24.0
	_pages.add_child(space)
	_button("继续漂流" if _started else "开始漂流", resume, "Resume")
	var load_button: Button = _button("读取旅程", _load_journey, "LoadJourney")
	load_button.disabled = not FileAccess.file_exists(JourneyStore.PATH)
	_button("保存旅程", _save_journey, "SaveJourney").disabled = not _started
	_button("设置", _settings, "Settings")
	_button("操作说明", _controls, "Controls")
	_button("退出", _quit, "Quit")
	_message = _label("晨 · 海岸草原\n烬 · 赤色沙丘　霜 · 冰蓝高地", 15)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 64.0


func _save_journey() -> void:
	var error: Error = JourneyStore.save(get_parent())
	_message.text = "旅程已保存。" if error == OK else "保存失败：" + error_string(error)
	var button: Button = _pages.get_node("LoadJourney") as Button
	button.disabled = error != OK


func _load_journey() -> void:
	var error: Error = JourneyStore.restore(get_parent())
	if error == OK:
		resume()
	else:
		_message.text = "无法读取旅程：" + error_string(error)


func _quit() -> void:
	if _started:
		var error: Error = JourneyStore.save(get_parent())
		if error != OK:
			_message.text = "保存失败，旅程尚未退出：" + error_string(error)
			return
	get_tree().quit()


func _controls() -> void:
	_clear()
	_label("操作说明", 30)
	_label("W A S D　移动\n鼠标　环顾\nShift　加速\n空格　跳跃 / 上升\nCtrl　下降\nF　飞行 / 距地面两米内步行\nT　加速昼夜\nH　帮助　F3　性能\nF12　截图　Esc　暂停", 18)
	_label("飞行速度随高度增加。\n离开地表后，朝远处的星球飞行。\n旅程会在退出时保存。", 16)
	_button("返回", _home)


func _settings() -> void:
	_clear()
	_label("设置", 30)
	_slider("鼠标灵敏度", StarSeaSettings.sensitivity * 1000.0, 0.5, 6.0, 0.1, func(value: float) -> void: StarSeaSettings.sensitivity = value / 1000.0)
	_slider("声音", StarSeaSettings.volume * 100.0, 0.0, 100.0, 1.0, func(value: float) -> void: StarSeaSettings.volume = value / 100.0)
	_slider("渲染比例", StarSeaSettings.render_scale * 100.0, 65.0, 100.0, 5.0, func(value: float) -> void: StarSeaSettings.render_scale = value / 100.0)
	_slider("视野", StarSeaSettings.field_of_view, 60.0, 100.0, 1.0, func(value: float) -> void: StarSeaSettings.field_of_view = value)
	_check("全屏", StarSeaSettings.fullscreen, func(value: bool) -> void: StarSeaSettings.fullscreen = value)
	_check("垂直同步", StarSeaSettings.vsync, func(value: bool) -> void: StarSeaSettings.vsync = value)
	_button("保存并返回", func() -> void:
		var error: Error = (get_node("/root/GameSettings") as StarSeaSettings).save()
		_home()
		if error != OK:
			_message.text = "设置保存失败：" + error_string(error))


func _slider(title: String, value: float, minimum: float, maximum: float, step: float, callback: Callable) -> void:
	var label: Label = _label("%s　%.1f" % [title, value], 16)
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 28.0
	slider.value_changed.connect(func(next: float) -> void:
		label.text = "%s　%.1f" % [title, next]
		callback.call(next))
	_pages.add_child(slider)


func _check(title: String, value: bool, callback: Callable) -> void:
	var check: CheckButton = CheckButton.new()
	check.text = title
	check.button_pressed = value
	check.toggled.connect(callback)
	_pages.add_child(check)
