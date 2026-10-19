class_name SurfaceDetails
extends Node3D

const NEAR_DIVISIONS: int = 1024
const FOREST_DIVISIONS: int = 128
const NEAR_DISTANCE: float = 160.0
const FOREST_DISTANCE: float = 1400.0
const KINDS: Array[String] = ["grass", "stone", "broadleaf", "pine", "shrub", "flowers"]

var _planet: Planet
var _tiles: Dictionary[Vector4i, Node3D] = {}
var _desired: Dictionary = {}
var _needed: Array[Vector4i] = []
var _meshes: Dictionary[String, ArrayMesh] = {}
var _materials: Dictionary[String, ShaderMaterial] = {}
var _colliders: Dictionary[String, StaticBody3D] = {}
var _stone_shape: ConvexPolygonShape3D
var _elapsed: float = 0.0
var _collision_elapsed: float = 0.0
var _last_position: Vector3 = Vector3.INF
var _near_enabled: bool = false
var _task_id: int = -1
var _pending_key: Vector4i
var _result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_parent() as Planet
	var shader: Shader = load("res://shaders/surface_detail.gdshader") as Shader
	for kind: String in KINDS:
		_meshes[kind] = VegetationMeshes.create(kind)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("wind_strength", 0.0 if kind == "stone" else 0.14)
		material.set_shader_parameter("is_grass", kind == "grass" or kind == "flowers")
		_materials[kind] = material
	_stone_shape = _meshes["stone"].create_convex_shape()
	# 实际使用的树冠、草叶和投影材质均在首次进入地表前实例化。
	var warmup: Node3D = Node3D.new()
	warmup.name = "MaterialWarmup"
	warmup.visible = false
	add_child(warmup)
	for kind: String in KINDS:
		_add_instances(warmup, kind, [Transform3D.IDENTITY], [Color.WHITE])
	if _planet.profile == 0 and DisplayServer.get_name() != "headless":
		_warm_draw_variants.call_deferred()
	_make_ruin()


func _warm_draw_variants() -> void:
	# 距离渐隐会启用额外绘制路径；启动时在独立视口实际绘制，覆盖隐藏实例无法触发的路径。
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "VegetationPipelineWarmup"
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage: Node3D = Node3D.new()
	viewport.add_child(stage)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.position = Vector3(0, 5, 30)
	stage.add_child(camera)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	stage.add_child(sun)
	for index: int in KINDS.size():
		var transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(index * 3.2 - 8.0, 0, 0))
		for fading: bool in [false, true]:
			_add_instances(stage, KINDS[index], [transform], [Color.WHITE])
			var instance: MultiMeshInstance3D = stage.get_child(stage.get_child_count() - 1) as MultiMeshInstance3D
			instance.visibility_range_end = 45.0 if fading else 0.0
			instance.visibility_range_end_margin = 30.0 if fading else 0.0
	for frame: int in 8:
		await get_tree().process_frame
	viewport.queue_free()


func _process(delta: float) -> void:
	_collect_tile()
	_elapsed += delta
	_collision_elapsed += delta
	if _elapsed < 0.04:
		return
	_elapsed = 0.0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var local: Vector3 = _planet.to_local(camera.global_position)
	var up: Vector3 = local.normalized()
	var altitude: float = local.length() - _planet.surface_radius(up)
	visible = altitude < 2200.0
	if not visible:
		_clear_colliders()
		return
	var near_enabled: bool = altitude < 220.0
	if local.distance_to(_last_position) > 20.0 or near_enabled != _near_enabled:
		_last_position = local
		_near_enabled = near_enabled
		_update_desired(up)
	if _task_id == -1 and not _needed.is_empty():
		_request_tile(_needed.pop_front())
	if _collision_elapsed > 0.5:
		_collision_elapsed = 0.0
		_refresh_colliders(local)


func _update_desired(up: Vector3) -> void:
	_desired.clear()
	_needed.clear()
	var near_keys: Array[Vector3i] = []
	var forest_keys: Array[Vector3i] = []
	if _near_enabled:
		near_keys = SurfaceGrid.nearby(up, _planet.radius, NEAR_DISTANCE, NEAR_DIVISIONS)
	if _planet.profile == 0:
		forest_keys = SurfaceGrid.nearby(up, _planet.radius, FOREST_DISTANCE, FOREST_DIVISIONS)
	# 近景和树林交替生成，避免草地全部上传之后才出现树木。
	for index: int in maxi(near_keys.size(), forest_keys.size()):
		if index < near_keys.size():
			var key: Vector3i = near_keys[index]
			_desired[Vector4i(NEAR_DIVISIONS, key.x, key.y, key.z)] = true
		if index < forest_keys.size():
			var key: Vector3i = forest_keys[index]
			_desired[Vector4i(FOREST_DIVISIONS, key.x, key.y, key.z)] = true
	for key: Vector4i in _tiles.keys():
		if not _desired.has(key):
			_tiles[key].queue_free()
			_tiles.erase(key)
	for key: Vector4i in _desired:
		if not _tiles.has(key) and not (_task_id != -1 and key == _pending_key):
			_needed.append(key)


func _request_tile(key: Vector4i) -> void:
	_pending_key = key
	var noise: TerrainNoise = _planet.noise
	var planet_seed: int = _planet.planet_seed
	var spawn_direction: Vector3 = _planet.site["direction"]
	_task_id = WorkerThreadPool.add_task(func() -> void:
		_result = generate(noise, key, planet_seed, spawn_direction))


func _collect_tile() -> void:
	if _task_id == -1 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	if _desired.has(_pending_key) and not _tiles.has(_pending_key):
		var tile: Node3D = Node3D.new()
		tile.position = _result["center"]
		add_child(tile)
		for kind: String in KINDS:
			_add_instances(tile, kind, _result[kind], _result[kind + "_colors"])
		tile.set_meta("trunks", _result["broadleaf"] + _result["pine"])
		tile.set_meta("rocks", _result["stone"])
		_tiles[_pending_key] = tile
	_result = {}


func is_settled() -> bool:
	return visible and _task_id == -1 and _needed.is_empty() and not _desired.is_empty()


static func generate(noise: TerrainNoise, key: Vector4i, planet_seed: int, spawn_direction: Vector3 = Vector3.ZERO) -> Dictionary:
	var divisions: int = key.x
	var cell: Vector3i = Vector3i(key.y, key.z, key.w)
	var center: Vector3 = SurfaceGrid.direction(cell, divisions) * noise.radius
	var result: Dictionary = {"center": center}
	for kind: String in KINDS:
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		result[kind] = transforms
		result[kind + "_colors"] = colors
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(key) + planet_seed
	var forest: bool = divisions == FOREST_DIVISIONS
	for index: int in (440 if forest else 650):
		var direction: Vector3 = SurfaceGrid.direction(cell, divisions, Vector2(rng.randf(), rng.randf()))
		var elevation: float = noise.height(direction)
		if elevation < 3.0:
			continue
		var moisture: float = noise.moisture(direction)
		var temperature: float = noise.temperature(direction, elevation)
		var grove: float = noise.woodland(direction)
		var kind: String = "grass"
		var scale_value: float = rng.randf_range(0.65, 1.30)
		var tint: Color = Color.WHITE
		var slope: float = noise.slope(direction, elevation)
		if forest:
			if elevation < 16.0 or elevation > 1600.0 or slope > 0.65 or temperature < 0.16:
				continue
			if rng.randf() > (0.08 + grove * 0.72) * smoothstep(0.20, 0.65, moisture):
				continue
			kind = "pine" if temperature < 0.48 or elevation > 750.0 else "broadleaf"
			tint = Color(0.77, 0.87, 0.72).lerp(Color(1.08, 1.02, 0.78), rng.randf())
		elif index > 618:
			kind = "stone"
			scale_value = rng.randf_range(0.15, 1.3)
			if index > 644 and noise.profile == 0:
				scale_value = rng.randf_range(1.4, 3.0)
			tint = Color(0.72, 0.76, 0.75).lerp(Color(1.1, 1.03, 0.91), rng.randf())
		elif noise.profile != 0 or elevation < 9.0 or elevation > 1550.0 or slope > 0.9:
			continue
		elif index > 600 and grove > 0.38 and moisture > 0.35:
			kind = "shrub"
			scale_value = rng.randf_range(0.6, 1.6)
		elif index > 560 and moisture > 0.36 and temperature > 0.40:
			kind = "flowers"
			tint = Color(1.05, 0.94, 0.85) if index % 2 == 0 else Color(0.82, 0.85, 1.15)
		else:
			if rng.randf() > 0.45 + moisture * 0.5:
				continue
			tint = Color(0.68, 0.85, 0.64).lerp(Color(1.03, 0.97, 0.72), 1.0 - moisture)
			if grove > 0.7:
				tint *= 0.84
		var tangent: Vector3 = SurfaceSites.tangent_forward(direction).rotated(direction, rng.randf() * TAU)
		var basis: Basis = Basis.looking_at(tangent, direction).scaled(Vector3.ONE * scale_value)
		# 出生点保留固定空地，避免开始旅程时落在树干或巨石内部。
		var clearance: float = 12.0 if kind == "broadleaf" or kind == "pine" else 6.0
		if kind != "grass" and kind != "flowers" and direction.distance_to(spawn_direction) * noise.radius < clearance:
			continue
		var surface_position: Vector3 = direction * (noise.radius + elevation - 0.08)
		# 球面坐标以单精度保存；用最终位置重新采样，避免陡坡的方向舍入放大贴地误差。
		for correction: int in 2:
			var actual_direction: Vector3 = surface_position.normalized()
			var radial_error: float = noise.radius + noise.height(actual_direction) - 0.08 - surface_position.length()
			surface_position += actual_direction * radial_error
		var position_local: Vector3 = surface_position - center
		(result[kind] as Array[Transform3D]).append(Transform3D(basis, position_local))
		(result[kind + "_colors"] as Array[Color]).append(tint)
	return result


func _add_instances(parent: Node3D, kind: String, transforms: Array, colors: Array) -> void:
	if transforms.is_empty():
		return
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = _meshes[kind]
	multi.instance_count = transforms.size()
	for index: int in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colors[index])
		multi.set_instance_custom_data(index, Color(float(index) / transforms.size(), 0.0, 0.0))
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = kind.capitalize()
	instance.multimesh = multi
	instance.material_override = _materials[kind]
	var tree: bool = kind == "broadleaf" or kind == "pine"
	instance.visibility_range_end = 1800.0 if tree else 230.0
	instance.visibility_range_end_margin = 90.0 if tree else 30.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind != "grass" and kind != "flowers" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.8
	parent.add_child(instance)


func _refresh_colliders(camera_position: Vector3) -> void:
	# 本轮实体碰撞只完善晨，其他星球沿用原型行为。
	if _planet.profile != 0:
		return
	var desired: Dictionary = {}
	for key: Vector4i in _tiles:
		var tile: Node3D = _tiles[key]
		if tile.position.distance_to(camera_position) > 800.0:
			continue
		var trunks: Array = tile.get_meta("trunks")
		var obstacles: Array = trunks + (tile.get_meta("rocks") as Array)
		for index: int in obstacles.size():
			var transform: Transform3D = obstacles[index]
			var position_local: Vector3 = tile.position + transform.origin
			if position_local.distance_to(camera_position) > 65.0:
				continue
			var identity: String = str(key) + "/" + str(index)
			desired[identity] = true
			if _colliders.has(identity):
				continue
			var body: StaticBody3D = StaticBody3D.new()
			body.collision_layer = 2
			body.set_meta("ecology_obstacle", true)
			body.set_meta("ecology_kind", "tree" if index < trunks.size() else "stone")
			body.position = position_local
			body.basis = transform.basis.orthonormalized()
			var scale_value: float = transform.basis.get_scale().x
			var shape: CapsuleShape3D = CapsuleShape3D.new()
			shape.radius = 0.38 * scale_value
			shape.height = 6.0 * scale_value
			var collider: CollisionShape3D = CollisionShape3D.new()
			if index < trunks.size():
				collider.shape = shape
				collider.position.y = 3.0 * scale_value
			else:
				collider.shape = _stone_shape
				body.basis = transform.basis
			body.add_child(collider)
			add_child(body)
			_colliders[identity] = body
	for identity: String in _colliders.keys():
		if not desired.has(identity):
			_colliders[identity].queue_free()
			_colliders.erase(identity)


func _clear_colliders() -> void:
	for body: StaticBody3D in _colliders.values():
		body.queue_free()
	_colliders.clear()


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


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
