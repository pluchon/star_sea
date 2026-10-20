class_name TerrainAtlas
extends Control

# 地球仪上最多插几面旗；再插会替换最早的一面。
const MAX_FLAGS: int = 6

var is_open: bool = false
var global_view: TerrainMapView
var local_view: TerrainMapView
var globe_view: GlobeView
# 玩家在地球仪上插的旗，存为晨的球面方向。
var flags: Array[Vector3] = []
var _flat_frame: AspectRatioContainer
var _globe_button: Button
var _compass: Control
var _player: StarSeaPlayer
var _planet: Planet
var _panel: PanelContainer
var _mini: PanelContainer
var _information: Label
var _mini_title: Label
var _local_information: Label
var _global_task: int = -1
var _local_task: int = -1
var _global_result: Dictionary = {}
var _local_result: Dictionary = {}
var _last_local_center: Vector3 = Vector3.ZERO
var _old_mouse_mode: Input.MouseMode
var _elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scene: Node = get_parent().get_parent().get_parent()
	_player = scene.get_node("Player") as StarSeaPlayer
	_planet = scene.get_node("Universe/PlanetDawn") as Planet
	_build()
	var noise: TerrainNoise = TerrainNoise.new(_planet.planet_seed, _planet.radius, 0)
	_global_task = WorkerThreadPool.add_task(func() -> void:
		_global_result = TerrainMapData.generate(noise, Vector2i(1024, 512)))


func _style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.075, 0.96)
	style.border_color = Color(0.45, 0.58, 0.53, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _build() -> void:
	_mini = PanelContainer.new()
	_mini.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mini.offset_left = -284
	_mini.offset_right = -24
	_mini.offset_top = 24
	_mini.offset_bottom = 320
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.add_theme_stylebox_override("panel", _style())
	add_child(_mini)
	var mini_column: VBoxContainer = VBoxContainer.new()
	mini_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.add_child(mini_column)
	var mini_title: Label = Label.new()
	_mini_title = mini_title
	mini_title.text = "晨　地形　　N ↑　 M 展开"
	mini_title.add_theme_font_size_override("font_size", 13)
	mini_column.add_child(mini_title)
	local_view = TerrainMapView.new()
	local_view.global_map = false
	local_view.custom_minimum_size = Vector2(220, 220)
	mini_column.add_child(local_view)
	_local_information = Label.new()
	_local_information.add_theme_font_size_override("font_size", 12)
	_local_information.text = "正在绘制附近地形…"
	mini_column.add_child(_local_information)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 48
	_panel.offset_top = 36
	_panel.offset_right = -48
	_panel.offset_bottom = -36
	_panel.add_theme_stylebox_override("panel", _style())
	_panel.visible = false
	add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "晨 / 全球地形图"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for entry: Array in [["立体地球", _toggle_globe], ["－", func() -> void: global_view.change_zoom(0.8)], ["＋", func() -> void: global_view.change_zoom(1.25)], ["当前位置", _center_on_player], ["关闭  M / Esc", func() -> void: set_open(false)]]:
		var button: Button = Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(40, 36)
		button.pressed.connect(entry[1])
		header.add_child(button)
		if _globe_button == null:
			_globe_button = button
	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = "滚轮缩放 · 拖动平移 · 点击查看海拔　　等高距 100 m　　N ↑"
	hint.add_theme_font_size_override("font_size", 14)
	column.add_child(hint)
	var aspect: AspectRatioContainer = AspectRatioContainer.new()
	aspect.ratio = 2.0
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(aspect)
	_flat_frame = aspect
	global_view = TerrainMapView.new()
	aspect.add_child(global_view)
	global_view.selected.connect(_select)
	globe_view = GlobeView.new()
	globe_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe_view.visible = false
	column.add_child(globe_view)
	globe_view.selected.connect(_select)
	globe_view.flag_requested.connect(_add_flag)
	globe_view.flag_removed.connect(_remove_flag)
	_information = Label.new()
	_information.text = "正在绘制全球地形…"
	column.add_child(_information)
	var legend: HBoxContainer = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 0)
	column.add_child(legend)
	for entry: Array in [["海洋", Color(0.13, 0.30, 0.38)], ["0 m", Color(0.48, 0.64, 0.42)], ["400 m", Color(0.69, 0.73, 0.45)], ["1000 m", Color(0.68, 0.52, 0.35)], ["1700 m", Color(0.55, 0.51, 0.47)], ["2400 m", Color(0.92, 0.92, 0.83)]]:
		var swatch: PanelContainer = PanelContainer.new()
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = entry[1]
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		swatch.add_theme_stylebox_override("panel", style)
		legend.add_child(swatch)
		var label: Label = Label.new()
		label.text = entry[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.06, 0.10, 0.12) if entry[0] != "海洋" else Color(0.90, 0.92, 0.86))
		swatch.add_child(label)
	for view: TerrainMapView in [global_view, local_view]:
		view.planet_radius = _planet.radius
		view.spawn_direction = _planet.site["direction"]
		view.ruin_direction = SurfaceSites.ruin_direction(_planet.site, _planet.radius)
	# 屏幕上方的旗子方位标记：只在地面附近、地图关闭时显示，颜色很淡。
	_compass = FlagCompass.new()
	_compass.atlas = self
	_compass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compass)


class FlagCompass extends Control:
	var atlas: TerrainAtlas

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		atlas.draw_compass(self)


func set_flags(directions: Array[Vector3]) -> void:
	flags = directions.duplicate()
	_sync_flags()


func _add_flag(direction: Vector3) -> void:
	if flags.size() >= MAX_FLAGS:
		flags.remove_at(0)
	flags.append(direction.normalized())
	_sync_flags()


func _remove_flag(direction: Vector3) -> void:
	# 右键拔掉离点击处最近的一面旗，太远的不算。
	var nearest: int = -1
	var closest: float = 0.08
	for index: int in flags.size():
		var gap: float = flags[index].distance_to(direction)
		if gap < closest:
			closest = gap
			nearest = index
	if nearest >= 0:
		flags.remove_at(nearest)
		_sync_flags()


func _sync_flags() -> void:
	for view: TerrainMapView in [global_view, local_view]:
		view.flags = flags
		view.queue_redraw()
	globe_view.flags = flags
	globe_view.refresh()


func _toggle_globe() -> void:
	var showing: bool = not globe_view.visible
	globe_view.visible = showing
	_flat_frame.visible = not showing
	_globe_button.text = "平面地图" if showing else "立体地球"
	var hint: Label = _panel.find_child("Hint", true, false) as Label
	hint.text = "拖动旋转 · 滚轮缩放 · 单击插旗 · 右键拔旗　　旗子会在屏幕上方显示方位" if showing else "滚轮缩放 · 拖动平移 · 点击查看海拔　　等高距 100 m　　N ↑"
	if showing:
		_center_on_player()


func _center_on_player() -> void:
	global_view.center_on_player()
	var relative: Vector3 = _player.global_position - _planet.global_position
	globe_view.face(relative.normalized() if _player.current_planet() == _planet else Vector3(_planet.site["direction"]))


# 最近一面旗的方位：按相机朝向换算到屏幕横向位置，超出视野时贴在屏幕边缘。
func draw_compass(canvas: Control) -> void:
	if flags.is_empty() or is_open or _player.current_planet() != _planet:
		return
	var camera: Camera3D = _player.camera
	var relative: Vector3 = camera.global_position - _planet.global_position
	var up: Vector3 = relative.normalized()
	if relative.length() - _planet.radius > 8000.0:
		return
	var target: Vector3 = flags[0]
	for flag: Vector3 in flags:
		if flag.distance_to(up) < target.distance_to(up):
			target = flag
	var distance: float = up.angle_to(target) * _planet.radius
	var toward: Vector3 = target - up * target.dot(up)
	var forward: Vector3 = -camera.global_basis.z
	forward = forward - up * forward.dot(up)
	if toward.length_squared() < 1e-12 or forward.length_squared() < 1e-8:
		return
	var bearing: float = forward.normalized().signed_angle_to(toward.normalized(), up)
	var half_view: float = deg_to_rad(camera.fov) * 0.5 * canvas.size.x / canvas.size.y
	var x: float = canvas.size.x * 0.5 - bearing / half_view * canvas.size.x * 0.5
	var edge: bool = x < 60.0 or x > canvas.size.x - 60.0
	x = clampf(x, 60.0, canvas.size.x - 60.0)
	var center: Vector2 = Vector2(x, 54.0)
	var alpha: float = 0.42 if edge else 0.6
	var diamond: PackedVector2Array = [center + Vector2(0, -7), center + Vector2(6, 0), center + Vector2(0, 7), center + Vector2(-6, 0)]
	canvas.draw_colored_polygon(diamond, Color(0.93, 0.42, 0.32, alpha))
	var text: String = "%.1f km" % (distance / 1000.0) if distance >= 1000.0 else "%d m" % int(distance)
	var font: Font = canvas.get_theme_default_font()
	canvas.draw_string(font, center + Vector2(-24, 24), text, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 13, Color(0.92, 0.94, 0.90, alpha))


func set_open(enabled: bool) -> void:
	if is_open == enabled:
		return
	if enabled:
		if not _player.controls_enabled or get_tree().paused:
			return
		_old_mouse_mode = Input.mouse_mode
		_player.controls_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_player.controls_enabled = true
		Input.mouse_mode = _old_mouse_mode
	is_open = enabled
	_panel.visible = enabled
	_mini.visible = not enabled
	global_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map") and not event.is_echo():
		set_open(not is_open)
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("release_mouse"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_collect()
	_elapsed += delta
	if _elapsed < 0.1:
		return
	_elapsed = 0.0
	var relative: Vector3 = _player.global_position - _planet.global_position
	var up: Vector3 = relative.normalized()
	var on_dawn: bool = _player.current_planet() == _planet
	if on_dawn:
		var water: String = _planet.noise.water_body(up)
		_mini_title.text = "晨 · %s　 N ↑　 M" % (water if not water.is_empty() else _planet.noise.biome(up))
	for view: TerrainMapView in [global_view, local_view]:
		view.player_direction = up if on_dawn else Vector3.ZERO
		view.player_forward = -_player.camera.global_basis.z
		view.queue_redraw()
	if is_open and globe_view.visible:
		globe_view.set_player(up if on_dawn else Vector3.ZERO)
	_mini.visible = not is_open and on_dawn and relative.length() - _planet.radius < 8000.0
	if _mini.visible and is_visible_in_tree() and _local_task == -1 and up.distance_to(_last_local_center) * _planet.radius > 100.0:
		_last_local_center = up
		var noise: TerrainNoise = TerrainNoise.new(_planet.planet_seed, _planet.radius, 0)
		_local_task = WorkerThreadPool.add_task(func() -> void:
			_local_result = TerrainMapData.generate(noise, Vector2i(256, 256), up))


func _collect() -> void:
	if _global_task != -1 and WorkerThreadPool.is_task_completed(_global_task):
		WorkerThreadPool.wait_for_task_completion(_global_task)
		_global_task = -1
		global_view.set_map(_global_result)
		globe_view.set_map(_global_result)
		_information.text = "全球海拔 %.0f～%.0f m　　金色圆点：出发地　浅色圆点：遗迹" % [_global_result["minimum"], _global_result["maximum"]]
		_global_result = {}
	if _local_task != -1 and WorkerThreadPool.is_task_completed(_local_task):
		WorkerThreadPool.wait_for_task_completion(_local_task)
		_local_task = -1
		local_view.set_map(_local_result)
		_local_information.text = "范围 1.6 km　等高距 20 m　%.0f～%.0f m" % [_local_result["minimum"], _local_result["maximum"]]
		_local_result = {}


func _select(direction: Vector3) -> void:
	var uv: Vector2 = TerrainMapData.coordinates(direction)
	_information.text = "海拔 %.0f m　　纬度 %.1f°　经度 %.1f°　　%s · %s" % [_planet.noise.height(direction), (0.5 - uv.y) * 180.0, (uv.x - 0.5) * 360.0, _planet.noise.landform(direction), _planet.noise.biome(direction)]


func _exit_tree() -> void:
	for task: int in [_global_task, _local_task]:
		if task != -1:
			WorkerThreadPool.wait_for_task_completion(task)
