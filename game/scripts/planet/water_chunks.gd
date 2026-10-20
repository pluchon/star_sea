class_name WaterChunks
extends Node3D

const ENTER_RANGE: float = 3000.0 # 河湖细节加载距离，米。
const LEAVE_RANGE: float = 4000.0 # 释放距离，米。
const MAX_TASKS: int = 2 # 限制后台队列，避免水面争用地形线程。
var _data: HydrologyData
var _planet: Planet
var _radius: float
var _sides: PackedVector3Array
var _noise: TerrainNoise
var _proxy_waiting: Dictionary = {}
var _proxies: Dictionary = {}
var _owned: Dictionary = {}
var _lake_cells: Dictionary = {}
var _visible: Dictionary = {}
var _tasks: Dictionary = {}
var _elapsed: float = 1.0
var _river_material: ShaderMaterial
var _lake_material: ShaderMaterial
var _fall_material: ShaderMaterial
var _proxy_material: ShaderMaterial
var _pending_requests: int = 1


func build(planet_value: Planet, data_value: HydrologyData) -> void:
	_planet = planet_value
	_radius = planet_value.radius
	_noise = planet_value.noise
	_data = data_value
	_sides.resize(_data.river_points.size())
	for river: int in _data.river_starts.size() - 1:
		var start: int = _data.river_starts[river]
		var end: int = _data.river_starts[river + 1] - 1
		for index: int in range(start, end + 1):
			_sides[index] = _data.river_points[maxi(start, index - 1)].cross(_data.river_points[mini(end, index + 1)]).normalized()
		for index: int in range(_data.river_starts[river], _data.river_starts[river + 1] - 1):
			var bucket: int = HydrologyData.cell_at((_data.river_points[index] + _data.river_points[index + 1]).normalized(), HydrologyData.BUCKET_GRID)
			if not _owned.has(bucket):
				_owned[bucket] = PackedInt32Array()
			var list: PackedInt32Array = _owned[bucket]
			list.append(index)
			_owned[bucket] = list
	var coverage: Dictionary = _data.lake_coverage()
	for cell: int in coverage:
		var lake: int = coverage[cell]
		var bucket: int = HydrologyData.cell_at(HydrologyData.direction_at(cell), HydrologyData.BUCKET_GRID)
		if not _lake_cells.has(bucket):
			_lake_cells[bucket] = []
		(_lake_cells[bucket] as Array).append(Vector2i(cell, lake))
		if not _proxy_waiting.has(lake):
			_proxy_waiting[lake] = []
		(_proxy_waiting[lake] as Array).append(Vector2i(cell, lake))
	_river_material = ShaderMaterial.new()
	_river_material.shader = load("res://shaders/inland_water.gdshader") as Shader
	_river_material.set_shader_parameter("flowing", true)
	_lake_material = _river_material.duplicate() as ShaderMaterial
	_lake_material.set_shader_parameter("flowing", false)
	_proxy_material = _lake_material.duplicate() as ShaderMaterial
	_proxy_material.set_shader_parameter("far_proxy", true)
	_lake_material.set_shader_parameter("near_detail", true)
	_fall_material = _river_material.duplicate() as ShaderMaterial
	_fall_material.set_shader_parameter("falling", true)
	# 大湖保留全局简化水面；细节块只覆盖近处，避免高空湖泊消失。
	for lake: int in _proxy_waiting.keys():
		var start: int = _data.lake_starts[lake]
		var count: int = _data.lake_starts[lake + 1] - start
		if count < 30:
			_proxy_waiting.erase(lake)
			continue


func _process(delta: float) -> void:
	for bucket: int in _tasks.keys():
		var task: Dictionary = _tasks[bucket]
		if WorkerThreadPool.is_task_completed(task["id"]):
			WorkerThreadPool.wait_for_task_completion(task["id"])
			_tasks.erase(bucket)
			var node: Node3D = _upload(task["result"])
			if bucket < 0:
				_proxies[bucket] = node
				for child: Node in node.get_children():
					if child is GeometryInstance3D:
						(child as GeometryInstance3D).visibility_range_end = 20000.0
						(child as MeshInstance3D).material_override = _proxy_material
			else:
				_visible[bucket] = node
				_add_waterfalls(node, bucket)
			break
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0.0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var position_value: Vector3 = _planet.to_local(camera.global_position)
	_pending_requests = 0
	for lake: int in _proxy_waiting.keys():
		var anchor: Vector3 = HydrologyData.direction_at(_data.lake_cells[_data.lake_starts[lake]]) * _radius
		if anchor.distance_to(position_value) < 20000.0:
			if _tasks.size() >= MAX_TASKS:
				_pending_requests += 1
				continue
			var cells: Array = _proxy_waiting[lake]
			_proxy_waiting.erase(lake)
			var task: Dictionary = {"result": {}}
			task["id"] = WorkerThreadPool.add_task(func() -> void: task["result"] = {"origin": anchor, "rivers": [], "falls": [], "lakes": _lake_arrays(cells, anchor)})
			_tasks[-lake - 1] = task
	for bucket: int in _visible.keys():
		if (HydrologyData.direction_at(bucket, HydrologyData.BUCKET_GRID) * _radius).distance_to(position_value) > LEAVE_RANGE:
			(_visible[bucket] as Node3D).queue_free()
			_visible.erase(bucket)
	if position_value.length() - _radius > ENTER_RANGE:
		return
	var direction: Vector3 = position_value.normalized()
	var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
	var right: Vector3 = tangent.cross(direction)
	var nearby: Dictionary = {}
	for x: int in range(-7, 8):
		for y: int in range(-7, 8):
			var sample: Vector3 = direction * _radius + (tangent * x + right * y) * 500.0
			var bucket: int = HydrologyData.cell_at(sample.normalized(), HydrologyData.BUCKET_GRID)
			if (_owned.has(bucket) or _lake_cells.has(bucket)) and not _visible.has(bucket) and not _tasks.has(bucket):
				nearby[bucket] = (HydrologyData.direction_at(bucket, HydrologyData.BUCKET_GRID) * _radius).distance_to(position_value)
	var ordered: Array = nearby.keys()
	ordered.sort_custom(func(a: int, b: int) -> bool: return nearby[a] < nearby[b])
	for bucket: int in ordered:
		if float(nearby[bucket]) > ENTER_RANGE:
			continue
		if _tasks.size() >= MAX_TASKS:
			_pending_requests += 1
			continue
		var task: Dictionary = {"result": {}}
		task["id"] = WorkerThreadPool.add_task(func() -> void: task["result"] = _generate(bucket))
		_tasks[bucket] = task


func is_settled() -> bool:
	return _tasks.is_empty() and _pending_requests == 0


func _generate(bucket: int) -> Dictionary:
	var origin: Vector3 = HydrologyData.direction_at(bucket, HydrologyData.BUCKET_GRID) * _radius
	var river_vertices: PackedVector3Array = []
	var river_uvs: PackedVector2Array = []
	var fall_vertices: PackedVector3Array = []
	var fall_uvs: PackedVector2Array = []
	for index: int in _owned.get(bucket, PackedInt32Array()) as PackedInt32Array:
		var a: Vector3 = _data.river_points[index]
		var b: Vector3 = _data.river_points[index + 1]
		var is_fall: bool = (_data.river_flags[index] & 1) != 0
		var vertices: PackedVector3Array = fall_vertices if is_fall else river_vertices
		var uvs: PackedVector2Array = fall_uvs if is_fall else river_uvs
		var weights: PackedFloat32Array = PackedFloat32Array([0.0, 0.38, 0.62, 1.0] if is_fall else [0.0, 1.0])
		for section: int in weights.size() - 1:
			var quad: PackedVector3Array = []
			for weight: float in [weights[section], weights[section + 1]]:
				var direction: Vector3 = a.slerp(b, weight).normalized()
				var side: Vector3 = _sides[index].lerp(_sides[index + 1], weight).normalized()
				var level_weight: float = smoothstep(0.38, 0.62, weight) if is_fall else weight
				var level: float = lerpf(_data.river_levels[index], _data.river_levels[index + 1], level_weight)
				var width: float = lerpf(_data.river_widths[index], _data.river_widths[index + 1], weight) * 1.15
				for sign_value: float in [-1.0, 1.0]:
					quad.append((direction * _radius + side * width * sign_value).normalized() * (_radius + level) - origin)
			for corner: int in [0, 1, 2, 1, 3, 2]:
				vertices.append(quad[corner])
				uvs.append(Vector2(-1.0 if corner % 2 == 0 else 1.0, (float(index) + weights[section + corner / 2]) * 15.0))
		if is_fall:
			fall_vertices = vertices
			fall_uvs = uvs
		else:
			river_vertices = vertices
			river_uvs = uvs
	return {"origin": origin, "rivers": _arrays(river_vertices, river_uvs, origin), "falls": _arrays(fall_vertices, fall_uvs, origin), "lakes": _lake_arrays(_lake_cells.get(bucket, []), origin)}


func _lake_arrays(cells: Array, origin: Vector3) -> Array:
	var vertices: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	for entry: Vector2i in cells:
		var face: int = entry.x / (HydrologyData.GRID * HydrologyData.GRID)
		var x: int = entry.x % HydrologyData.GRID
		var y: int = (entry.x / HydrologyData.GRID) % HydrologyData.GRID
		var level: float = _data.lake_levels[entry.y]
		for sx: int in 2:
			for sy: int in 2:
				var quad: PackedVector3Array = []
				for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var u: float = (x + float(sx + corner.x) * 0.5) * 2.0 / HydrologyData.GRID - 1.0
					var v: float = (y + float(sy + corner.y) * 0.5) * 2.0 / HydrologyData.GRID - 1.0
					quad.append(HydrologyData.corner(face, u, v))
				for triangle: Array in [[0, 1, 2], [1, 3, 2]]:
					var polygon: Array[Vector3] = []
					for index: int in triangle:
						polygon.append(quad[index])
					var clipped: Array[Vector3] = []
					for index: int in 3:
						var a: Vector3 = polygon[index]
						var b: Vector3 = polygon[(index + 1) % 3]
						var ha: float = _noise.height(a) - level - 0.15
						var hb: float = _noise.height(b) - level - 0.15
						if ha <= 0.0:
							clipped.append(a)
						if (ha < 0.0) != (hb < 0.0):
							clipped.append(a.slerp(b, ha / (ha - hb)).normalized())
					for index: int in range(1, clipped.size() - 1):
						for direction: Vector3 in [clipped[0], clipped[index], clipped[index + 1]]:
							var vertex: Vector3 = direction * (_radius + level) - origin
							vertices.append(vertex)
							uvs.append(Vector2(vertex.x, vertex.z))
	return _arrays(vertices, uvs, origin)


func _arrays(vertices: PackedVector3Array, uvs: PackedVector2Array, origin: Vector3) -> Array:
	if vertices.is_empty():
		return []
	var normals: PackedVector3Array = []
	var uv2s: PackedVector2Array = []
	for vertex: Vector3 in vertices:
		normals.append((vertex + origin).normalized())
		uv2s.append(Vector2(14, 0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	return arrays


func _upload(result: Dictionary) -> Node3D:
	var container: Node3D = Node3D.new()
	container.position = result["origin"]
	add_child(container)
	for key: String in ["rivers", "lakes", "falls"]:
		var arrays: Array = result[key]
		if arrays.is_empty():
			continue
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _lake_material if key == "lakes" else (_fall_material if key == "falls" else _river_material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(instance)
	return container


func _add_waterfalls(container: Node3D, bucket: int) -> void:
	var previous: Vector3 = Vector3.INF
	for index: int in _owned.get(bucket, PackedInt32Array()) as PackedInt32Array:
		if (_data.river_flags[index] & 1) == 0:
			continue
		var position_value: Vector3 = _data.river_points[index] * (_radius + _data.river_levels[index])
		if position_value.distance_to(previous) < 80.0:
			continue
		previous = position_value
		var sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		var loop: AudioStreamWAV = (load("res://audio/waterfall.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		sound.stream = loop
		sound.max_distance = 220.0
		sound.unit_size = 28.0
		sound.volume_db = -12.0
		sound.position = position_value - container.position
		container.add_child(sound)
		sound.play()
		var mist: GPUParticles3D = GPUParticles3D.new()
		mist.amount = 40
		mist.lifetime = 2.0
		mist.position = sound.position
		mist.basis = Basis.looking_at(SurfaceSites.tangent_forward(position_value.normalized()), position_value.normalized())
		var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
		process.direction = Vector3.UP
		process.spread = 45.0
		process.initial_velocity_min = 0.5
		process.initial_velocity_max = 1.5
		process.gravity = Vector3.ZERO
		process.scale_min = 0.2
		process.scale_max = 0.8
		process.color = Color(0.8, 0.9, 0.92, 0.15)
		mist.process_material = process
		var quad: QuadMesh = QuadMesh.new()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		quad.material = material
		mist.draw_pass_1 = quad
		container.add_child(mist)


func _exit_tree() -> void:
	for task: Dictionary in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(task["id"])
