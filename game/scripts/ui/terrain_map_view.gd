class_name TerrainMapView
extends TextureRect

var global_map: bool = true
var center_uv: Vector2 = Vector2(0.5, 0.5)
var zoom: float = 1.0
var map_center: Vector3 = Vector3.ZERO
var span: float = 1600.0
var player_direction: Vector3 = Vector3.ZERO
var player_forward: Vector3 = Vector3.FORWARD
var spawn_direction: Vector3 = Vector3.ZERO
var ruin_direction: Vector3 = Vector3.ZERO
var planet_radius: float = 40000.0
var _dragging: bool = false
var _symbols: Symbols
signal selected(direction: Vector3)

class Symbols extends Control:
	var paint: Callable
	func _draw() -> void:
		paint.call(self)


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	clip_contents = true
	var map_material: ShaderMaterial = ShaderMaterial.new()
	map_material.shader = load("res://shaders/terrain_map.gdshader") as Shader
	material = map_material
	mouse_filter = Control.MOUSE_FILTER_STOP if global_map else Control.MOUSE_FILTER_IGNORE
	# 标记独立绘制，避免高度着色器覆盖方向箭头、地点圆点和经纬网颜色。
	_symbols = Symbols.new()
	_symbols.paint = _draw_symbols
	_symbols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_symbols)


func set_map(data: Dictionary) -> void:
	texture = ImageTexture.create_from_image(data["image"])
	map_center = data["center"]
	span = data["span"]
	var dimensions: Vector2 = Vector2(texture.get_size())
	var map_material: ShaderMaterial = material as ShaderMaterial
	map_material.set_shader_parameter("height_map", texture)
	map_material.set_shader_parameter("map_step", Vector2.ONE / dimensions)
	map_material.set_shader_parameter("global_map", global_map)
	map_material.set_shader_parameter("meters_per_pixel", Vector2(TAU * planet_radius, PI * planet_radius) / dimensions if global_map else Vector2.ONE * span / dimensions)
	map_material.set_shader_parameter("contour_interval", 100.0 if global_map else 20.0)
	queue_redraw()


func change_zoom(multiplier: float) -> void:
	zoom = clampf(zoom * multiplier, 1.0, 8.0)
	_sync_view()


func _sync_view() -> void:
	center_uv.x = fposmod(center_uv.x, 1.0)
	center_uv.y = clampf(center_uv.y, 0.5 / zoom, 1.0 - 0.5 / zoom)
	(material as ShaderMaterial).set_shader_parameter("zoom", zoom)
	(material as ShaderMaterial).set_shader_parameter("center", center_uv)
	queue_redraw()


func center_on_player() -> void:
	center_uv = TerrainMapData.coordinates(player_direction) if player_direction != Vector3.ZERO else Vector2.ONE * 0.5
	_sync_view()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			change_zoom(1.25)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			change_zoom(0.8)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed:
				selected.emit(TerrainMapData.direction_at(center_uv + (button.position / size - Vector2.ONE * 0.5) / zoom))
	elif event is InputEventMouseMotion and _dragging and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		center_uv -= (event as InputEventMouseMotion).relative / size / zoom
		_sync_view()
	accept_event()


func _position(direction: Vector3) -> Vector2:
	if global_map:
		var uv: Vector2 = TerrainMapData.coordinates(direction)
		uv.x = center_uv.x + wrapf(uv.x - center_uv.x, -0.5, 0.5)
		return ((uv - center_uv) * zoom + Vector2.ONE * 0.5) * size
	var northward: Vector3 = TerrainMapData.north(map_center)
	var eastward: Vector3 = map_center.cross(northward)
	var relative: Vector3 = (direction - map_center) * planet_radius
	return (Vector2(relative.dot(eastward), -relative.dot(northward)) / span + Vector2.ONE * 0.5) * size


func _draw() -> void:
	if _symbols != null:
		_symbols.queue_redraw()


func _draw_symbols(canvas: Control) -> void:
	if texture == null:
		return
	if global_map:
		for index: int in range(-8, 17):
			var x: float = ((index / 8.0 - center_uv.x) * zoom + 0.5) * size.x
			canvas.draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.86, 0.91, 0.79, 0.12))
		for index: int in range(1, 8):
			var y: float = ((index / 8.0 - center_uv.y) * zoom + 0.5) * size.y
			canvas.draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.86, 0.91, 0.79, 0.12))
	for marker: Array in [[spawn_direction, Color(0.96, 0.81, 0.47)], [ruin_direction, Color(0.92, 0.85, 0.73)]]:
		var position: Vector2 = _position(marker[0])
		canvas.draw_circle(position, 4.0, Color(0.05, 0.10, 0.12), true)
		canvas.draw_circle(position, 2.5, marker[1], true)
	if player_direction != Vector3.ZERO:
		var position: Vector2 = _position(player_direction)
		var northward: Vector3 = TerrainMapData.north(player_direction)
		var eastward: Vector3 = player_direction.cross(northward)
		var heading: float = atan2(player_forward.dot(eastward), player_forward.dot(northward))
		var triangle: PackedVector2Array = []
		for corner: Vector2 in [Vector2(0, -8), Vector2(5, 6), Vector2(0, 3), Vector2(-5, 6)]:
			triangle.append(position + corner.rotated(heading))
		canvas.draw_colored_polygon(triangle, Color(0.99, 0.95, 0.77))
		canvas.draw_polyline(triangle + PackedVector2Array([triangle[0]]), Color(0.05, 0.13, 0.16), 1.3, true)
