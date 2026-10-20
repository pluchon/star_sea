class_name GlobeView
extends SubViewportContainer

# 地图里的立体地球仪：拖动旋转，滚轮缩放，单击插旗，右键拔掉最近的旗子。
# 地球仪在独立的三维世界里渲染，不受游戏里的光照和浮动原点影响。

signal selected(direction: Vector3)
signal flag_requested(direction: Vector3)
signal flag_removed(direction: Vector3)

var player_direction: Vector3 = Vector3.ZERO
var spawn_direction: Vector3 = Vector3.ZERO
var flags: Array[Vector3] = []
var _viewport: SubViewport
var _pivot: Node3D
var _globe: MeshInstance3D
var _camera: Camera3D
var _markers: Node3D
var _player_marker: MeshInstance3D
var _distance: float = 3.2
var _press_position: Vector2
var _dragging: bool = false
var _flag_mesh: ArrayMesh
var _flag_material: StandardMaterial3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.75)
	environment.ambient_light_energy = 0.55
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	light.light_energy = 1.1
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_viewport.add_child(_camera)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_globe = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 256
	sphere.rings = 128
	_globe.mesh = sphere
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/globe.gdshader") as Shader
	_globe.material_override = material
	_pivot.add_child(_globe)
	_markers = Node3D.new()
	_pivot.add_child(_markers)
	_flag_mesh = _build_flag_mesh()
	_flag_material = StandardMaterial3D.new()
	_flag_material.vertex_color_use_as_albedo = true
	_flag_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_marker = MeshInstance3D.new()
	var dot: SphereMesh = SphereMesh.new()
	dot.radius = 0.018
	dot.height = 0.036
	_player_marker.mesh = dot
	var dot_material: StandardMaterial3D = StandardMaterial3D.new()
	dot_material.albedo_color = Color(0.99, 0.95, 0.77)
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_marker.material_override = dot_material
	_pivot.add_child(_player_marker)
	_update_camera()


func set_map(data: Dictionary) -> void:
	var texture: ImageTexture = ImageTexture.create_from_image(data["image"])
	var material: ShaderMaterial = _globe.material_override as ShaderMaterial
	material.set_shader_parameter("height_map", texture)
	material.set_shader_parameter("map_step", Vector2.ONE / Vector2(texture.get_size()))


# 把指定方向转到正对镜头。
func face(direction: Vector3) -> void:
	if direction == Vector3.ZERO:
		return
	var north: Vector3 = Vector3.UP - direction * direction.y
	if north.length_squared() < 0.0001:
		north = Vector3.FORWARD
	_pivot.basis = Basis.looking_at(-direction, north.normalized()).inverse()


func refresh() -> void:
	for child: Node in _markers.get_children():
		child.queue_free()
	for flag: Vector3 in flags:
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.mesh = _flag_mesh
		marker.material_override = _flag_material
		var up: Vector3 = flag.normalized()
		var side: Vector3 = Vector3.UP.cross(up) if absf(up.y) < 0.95 else Vector3.RIGHT
		marker.transform = Transform3D(Basis.looking_at(side.normalized(), up), up * 1.004)
		_markers.add_child(marker)
	_player_marker.visible = player_direction != Vector3.ZERO
	_player_marker.position = player_direction.normalized() * 1.012


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = maxf(_distance * 0.88, 1.35)
			_update_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = minf(_distance * 1.14, 5.0)
			_update_camera()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press_position = button.position
				_dragging = true
			else:
				_dragging = false
				# 按下和松开几乎在同一处，视为单击：插一面旗。
				if button.position.distance_to(_press_position) < 4.0:
					var direction: Vector3 = _pick(button.position)
					if direction != Vector3.ZERO:
						selected.emit(direction)
						flag_requested.emit(direction)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			var direction: Vector3 = _pick(button.position)
			if direction != Vector3.ZERO:
				flag_removed.emit(direction)
	elif event is InputEventMouseMotion and _dragging:
		var motion: Vector2 = (event as InputEventMouseMotion).relative
		var speed: float = 0.006 * (_distance - 0.9)
		_pivot.basis = (Basis(Vector3.UP, motion.x * speed) * Basis(Vector3.RIGHT, motion.y * speed) * _pivot.basis).orthonormalized()
	accept_event()


func _update_camera() -> void:
	_camera.position = Vector3(0.0, 0.0, _distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


# 屏幕坐标转成球面方向；没点在球上时返回零向量。
func _pick(screen: Vector2) -> Vector3:
	var scale_value: Vector2 = Vector2(_viewport.size) / size
	var origin: Vector3 = _camera.project_ray_origin(screen * scale_value)
	var ray: Vector3 = _camera.project_ray_normal(screen * scale_value)
	var b: float = origin.dot(ray)
	var c: float = origin.dot(origin) - 1.0
	var h: float = b * b - c
	if h < 0.0:
		return Vector3.ZERO
	var hit: Vector3 = origin + ray * (-b - sqrt(h))
	return (_pivot.global_basis.inverse() * hit).normalized()


func _build_flag_mesh() -> ArrayMesh:
	# 细杆加一面三角小旗，颜色和平面地图上的旗子一致。
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole: Color = Color(0.92, 0.90, 0.82)
	var cloth: Color = Color(0.93, 0.36, 0.28)
	for corner: int in 6:
		var a: float = TAU * corner / 6.0
		var b: float = TAU * (corner + 1) / 6.0
		var p0: Vector3 = Vector3(cos(a), 0.0, sin(a)) * 0.0025
		var p1: Vector3 = Vector3(cos(b), 0.0, sin(b)) * 0.0025
		for point: Vector3 in [p0, p1, p0 + Vector3.UP * 0.07, p1, p1 + Vector3.UP * 0.07, p0 + Vector3.UP * 0.07]:
			tool.set_color(pole)
			tool.add_vertex(point)
	for point: Vector3 in [Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.045, 0.0), Vector3(0.0, 0.0575, 0.035)]:
		tool.set_color(cloth)
		tool.add_vertex(point)
	return tool.commit()
