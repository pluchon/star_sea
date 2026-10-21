extends SceneTree

var _failures: Array[String] = []
var _player: StarSeaPlayer
var _planet: Planet
var _caves: CaveSystem


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	root.unfocusable = true
	root.mouse_passthrough = true
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	_player = scene.get_node("Player") as StarSeaPlayer
	_planet = scene.get_node("Universe/PlanetDawn") as Planet
	_caves = _planet.get_node("CaveSystem") as CaveSystem
	_player.controls_enabled = false
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	var data: CaveData = _caves.data
	var network: Dictionary = data.networks[0]
	var constraints: Dictionary = CaveBake.constraints(_planet.noise, network, _planet.noise.features.civilization.data)
	_check(constraints["passed"], "回声洞约束不通过。")
	_check(data.signature == CaveData.source_signature(), "洞穴烘焙签名已经过期。")
	var adjacency: Dictionary = {}
	for i: int in network["nodes"].size():
		adjacency[i] = []
	for edge: Dictionary in network["edges"]:
		adjacency[edge["a"]].append(edge["b"])
		adjacency[edge["b"]].append(edge["a"])
	var connected: bool = true
	for entrance: Dictionary in network["entrances"]:
		var visited: Dictionary = {}
		var queue: Array[int] = [entrance["node"]]
		while not queue.is_empty():
			var id: int = queue.pop_back()
			if visited.has(id):
				continue
			visited[id] = true
			for next: int in adjacency[id]:
				queue.append(next)
		connected = connected and visited.size() == network["nodes"].size()
	var cycles: int = network["edges"].size() - network["nodes"].size() + 1
	_check(connected and cycles >= 1, "洞穴图存在不可达节点或没有环路。")
	var wall_clearance: float = _wall_clearance(network)
	constraints["minimum_unrelated_wall_m"] = wall_clearance
	_check(wall_clearance >= 6, "不相连通道之间的岩壁不足六米。")
	var finite: bool = true
	var sample_count: int = 0
	for node: Dictionary in network["nodes"]:
		if node["kind"] == "shaft_top":
			continue
		var inside: float = CaveData.field(Vector3(node["local"]) + Vector3.UP * 1.7, network["primitives"], null)
		finite = finite and is_finite(inside) and inside < 0
		sample_count += 1
	var outside: float = CaveData.field(Vector3(400, 100, 400), network["primitives"], null)
	_check(finite and is_finite(outside) and outside > 0, "距离场产生非有限值或没有区分洞内外。")
	var seams: Dictionary = _seams(data)
	_check(seams["passed"], "洞穴分块共享单元的顶点不一致。")
	var openings: Array[Dictionary] = _openings(_planet.noise, network)
	for opening: Dictionary in openings:
		_check(opening["passed"], "入口的地形渲染开洞与碰撞开洞不一致。")
	var frame: Transform3D = network["frame"]
	_player.place_at(_planet.to_global(frame * Vector3(0, 0.15, -5)), frame.basis.z, frame.basis.y)
	_player.mode = StarSeaPlayer.Mode.WALK
	var deadline: int = Time.get_ticks_msec() + 60000
	while (not _caves.is_settled() or not (_planet.get_node("Terrain") as PlanetTerrain).is_settled()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_caves.is_settled(), "洞穴运行时加载超时。")
	var walks: Array[Dictionary] = []
	if "--skip-walk" not in OS.get_cmdline_user_args():
		Engine.time_scale = 6
		var walk_network: Dictionary = network.duplicate(true)
		var approach: Vector3 = frame * Vector3(0, 0, -7)
		var approach_id: int = walk_network["nodes"].size()
		walk_network["nodes"].append({"position": approach, "local": Vector3(0, 0, -7), "id": "approach", "kind": "bend"})
		for route: Array in [[approach_id,0,1,2,3,4,5,6,7,6,8,9], [approach_id,0,1,10,11,8,9]]:
			walks.append(await _walk(walk_network, route))
		Engine.time_scale = 1
		for walk: Dictionary in walks:
			_check(walk["passed"], "回声洞实际行走卡住或偏离路线。")
	_player.controls_enabled = false
	var hall: Vector3 = network["nodes"][4]["position"]
	_player.place_at(_planet.to_global(hall + frame.basis.y * 8), frame.basis.z, frame.basis.y)
	_player.mode = StarSeaPlayer.Mode.WALK
	_player._waiting_for_ground = false
	_player.traversal.airborne_time = 1
	_player.set_third_person(true)
	for i: int in 10:
		await process_frame
	var cave_id: int = PlayerTraversal.cave_at(_player)
	var no_glide: bool = not _player.traversal.can_open(false, true, cave_id)
	var camera_below_surface: bool = _planet.to_local(_player.camera.global_position).length() < _planet.surface_radius(_planet.to_local(_player.camera.global_position).normalized()) - 5
	_check(cave_id == 0 and no_glide and camera_below_surface, "洞内识别、滑翔限制或第三人称相机失败。")
	var before_seen: int = _caves.seen.size()
	_caves._reveal(0, hall)
	var map_revealed: bool = _caves.seen.has("0:hall") and _caves.seen.size() >= before_seen
	_check(map_revealed, "洞穴地图没有记录到达的节点。")
	var persistence: Dictionary = CavePersistenceChecks.run(scene)
	_check(persistence["passed"], "洞穴存档往返或非法数据整体拒绝失败。")
	var bytes: int = FileAccess.get_file_as_bytes(CaveData.PATH).size()
	_check(bytes <= 25 * 1024 * 1024, "洞穴数据超过二十五兆字节。")
	_check(_caves.active_lights <= 11, "同时启用的洞内点光源超出预算。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "constraints": constraints, "connected_from_all_entrances": connected, "cycles": cycles, "finite_field_samples": sample_count, "seams": seams, "walks": walks, "cave_id": cave_id, "glide_blocked": no_glide, "camera_below_surface": camera_below_surface, "map_revealed": map_revealed, "persistence": persistence, "bytes": bytes, "chunks": data.chunks.size(), "triangles": data.statistics["triangles"], "maximum_runtime_build_ms": _caves.maximum_build_us / 1000.0, "maximum_mesh_ms": _caves.maximum_mesh_us / 1000.0, "maximum_collision_ms": _caves.maximum_collision_us / 1000.0, "maximum_props_ms": _caves.maximum_props_us / 1000.0, "active_lights": _caves.active_lights}
	report["openings"] = openings
	VerificationMetrics.write_json("res://../test-output/wanderer/cave_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for i: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _check(value: bool, text: String) -> void:
	if not value:
		_failures.append(text)


func _walk(network: Dictionary, route: Array) -> Dictionary:
	var frame: Transform3D = network["frame"]
	var nodes: Array = network["nodes"]
	_player.controls_enabled = false
	_player.mode = StarSeaPlayer.Mode.WALK
	_player.set_third_person(false)
	_player.place_at(_planet.to_global(Vector3(nodes[route[0]]["position"]) + frame.basis.y * 0.15), frame.basis.z, frame.basis.y)
	var deadline: int = Time.get_ticks_msec() + 20000
	while not _caves.is_settled() and Time.get_ticks_msec() < deadline:
		await process_frame
	_player.controls_enabled = true
	Input.action_press("move_forward")
	var target: int = 1
	var elapsed: float = 0.0
	var stuck: float = 0.0
	var previous: Vector3 = _planet.to_local(_player.global_position)
	var sample_time: float = 0.0
	var maximum_error: float = 0.0
	while elapsed < 500 and target < route.size():
		await physics_frame
		var at: Vector3 = _planet.to_local(_player.global_position)
		var destination: Vector3 = nodes[route[target]]["position"]
		var up: Vector3 = at.normalized()
		var desired: Vector3 = (destination - at).slide(up)
		if desired.length() < 0.75:
			target += 1
			continue
		_player.global_basis = Basis.looking_at(desired.normalized(), up)
		await process_frame
		var delta: float = _player.get_physics_process_delta_time()
		elapsed += delta
		sample_time += delta
		if sample_time >= 0.5:
			var now: Vector3 = _planet.to_local(_player.global_position)
			stuck = stuck + sample_time if now.distance_to(previous) < 0.15 else 0.0
			previous = now
			var a: Vector3 = nodes[route[target - 1]]["position"]
			var b: Vector3 = nodes[route[target]]["position"]
			var gap: float = now.distance_to(Geometry3D.get_closest_point_to_segment(now, a, b))
			maximum_error = maxf(maximum_error, gap)
			sample_time = 0
			if stuck > 4 or gap > 8:
				break
	Input.action_release("move_forward")
	_player.controls_enabled = false
	return {"passed": target == route.size(), "route": route, "reached_index": target, "duration_s": elapsed, "maximum_path_error_m": maximum_error, "stuck_s": stuck, "last_local": str(frame.affine_inverse() * _planet.to_local(_player.global_position)), "on_floor": _player.is_on_floor(), "waiting": _player._waiting_for_ground}


func _seams(data: CaveData) -> Dictionary:
	var vertices: Dictionary = {}
	var matches: int = 0
	var maximum: float = 0.0
	for chunk: Dictionary in data.chunks:
		var origin: Vector3 = chunk["origin"]
		var points: PackedVector3Array = chunk["vertices"]
		for index: int in points.size():
			var vertex: Vector3 = points[index]
			if vertex.x > 0.51 and vertex.y > 0.51 and vertex.z > 0.51 and vertex.x < 31.49 and vertex.y < 31.49 and vertex.z < 31.49:
				continue
			var p: Vector3 = vertex + origin
			var key: Vector3i = Vector3i((chunk["cells"] as PackedVector3Array)[index])
			if vertices.has(key):
				maximum = maxf(maximum, p.distance_to(vertices[key]))
				matches += 1
			else:
				vertices[key] = p
	return {"passed": matches > 100 and maximum < 0.001, "matched_vertices": matches, "maximum_error_m": maximum}


func _openings(noise: TerrainNoise, network: Dictionary) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for entrance: Dictionary in network["entrances"]:
		var direction: Vector3 = Vector3(entrance["position"]).normalized()
		var face: int = SurfaceGrid.cell_at(direction, 1).x
		var axes: Array = PlanetTerrain.FACES[face]
		var normal: Vector3 = axes[0]
		var a: Vector3 = axes[1]
		var b: Vector3 = axes[2]
		var u: float = 0
		var v: float = 0
		# 反解实际使用的均匀立方体球面映射，不能用普通归一化立方体的投影代替。
		for iteration: int in 12:
			var low: float = -1
			var high: float = 1
			for step: int in 24:
				var middle: float = (low + high) * 0.5
				if PlanetTerrain.cube_to_sphere(normal + a * middle + b * v).dot(a) < direction.dot(a):
					low = middle
				else:
					high = middle
			u = (low + high) * 0.5
			low = -1
			high = 1
			for step: int in 24:
				var middle: float = (low + high) * 0.5
				if PlanetTerrain.cube_to_sphere(normal + a * u + b * middle).dot(b) < direction.dot(b):
					low = middle
				else:
					high = middle
			v = (low + high) * 0.5
		var size_value: float = 64.0 / noise.radius
		var collision: Dictionary = TerrainChunkBuilder.build(noise, normal, a, b, u - size_value * 0.5, v - size_value * 0.5, size_value, 64, 0, true)
		var render: Dictionary = TerrainChunkBuilder.build(noise, normal, a, b, u - size_value * 0.5, v - size_value * 0.5, size_value, 64, 0.5, false)
		var faces: PackedVector3Array = collision["faces"]
		var center: Vector3 = collision["center"]
		var target: Vector3 = direction * (noise.radius + noise.height(direction))
		var central: int = 0
		var outside: int = 0
		var illegal: int = 0
		for index: int in range(0, faces.size(), 3):
			var p: Vector3 = (faces[index] + faces[index + 1] + faces[index + 2]) / 3 + center
			central += int(p.distance_to(target) < 1.2)
			outside += int(p.distance_to(target) > 10)
			illegal += int(noise.features.in_hole(faces[index] + center) and noise.features.in_hole(faces[index + 1] + center) and noise.features.in_hole(faces[index + 2] + center))
		var render_indices: PackedInt32Array = render["terrain"][Mesh.ARRAY_INDEX]
		var render_vertices: PackedVector3Array = render["terrain"][Mesh.ARRAY_VERTEX]
		var same: bool = render_indices.size() >= faces.size()
		if same:
			for index: int in faces.size():
				if render_vertices[render_indices[index]].distance_to(faces[index]) >= 0.001:
					same = false
					break
		reports.append({"kind": entrance["kind"], "passed": central == 0 and outside > 0 and illegal == 0 and same and faces.size() < 64 * 64 * 6, "center_triangles": central, "outer_triangles": outside, "illegal_hole_triangles": illegal, "render_collision_match": same, "removed_triangles": (64 * 64 * 6 - faces.size()) / 3})
	return reports


func _wall_clearance(network: Dictionary) -> float:
	var minimum: float = INF
	var edges: Array = network["edges"]
	var nodes: Array = network["nodes"]
	for i: int in edges.size():
		for j: int in range(i + 1, edges.size()):
			var a: Dictionary = edges[i]
			var b: Dictionary = edges[j]
			var connected: bool = false
			for x: int in [a["a"], a["b"]]:
				for y: int in [b["a"], b["b"]]:
					connected = connected or x == y
					# 一个交汇处及其紧邻厅室本就连续，不属于相互独立的洞壁。
					for link: Dictionary in edges:
						connected = connected or (link["a"] == x and link["b"] == y) or (link["a"] == y and link["b"] == x)
			if connected or a["profile"] == "shaft" or b["profile"] == "shaft":
				continue
			var start: Vector3 = Vector3(nodes[a["a"]]["local"]) + Vector3.UP * float(a["height"]) * 0.5
			var end: Vector3 = Vector3(nodes[a["b"]]["local"]) + Vector3.UP * float(a["height"]) * 0.5
			var b0: Vector3 = Vector3(nodes[b["a"]]["local"]) + Vector3.UP * float(b["height"]) * 0.5
			var b1: Vector3 = Vector3(nodes[b["b"]]["local"]) + Vector3.UP * float(b["height"]) * 0.5
			var count: int = ceili(start.distance_to(end) / 2)
			for index: int in count + 1:
				var p: Vector3 = start.lerp(end, index / float(count))
				var gap: float = p.distance_to(Geometry3D.get_closest_point_to_segment(p, b0, b1)) - (float(a["width"]) + float(b["width"])) * 0.5 - 1.6
				minimum = minf(minimum, gap)
	return minimum
