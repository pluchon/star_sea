class_name SurfaceDetails
extends Node3D

const TILE_SIZE: float = 48.0
const TILE_RADIUS: int = 2
const VIEW_DISTANCE: float = 170.0

var _planet: Planet
var _tiles: Dictionary[Vector2i, Node3D] = {}
var _origin_up: Vector3
var _forward: Vector3
var _right: Vector3
var _elapsed: float = 0.0
var _grass_mesh: ArrayMesh
var _stone_mesh: SphereMesh
var _grass_material: ShaderMaterial
var _stone_material: ShaderMaterial
var _task_id: int = -1
var _pending_key: Vector2i
var _pending_center: Vector3
var _pending_epoch: int = 0
var _epoch: int = 0
var _result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_parent() as Planet
	_origin_up = _planet.site["direction"]
	_forward = _planet.site["forward"]
	_right = _forward.cross(_origin_up).normalized()
	_grass_mesh = _make_grass()
	_stone_mesh = SphereMesh.new()
	_stone_mesh.radius = 1.0
	_stone_mesh.height = 2.0
	_stone_mesh.radial_segments = 5
	_stone_mesh.rings = 2
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = load("res://shaders/surface_detail.gdshader") as Shader
	_grass_material.set_shader_parameter("wind_strength", 0.16)
	_stone_material = ShaderMaterial.new()
	_stone_material.shader = _grass_material.shader
	if _planet.profile == 0:
		_warm_materials()
	_make_ruin()


func _warm_materials() -> void:
	# 先实例化隐藏版本，使 Godot 在启动时预编译近景实例材质，避免首次降落时停顿。
	var warmup: Node3D = Node3D.new()
	warmup.name = "MaterialWarmup"
	warmup.visible = false
	add_child(warmup)
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY]
	var colors: Array[Color] = [Color(0.4, 0.5, 0.3)]
	_add_instances(warmup, _grass_mesh, _grass_material, transforms, colors)
	_add_instances(warmup, _stone_mesh, _stone_material, transforms, colors)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.08:
		return
	_elapsed = 0.0
	_collect_tile()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var local: Vector3 = _planet.to_local(camera.global_position)
	var altitude: float = local.length() - _planet.surface_radius(local.normalized())
	# 高空不生成近景，已有分块在下一次进入地表时继续复用。
	visible = altitude < 400.0
	if not visible:
		return
	var up: Vector3 = local.normalized()
	# 每次离开切平面约一公里后重新建立坐标，覆盖整个球面。
	if up.dot(_origin_up) < 0.9997:
		_epoch += 1
		for tile: Node3D in _tiles.values():
			tile.queue_free()
		_tiles.clear()
		_origin_up = up
		_forward = SurfaceSites.tangent_forward(up)
		_right = _forward.cross(up).normalized()
	var relative: Vector3 = local - _origin_up * _planet.radius
	var center: Vector2i = Vector2i(floori(relative.dot(_right) / TILE_SIZE), floori(relative.dot(_forward) / TILE_SIZE))
	for key: Vector2i in _tiles.keys():
		if absi(key.x - center.x) > TILE_RADIUS or absi(key.y - center.y) > TILE_RADIUS:
			_tiles[key].queue_free()
			_tiles.erase(key)
	# 每次只创建一个近景分块，避免步行时集中上传实例。
	for ring: int in TILE_RADIUS + 1:
		for y: int in range(-ring, ring + 1):
			for x: int in range(-ring, ring + 1):
				var key: Vector2i = center + Vector2i(x, y)
				if not _tiles.has(key):
					if _task_id == -1:
						_request_tile(key)
					return


func _request_tile(key: Vector2i) -> void:
	_pending_key = key
	_pending_epoch = _epoch
	_pending_center = (_origin_up * _planet.radius + _right * (key.x + 0.5) * TILE_SIZE + _forward * (key.y + 0.5) * TILE_SIZE).normalized() * _planet.radius
	var center: Vector3 = _pending_center
	var right: Vector3 = _right
	var forward: Vector3 = _forward
	var noise: TerrainNoise = _planet.noise
	var planet_seed: int = _planet.planet_seed
	_task_id = WorkerThreadPool.add_task(func() -> void:
		_result = _generate(noise, center, right, forward, planet_seed))


func _collect_tile() -> void:
	if _task_id == -1 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	if _pending_epoch == _epoch and visible:
		var tile: Node3D = Node3D.new()
		tile.position = _pending_center
		add_child(tile)
		_add_instances(tile, _grass_mesh, _grass_material, _result["grass"], _result["grass_colors"])
		_add_instances(tile, _stone_mesh, _stone_material, _result["stones"], _result["stone_colors"])
		_tiles[_pending_key] = tile
	_result = {}


static func _generate(noise: TerrainNoise, center: Vector3, right: Vector3, forward: Vector3, planet_seed: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(center.x), roundi(center.y), roundi(center.z))) + planet_seed
	var grass: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var stone_colors: Array[Color] = []
	for index: int in 520:
		var direction: Vector3 = (center + right * rng.randf_range(-24.0, 24.0) + forward * rng.randf_range(-24.0, 24.0)).normalized()
		var height: float = noise.height(direction)
		if height < 3.0:
			continue
		var tangent: Vector3 = SurfaceSites.tangent_forward(direction).rotated(direction, rng.randf() * TAU)
		var basis: Basis = Basis.looking_at(tangent, direction)
		var position_local: Vector3 = direction * (noise.radius + height - 0.10) - center
		if index < 492 and height > 8.0 and height < 1250.0 and noise.profile == 0:
			var scale: float = rng.randf_range(0.45, 1.25)
			grass.append(Transform3D(basis.scaled(Vector3.ONE * scale), position_local))
			grass_colors.append(Color(0.20, 0.37, 0.20).lerp(Color(0.48, 0.60, 0.29), rng.randf()))
		elif index >= 492:
			var size: float = rng.randf_range(0.18, 0.85)
			stones.append(Transform3D(basis.scaled(Vector3(size * 1.2, size * 0.55, size)), position_local))
			stone_colors.append(Color(0.43, 0.46, 0.49).lerp(Color(0.69, 0.67, 0.61), rng.randf()))
	return {"grass": grass, "stones": stones, "grass_colors": grass_colors, "stone_colors": stone_colors}


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _add_instances(parent: Node3D, mesh: Mesh, material: ShaderMaterial, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	if transforms.is_empty():
		return
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index: int in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colors[index])
		multi.set_instance_custom_data(index, Color(float(index) / transforms.size(), 0.0, 0.0))
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.visibility_range_end = VIEW_DISTANCE
	instance.visibility_range_end_margin = 25.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _make_grass() -> ArrayMesh:
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	for index: int in 5:
		var angle: float = float(index) * TAU / 5.0
		var right: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var base: Vector3 = right * 0.12
		var tip: Vector3 = Vector3.UP * (0.55 + float(index % 3) * 0.13) + right * 0.22
		vertices.append_array(PackedVector3Array([base - right * 0.045, tip, base + right * 0.045]))
		for vertex: int in 3:
			normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_ruin() -> void:
	# 出生地附近仅保留一处无人遗迹，不设置任务标记。
	if _planet.profile != 0:
		return
	var up: Vector3 = _planet.site["direction"]
	var forward: Vector3 = _planet.site["forward"]
	var right: Vector3 = forward.cross(up)
	var direction: Vector3 = SurfaceSites.offset_direction(up, (forward * 0.7 - right * 0.7).normalized(), 62.0, _planet.radius)
	var height: float = _planet.noise.height(direction)
	if height < 2.0:
		return
	var ruin: Node3D = Node3D.new()
	ruin.name = "SilentArch"
	ruin.position = direction * (_planet.radius + height - 0.3)
	ruin.basis = Basis.looking_at(forward, direction)
	add_child(ruin)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.60, 0.62, 0.59)
	material.roughness = 1.0
	for index: int in 5:
		var size: Vector3 = Vector3(0.9, 4.8, 1.0)
		var location: Vector3 = Vector3(-2.0, 2.0, 0.0)
		if index == 1:
			location = Vector3(2.0, 1.5, 0.0)
			size.y = 3.8
		elif index == 2:
			location = Vector3(-0.7, 4.4, 0.0)
			size = Vector3(3.5, 0.7, 1.1)
		elif index > 2:
			location = Vector3(float(index - 3) * 1.8 + 1.0, 0.1, -2.0)
			size = Vector3(1.8, 0.6, 1.0)
		var body: StaticBody3D = StaticBody3D.new()
		body.position = location
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = box
		visual.material_override = material
		body.add_child(visual)
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		ruin.add_child(body)
