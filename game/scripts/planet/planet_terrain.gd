class_name PlanetTerrain
extends Node3D

const GRID: int = 32
const MAX_DEPTH: int = 11
const SPLIT_FACTOR: float = 2.2
const MERGE_FACTOR: float = 2.6
const UPDATE_INTERVAL: float = 0.15
const MAX_TASKS: int = 6
const MAX_UPLOADS_PER_FRAME: int = 4
const COLLISION_RANGE: float = 600.0
const FACES: Array = [
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]

class TerrainNode:
	extends RefCounted
	var face: int
	var u0: float
	var v0: float
	var size: float
	var depth: int
	var edge_m: float
	var center_local: Vector3
	var children: Array[TerrainNode] = []
	var mesh_instance: MeshInstance3D
	var water_instance: MeshInstance3D
	var collider: StaticBody3D
	var task_id: int = -1
	var result: Dictionary = {}
	var wants_collision: bool = false
	var collision_task: bool = false
	var cancelled: bool = false

var uploaded_this_frame: int = 0
var upload_us: int = 0
var maximum_upload_us: int = 0
var generated_tasks: int = 0
var generation_us: int = 0
var visible_chunks: int = 0
var pending_requests: int = 0
var radius: float
var _planet: Planet
var _noise: TerrainNoise
var _camera: Camera3D
var _roots: Array[TerrainNode] = []
var _running: Array[TerrainNode] = []
var _uploads: Array[TerrainNode] = []
var _elapsed: float = UPDATE_INTERVAL
var _terrain_material: ShaderMaterial
var _water_material: ShaderMaterial


func _ready() -> void:
	# 暂停菜单保留世界画面，后台完成的分块仍需上传。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_parent() as Planet
	radius = _planet.radius
	_noise = _planet.noise
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load("res://shaders/terrain.gdshader") as Shader
	_water_material = ShaderMaterial.new()
	_water_material.shader = load("res://shaders/water.gdshader") as Shader
	if _planet.profile == 1:
		_terrain_material.set_shader_parameter("snow_height", 9000.0)
		_terrain_material.set_shader_parameter("sand", Color(0.84, 0.51, 0.32))
		_terrain_material.set_shader_parameter("grass", Color(0.72, 0.37, 0.26))
		_terrain_material.set_shader_parameter("grass_far", Color(0.82, 0.52, 0.36))
		_terrain_material.set_shader_parameter("rock", Color(0.40, 0.26, 0.34))
	elif _planet.profile == 2:
		_terrain_material.set_shader_parameter("snow_height", 260.0)
		_terrain_material.set_shader_parameter("sand", Color(0.77, 0.83, 0.88))
		_terrain_material.set_shader_parameter("grass", Color(0.68, 0.77, 0.82))
		_terrain_material.set_shader_parameter("grass_far", Color(0.88, 0.91, 0.96))
		_terrain_material.set_shader_parameter("rock", Color(0.38, 0.43, 0.61))
		_water_material.set_shader_parameter("shallow", Color(0.43, 0.70, 0.81))
		_water_material.set_shader_parameter("deep", Color(0.15, 0.25, 0.44))
	for face: int in FACES.size():
		var axes: Array = FACES[face]
		assert((axes[1] as Vector3).cross(axes[2]).is_equal_approx(axes[0]))
		_roots.append(_make_node(face, -1.0, -1.0, 2.0, 0))


static func cube_to_sphere(point: Vector3) -> Vector3:
	var x2: float = point.x * point.x
	var y2: float = point.y * point.y
	var z2: float = point.z * point.z
	return Vector3(
		point.x * sqrt(1.0 - y2 * 0.5 - z2 * 0.5 + y2 * z2 / 3.0),
		point.y * sqrt(1.0 - z2 * 0.5 - x2 * 0.5 + z2 * x2 / 3.0),
		point.z * sqrt(1.0 - x2 * 0.5 - y2 * 0.5 + x2 * y2 / 3.0))


func _make_node(face: int, u0: float, v0: float, size: float, depth: int) -> TerrainNode:
	var node: TerrainNode = TerrainNode.new()
	node.face = face
	node.u0 = u0
	node.v0 = v0
	node.size = size
	node.depth = depth
	node.edge_m = radius * size * 0.785
	var axes: Array = FACES[face]
	var direction: Vector3 = cube_to_sphere(axes[0] + axes[1] * (u0 + size * 0.5) + axes[2] * (v0 + size * 0.5))
	node.center_local = direction * (radius + _noise.height(direction))
	return node


func _process(delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	_terrain_material.set_shader_parameter("planet_center", _planet.global_position)
	_water_material.set_shader_parameter("planet_center", _planet.global_position)
	uploaded_this_frame = 0
	upload_us = 0
	_collect_completed()
	var upload_start: int = Time.get_ticks_usec()
	while not _uploads.is_empty() and uploaded_this_frame < MAX_UPLOADS_PER_FRAME:
		if uploaded_this_frame > 0 and Time.get_ticks_usec() - upload_start >= 1000:
			break
		# 碰撞资源的构建开销较高，单独占用一帧的上传额度。
		if _uploads[0].collision_task and uploaded_this_frame > 0:
			break
		var node: TerrainNode = _uploads.pop_front()
		if not node.cancelled:
			_upload(node)
			uploaded_this_frame += 1
			if node.collision_task:
				break
		else:
			node.result = {}
	upload_us = Time.get_ticks_usec() - upload_start
	maximum_upload_us = maxi(maximum_upload_us, upload_us)
	_elapsed += delta
	if _elapsed >= UPDATE_INTERVAL:
		_elapsed = 0.0
		pending_requests = 0
		visible_chunks = 0
		var camera_position: Vector3 = to_local(_camera.global_position)
		for node: TerrainNode in _roots:
			_visit(node, camera_position)


func _visit(node: TerrainNode, camera_position: Vector3) -> void:
	var distance: float = camera_position.distance_to(node.center_local)
	node.wants_collision = node.depth == MAX_DEPTH and distance < COLLISION_RANGE
	if is_instance_valid(node.collider) and not node.wants_collision:
		node.collider.queue_free()
		node.collider = null
	if node.mesh_instance == null:
		_request_build(node, false)
		return
	if node.wants_collision and node.collider == null:
		_request_build(node, true)
	var above_horizon: bool = _above_horizon(node, camera_position)
	var split: bool = node.depth < MAX_DEPTH and distance < node.edge_m * SPLIT_FACTOR and above_horizon
	var merge: bool = distance > node.edge_m * MERGE_FACTOR or not above_horizon
	if split and node.children.is_empty():
		var half: float = node.size * 0.5
		for row: int in 2:
			for column: int in 2:
				node.children.append(_make_node(node.face, node.u0 + half * column, node.v0 + half * row, half, node.depth + 1))
	if not node.children.is_empty() and not merge:
		var ready: bool = true
		for child: TerrainNode in node.children:
			if child.mesh_instance == null:
				_request_build(child, false)
				ready = false
		if ready:
			_set_visible(node, false)
			for child: TerrainNode in node.children:
				_visit(child, camera_position)
			return
		# 子块全部可见之前保留父块，避免分级细化时短暂露出空洞。
		for child: TerrainNode in node.children:
			_hide_subtree(child)
	elif merge:
		_free_children(node)
	_set_visible(node, true)
	visible_chunks += 1


func _above_horizon(node: TerrainNode, camera_position: Vector3) -> bool:
	var horizon: float = sqrt(maxf(camera_position.length_squared() - radius * radius, 0.0))
	var reach: float = sqrt(pow(radius + TerrainNoise.MAX_HEIGHT, 2.0) - radius * radius)
	return camera_position.distance_to(node.center_local) < horizon + reach + node.edge_m


func _request_build(node: TerrainNode, collision: bool) -> void:
	pending_requests += 1
	if node.task_id != -1 or not node.result.is_empty() or _running.size() >= MAX_TASKS:
		return
	var axes: Array = FACES[node.face]
	var normal: Vector3 = axes[0]
	var axis_a: Vector3 = axes[1]
	var axis_b: Vector3 = axes[2]
	var u0: float = node.u0
	var v0: float = node.v0
	var size: float = node.size
	var skirt: float = node.edge_m * 0.03
	node.collision_task = collision
	var noise: TerrainNoise = _noise
	node.task_id = WorkerThreadPool.add_task(func() -> void:
		node.result = TerrainChunkBuilder.build(noise, normal, axis_a, axis_b, u0, v0, size, GRID, skirt, collision))
	_running.append(node)


func _collect_completed() -> void:
	for index: int in range(_running.size() - 1, -1, -1):
		var node: TerrainNode = _running[index]
		if WorkerThreadPool.is_task_completed(node.task_id):
			WorkerThreadPool.wait_for_task_completion(node.task_id)
			node.task_id = -1
			_running.remove_at(index)
			generated_tasks += 1
			generation_us += int(node.result.get("build_us", 0))
			_uploads.append(node)


func _upload(node: TerrainNode) -> void:
	if node.collision_task:
		if node.wants_collision and node.collider == null:
			var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
			shape.set_faces(node.result["faces"])
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = shape
			node.collider = StaticBody3D.new()
			node.collider.position = node.result["center"]
			node.collider.add_child(collision)
			add_child(node.collider)
	else:
		node.mesh_instance = _create_mesh(node.result["terrain"], _terrain_material, node.result["center"])
		var water: Array = node.result["water"]
		if not water.is_empty():
			node.water_instance = _create_mesh(water, _water_material, node.result["center"])
			node.water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.result = {}


func _create_mesh(arrays: Array, material: ShaderMaterial, center: Vector3) -> MeshInstance3D:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.visible = false
	add_child(instance)
	return instance


func _set_visible(node: TerrainNode, enabled: bool) -> void:
	if is_instance_valid(node.mesh_instance):
		node.mesh_instance.visible = enabled
	if is_instance_valid(node.water_instance):
		node.water_instance.visible = enabled


func _hide_subtree(node: TerrainNode) -> void:
	_set_visible(node, false)
	for child: TerrainNode in node.children:
		_hide_subtree(child)


func _free_children(node: TerrainNode) -> void:
	for child: TerrainNode in node.children:
		_dispose(child)
	node.children.clear()


func _dispose(node: TerrainNode) -> void:
	node.cancelled = true
	_free_children(node)
	if is_instance_valid(node.mesh_instance):
		node.mesh_instance.queue_free()
	if is_instance_valid(node.water_instance):
		node.water_instance.queue_free()
	if is_instance_valid(node.collider):
		node.collider.queue_free()


func is_settled() -> bool:
	return pending_requests == 0 and _running.is_empty() and _uploads.is_empty()


func _exit_tree() -> void:
	# 退出和场景切换也必须回收任务，不能只依赖每帧轮询。
	for node: TerrainNode in _running:
		WorkerThreadPool.wait_for_task_completion(node.task_id)
	_running.clear()
	_uploads.clear()
