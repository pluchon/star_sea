class_name SurfaceDetails
extends Node3D

const NEAR_DIVISIONS: int = 1024
const FOREST_DIVISIONS: int = 128
const NEAR_DISTANCE: float = 160.0
const FOREST_DISTANCE: float = 1400.0
const KINDS: Array[String] = ["grass", "stone", "broadleaf", "pine", "shrub", "flowers", "fern", "reeds", "mushrooms", "field_stalks"]
# 各类物件在阵风最强时的最大摆幅，单位为米；高大树冠摆得多，灌木和蕨类较稳。
const WIND_SWAY: Dictionary[String, float] = {"grass": 0.17, "stone": 0.0, "broadleaf": 0.32, "pine": 0.26, "shrub": 0.08, "flowers": 0.15, "fern": 0.10, "reeds": 0.24, "mushrooms": 0.0, "field_stalks": 0.08}

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
var _field_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_parent() as Planet
	var shader: Shader = load("res://shaders/surface_detail.gdshader") as Shader
	var solid_shader: Shader = load("res://shaders/surface_solid.gdshader") as Shader
	for kind: String in KINDS:
		_meshes[kind] = mesh_for_kind(kind)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = load("res://shaders/field_stalks.gdshader") as Shader if kind == "field_stalks" else (solid_shader if kind in ["broadleaf", "pine", "stone", "shrub", "mushrooms"] else shader)
		material.set_shader_parameter("wind_strength", WIND_SWAY[kind])
		if kind != "field_stalks":
			material.set_shader_parameter("is_grass", kind == "grass" or kind == "flowers")
			material.set_shader_parameter("bark_color", load("res://textures/painted/bark.svg"))
			material.set_shader_parameter("rock_color", load("res://textures/painted/stone.svg"))
			material.set_shader_parameter("leaf_color", load("res://textures/painted/leaves.svg"))
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


static func mesh_for_kind(kind: String) -> ArrayMesh:
	if kind != "field_stalks":
		return VegetationMeshes.create(kind)
	var scene: Node3D = (load("res://models/vegetation/field_stalks.glb") as PackedScene).instantiate() as Node3D
	var mesh: ArrayMesh = (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh as ArrayMesh
	scene.free()
	return mesh


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
		var transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3((index - (KINDS.size() - 1) * 0.5) * 2.8, 0, 0))
		for fading: bool in [false, true]:
			_add_instances(stage, KINDS[index], [transform], [Color.WHITE])
			var instance: MultiMeshInstance3D = stage.get_child(stage.get_child_count() - 1) as MultiMeshInstance3D
			instance.visibility_range_end = 45.0 if fading else 0.0
			instance.visibility_range_end_margin = 30.0 if fading else 0.0
	var explorer: ExplorerAvatar = ExplorerAvatar.new()
	explorer.position = Vector3(0, 0, 4)
	stage.add_child(explorer)
	for frame: int in 8:
		await get_tree().process_frame
	viewport.queue_free()


func _process(delta: float) -> void:
	var director: SkyDirector = get_tree().current_scene.get_node_or_null("SkyDirector") as SkyDirector if get_tree().current_scene != null else null
	if not get_tree().paused:
		_field_time += delta
	_materials["field_stalks"].set_shader_parameter("field_time", 0.0 if director != null and director.time_paused else _field_time)
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
	var ruin_direction: Vector3 = SurfaceSites.ruin_direction(_planet.site, _planet.radius) if _planet.profile == 0 else Vector3.ZERO
	_task_id = WorkerThreadPool.add_task(func() -> void:
		_result = generate(noise, key, planet_seed, spawn_direction, ruin_direction))


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


static func generate(noise: TerrainNoise, key: Vector4i, planet_seed: int, spawn_direction: Vector3 = Vector3.ZERO, ruin_direction: Vector3 = Vector3.ZERO) -> Dictionary:
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
		var field: Dictionary = noise.features.civilization.terrace_at(direction) if noise.features != null and noise.features.civilization != null else {}
		var plaza: bool = noise.features != null and noise.features.civilization != null and direction.distance_to(noise.features.civilization.data.town["direction"]) * noise.radius < 32.0
		if forest and plaza:
			continue
		if not field.is_empty():
			if forest:
				continue
			var coordinate: Vector2 = noise.features.civilization.field_point(field, direction)
			direction = SurfaceSites.offset_direction(direction, field["across"], snappedf(coordinate.y, 0.8) - coordinate.y, noise.radius)
		var elevation: float = noise.height(direction)
		if elevation < 3.0:
			continue
		# 河面和湖面下不放植被；河岸与湖岸留出芦苇带，树木离水再远一些。
		var water_level: float = noise.water_surface(direction)
		if elevation < water_level + 0.3:
			continue
		if noise.features != null and noise.features.in_clearing(direction):
			continue
		if noise.features != null and noise.features.in_hole(direction * (noise.radius + elevation)):
			continue
		var river_gap: float = noise.river_distance(direction)
		var waterside: bool = river_gap < 9.0 or elevation < water_level + 1.5
		var moisture: float = noise.moisture(direction)
		var temperature: float = noise.temperature(direction, elevation)
		var grove: float = noise.woodland(direction)
		var forest_cover: float = DawnBiomes.forest_cover(elevation, temperature, moisture, grove)
		var kind: String = "grass"
		var scale_value: float = rng.randf_range(0.65, 1.30)
		var tint: Color = Color.WHITE
		var slope: float = noise.slope(direction, elevation)
		if not field.is_empty():
			kind = "field_stalks"
			scale_value = rng.randf_range(0.9, 1.05)
		elif plaza:
			kind = "grass"
			scale_value = rng.randf_range(0.7, 1.0)
		elif forest:
			if elevation < 16.0 or elevation > 1600.0 or slope > 0.65 or temperature < 0.16 or river_gap < 7.0 or waterside:
				continue
			if rng.randf() > 0.035 + forest_cover * 0.82:
				continue
			if temperature < 0.24 or elevation > 1400.0 or moisture < 0.34:
				continue
			kind = "pine" if temperature < 0.50 or elevation > 750.0 else "broadleaf"
			tint = Color(0.77, 0.92, 0.84).lerp(Color(1.08, 1.02, 0.78), rng.randf())
		elif index > 618:
			# 晨每块只保留五个石块候选点，其中一个稍大；降低遮挡并扩大开局视野。
			if noise.profile == 0 and index not in [632, 636, 640, 644, 648]:
				continue
			if slope > 1.25:
				continue
			kind = "stone"
			scale_value = rng.randf_range(0.2, 0.65) if noise.profile == 0 else rng.randf_range(0.15, 1.3)
			if index > 644 and noise.profile == 0:
				scale_value = rng.randf_range(0.75, 1.1)
			tint = Color(0.72, 0.76, 0.75).lerp(Color(1.1, 1.03, 0.91), rng.randf())
			if noise.profile == 0:
				tint.a = smoothstep(0.48, 0.80, moisture) * (1.0 - smoothstep(1100.0, 1500.0, elevation))
		elif noise.profile != 0 or elevation < 9.0 or elevation > 1550.0 or slope > 0.9:
			continue
		elif noise.profile == 0 and index > 580 and elevation < 100.0 and moisture > 0.72 and slope < 0.3:
			kind = "reeds"
			scale_value = rng.randf_range(0.65, 1.05)
		elif noise.profile == 0 and index > 540 and waterside and slope < 0.5 and temperature > 0.24:
			kind = "reeds"
			scale_value = rng.randf_range(0.7, 1.15)
		elif noise.profile == 0 and index > 600 and forest_cover > 0.35 and moisture > 0.58:
			kind = "fern"
			scale_value = rng.randf_range(0.65, 1.4)
		elif index > 575 and index < 585 and forest_cover > 0.38 and moisture > 0.55:
			kind = "mushrooms"
			scale_value = rng.randf_range(0.75, 1.2)
		elif index > 600 and grove > 0.38 and moisture > 0.35:
			kind = "shrub"
			scale_value = rng.randf_range(0.6, 1.6)
			if temperature < 0.28 or elevation > 1250.0:
				scale_value *= 0.36
				tint = Color(0.93, 0.81, 0.91)
		elif index > 560 and moisture > 0.36 and temperature > 0.40:
			kind = "flowers"
			tint = Color(1.05, 0.94, 0.85) if index % 2 == 0 else Color(0.82, 0.85, 1.15)
		else:
			if rng.randf() > (0.35 + moisture * 0.45) * lerpf(1.0, 0.28, smoothstep(1150.0, 1500.0, elevation)):
				continue
			tint = Color(0.68, 0.85, 0.64).lerp(Color(1.03, 0.97, 0.72), 1.0 - moisture)
			if grove > 0.7:
				tint *= 0.84
			if moisture < 0.38:
				tint = Color(1.22, 1.03, 0.68)
			if temperature < 0.26:
				scale_value *= 0.5
		var tangent: Vector3 = SurfaceSites.tangent_forward(direction).rotated(direction, rng.randf() * TAU)
		var basis: Basis = Basis.looking_at(tangent, direction).scaled(Vector3.ONE * scale_value)
		if noise.profile == 0 and (kind == "broadleaf" or kind == "pine" or kind == "stone"):
			basis = basis.scaled_local(Vector3(rng.randf_range(0.85, 1.18), rng.randf_range(0.82, 1.20), rng.randf_range(0.85, 1.18)))
		# 出生点保留固定空地，避免开始旅程时落在树干或巨石内部。
		var clearance: float = 32.0 if kind == "stone" else (12.0 if kind == "broadleaf" or kind == "pine" else 6.0)
		if kind != "grass" and kind != "flowers" and direction.distance_to(spawn_direction) * noise.radius < clearance:
			continue
		# 拱门通道与倒塌石块周围保留空地，树冠也不能穿入拱券。
		var ruin_clearance: float = 10.0 if kind == "broadleaf" or kind == "pine" else (7.0 if kind == "stone" or kind == "shrub" else 4.0)
		if direction.distance_to(ruin_direction) * noise.radius < ruin_clearance:
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
	if forest and noise.features != null and noise.features.civilization != null:
		for direction: Vector3 in noise.features.civilization.data.trees:
			if SurfaceGrid.cell_at(direction, divisions) != cell:
				continue
			var basis: Basis = Basis.looking_at(SurfaceSites.tangent_forward(direction), direction)
			(result["broadleaf"] as Array[Transform3D]).append(Transform3D(basis, direction * (noise.radius + noise.height(direction) - 0.08) - center))
			(result["broadleaf_colors"] as Array[Color]).append(Color(0.84, 0.94, 0.8))
	return result


func _add_instances(parent: Node3D, kind: String, transforms: Array, colors: Array) -> void:
	if transforms.is_empty():
		return
	if kind != "broadleaf" and kind != "pine":
		_add_batch(parent, kind, transforms, colors)
		return
	# MultiMesh 整批共用细节层级；按切平面划小批次，避免一棵近树使整片树林使用高精度网格。
	var up: Vector3 = parent.position.normalized() if parent.position.length_squared() > 1.0 else Vector3.UP
	var forward: Vector3 = SurfaceSites.tangent_forward(up)
	var right: Vector3 = forward.cross(up)
	var groups: Dictionary = {}
	for index: int in transforms.size():
		var transform: Transform3D = transforms[index]
		var key: Vector2i = Vector2i(floori(transform.origin.dot(forward) / 128.0), floori(transform.origin.dot(right) / 128.0))
		if not groups.has(key):
			groups[key] = {"transforms": [], "colors": []}
		groups[key]["transforms"].append(transform)
		groups[key]["colors"].append(colors[index])
	for group: Dictionary in groups.values():
		_add_batch(parent, kind, group["transforms"], group["colors"])


func _add_batch(parent: Node3D, kind: String, transforms: Array, colors: Array) -> void:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = _meshes[kind]
	multi.instance_count = transforms.size()
	for index: int in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colors[index])
		multi.set_instance_custom_data(index, Color(float(index) / transforms.size(), (colors[index] as Color).a if kind == "stone" else 0.0, 0.0))
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = kind.capitalize()
	instance.multimesh = multi
	instance.material_override = _materials[kind]
	var tree: bool = kind == "broadleaf" or kind == "pine"
	instance.visibility_range_end = 1800.0 if tree else 230.0
	instance.visibility_range_end_margin = 90.0 if tree else 30.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if kind == "field_stalks":
		# 干秆都是封闭网格，不用透明渐隐，避免整批稻秆进入透明绘制通道。
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		instance.visibility_range_end_margin = 0.0
	# 小型薄叶不投影，避免亚像素叶片在草地上形成密集闪点；树木、灌木和岩石保留投影。
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in ["broadleaf", "pine", "stone", "shrub"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
			var vertical_scale: float = transform.basis.get_scale().y
			var shape: CapsuleShape3D = CapsuleShape3D.new()
			shape.radius = 0.38 * scale_value
			shape.height = 6.0 * vertical_scale
			var collider: CollisionShape3D = CollisionShape3D.new()
			if index < trunks.size():
				collider.shape = shape
				collider.position.y = 3.0 * vertical_scale
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
	var forward: Vector3 = _planet.site["forward"]
	var direction: Vector3 = SurfaceSites.ruin_direction(_planet.site, _planet.radius)
	var height: float = _planet.noise.height(direction)
	if height < 2.0:
		return
	var ruin: Node3D = Node3D.new()
	ruin.name = "SilentArch"
	ruin.position = direction * (_planet.radius + height - 0.3)
	ruin.basis = Basis.looking_at(forward, direction)
	add_child(ruin)
	for side: float in [-1.0, 1.0]:
		_ruin_piece(ruin, StoneworkMeshes.block(Vector3(1.4, 0.65, 1.65), int(side + 5)), Vector3(side * 2.025, 0.0, 0.0))
		for course: int in 4:
			var size: Vector3 = Vector3(0.78 + sin(course * 2.0) * 0.04, 0.67, 1.05)
			_ruin_piece(ruin, StoneworkMeshes.block(size, course + int(side * 11)), Vector3(side * 2.025, 0.68 + course * 0.69, 0.0))
		_ruin_piece(ruin, StoneworkMeshes.block(Vector3(1.02, 0.24, 1.25), int(side * 13)), Vector3(side * 2.025, 2.98, 0.0))
	for index: int in 9:
		var angle: float = -PI * 0.5 + (index + 0.5) * PI / 9.0
		var mesh: ArrayMesh = StoneworkMeshes.block(Vector3(2.025 * PI / 9.0 - 0.025, 0.75, 1.10), index + 30, Vector2(angle, 2.025))
		_ruin_piece(ruin, mesh, Vector3(0, 3.10, 0))
	for index: int in 4:
		var location: Vector3 = Vector3(3.4 + (index % 2) * 0.95, 0.15 + (index / 2) * 0.18, -1.1 - index * 0.7)
		_ruin_piece(ruin, StoneworkMeshes.block(Vector3(0.9, 0.65, 1.1), index + 50), location, Vector3(0.08 * index, index * 0.61, 0.14 * (index - 1)))


func _ruin_piece(parent: Node3D, mesh: ArrayMesh, location: Vector3, angles: Vector3 = Vector3.ZERO) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 2
	body.position = location
	body.rotation = angles
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _materials["stone"]
	body.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = mesh.create_convex_shape()
	body.add_child(collision)
	parent.add_child(body)
