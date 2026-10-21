extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000, 0)
	var data: CivilizationData = noise.features.civilization.data
	var town: Vector3 = data.town["direction"]
	var spawn: Vector3 = noise.features.site["direction"]
	var distance: float = spawn.angle_to(town) * noise.radius
	var river: Vector4 = noise.features.hydrology.nearest(town)
	_require(distance >= 4000 and distance <= CivilizationSiting.TOWN_FALLBACK_DISTANCE, "古城距离超过已记录的搜索范围。")
	_require(river.x >= 60.0 and river.x <= 120.1 and river.z >= 3.0 + 2.2 * sqrt(float(data.town["minimum_area_km2"])), "古城河岸距离或汇水面积不足。")
	var plaza_error: float = 0.0
	for angle: int in 24:
		for radius: float in [0.0, 10.0, 20.0, 30.0]:
			var direction: Vector3 = SurfaceSites.offset_direction(town, Vector3(data.town["along"]).rotated(town, angle * TAU / 24), radius, noise.radius)
			plaza_error = maxf(plaza_error, absf(noise.height(direction) - float(data.town["level"])))
	_require(plaza_error <= 0.1, "广场三十米内高度不一致。")
	var counts: Dictionary = {}
	var triangles: int = 0
	var batches: Dictionary = {}
	var foundation_error: float = 0.0
	var wet_foundations: int = 0
	var wet_records: Array[Dictionary] = []
	var foundations: int = 0
	var structural: int = 0
	for placement: Dictionary in data.placements:
		var piece: String = placement["piece"]
		counts[piece] = int(counts.get(piece, 0)) + 1
		var mesh: Mesh = RuinKit.mesh(piece)
		for surface: int in mesh.get_surface_count():
			triangles += (mesh.surface_get_array_index_len(surface) if mesh.surface_get_array_index_len(surface) > 0 else mesh.surface_get_array_len(surface)) / 3
		var transform_value: Transform3D = placement["transform"]
		batches[piece + str(Vector3i((transform_value.origin / RuinBuilder.CELL).floor()))] = true
		if placement.get("foundation", false):
			foundations += 1
			var direction: Vector3 = transform_value.origin.normalized()
			var error: float = absf(transform_value.origin.length() - noise.radius - noise.height(direction) + float(placement.get("sink", 0)))
			foundation_error = maxf(foundation_error, error)
			if noise.water_surface(direction) > -INF and not piece.begins_with("bridge"):
				wet_foundations += 1
				wet_records.append({"piece": piece, "position": str(transform_value.origin), "water_level": noise.water_surface(direction), "group": placement.get("group", "town")})
		else:
			structural += 1
	_require(foundation_error <= 0.5, "有基础构件悬空或过度下沉。")
	_require(wet_foundations == 0, "有非桥梁基础压在河湖上。")
	var road_gap: float = 0.0
	var road_error: float = 0.0
	var road_lengths: Dictionary = {}
	var maximum_slope: float = 0.0
	for road: Dictionary in data.roads:
		var points: PackedVector3Array = road["points"]
		var total: float = 0.0
		for index: int in points.size():
			road_error = maxf(road_error, absf(noise.height(points[index]) - float(road["levels"][index])))
			if index > 0:
				var gap: float = points[index - 1].distance_to(points[index]) * noise.radius
				road_gap = maxf(road_gap, gap)
				total += gap
				maximum_slope = maxf(maximum_slope, absf(noise.height(points[index]) - noise.height(points[index - 1])) / maxf(gap, 0.01))
		road_lengths[road["name"]] = total
	_require(road_gap <= 15.0, "道路相邻点间距超过十五米。")
	_require(road_error <= 0.1, "道路烘焙高度与唯一高度函数不一致。")
	_require(maximum_slope <= 1.0, "道路存在超过玩家站立坡度上限的路段。")
	_require(data.terraces.size() >= 2 and data.terraces.size() <= 4, "梯田数量不在二至四片之间。")
	var field_scene: Node3D = (load("res://models/vegetation/field_stalks.glb") as PackedScene).instantiate() as Node3D
	var field_mesh: Mesh = (field_scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var field_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/vegetation/field_stalks.json")) as Dictionary
	_require(field_mesh.get_faces().size() / 3 == int(field_record["triangles"]) and absf(field_mesh.get_aabb().size.y - 0.6) < 0.05, "稻秆导出模型的面数或高度不一致。")
	field_scene.free()
	var ladder_eye: Vector3 = spawn * (noise.radius + noise.height(spawn) + 1.7)
	var ladder_top: Vector3 = Vector3(data.ladder["direction"]) * (noise.radius + float(data.ladder["height"]) + 6200)
	_require(CivilizationSiting.visible(noise, ladder_eye, ladder_top), "天梯上部被地面遮挡。")
	var jump: Dictionary = await _bridge_jump(data, noise.radius)
	_require(jump["passed"], "角色未能实际跳过主桥断口。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "town_distance_m": distance, "river_distance_m": river.x, "river_width_m": river.z, "slope_limit": data.town["slope_limit"], "plaza_error_m": plaza_error, "foundation_error_m": foundation_error, "foundation_count": foundations, "supported_upper_pieces": structural, "wet_foundations": wet_foundations, "road_point_gap_m": road_gap, "road_height_error_m": road_error, "road_lengths_m": road_lengths, "maximum_road_grade": maximum_slope, "terrace_count": data.terraces.size(), "piece_counts": counts, "triangles": triangles, "estimated_batches": batches.size(), "bridge_jump": jump}
	report["wet_records"] = wet_records
	report["minimum_catchment_km2"] = data.town["minimum_area_km2"]
	report["field_stalks"] = field_record
	if not data.beacons.is_empty():
		var beacons: Dictionary = await BeaconChecks.run(self, noise)
		report["beacons"] = beacons
		if not beacons["passed"]:
			_failures.append_array(beacons["failures"])
		report["passed"] = _failures.is_empty()
	if "--skip-ladder" not in OS.get_cmdline_user_args():
		var ladder: Dictionary = await LadderChecks.run(self)
		report["ladder"] = ladder
		if not ladder["passed"]:
			_failures.append_array(ladder["failures"])
	report["passed"] = _failures.is_empty()
	VerificationMetrics.write_json("res://../test-output/wanderer/civilization_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)


func _bridge_jump(data: CivilizationData, radius: float) -> Dictionary:
	# 碰撞取实际残破桥段，角色尺寸、速度和重力与玩家一致。
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	var bridge: StaticBody3D = StaticBody3D.new()
	var up: Vector3 = data.bridge["direction"]
	var x: Vector3 = data.bridge["across"]
	var anchor: Transform3D = Transform3D(Basis(x, up, x.cross(up).normalized()), up * (radius + float(data.bridge["level"]) - 6.0))
	for placement: Dictionary in data.placements:
		if not placement.has("bridge_direction") or not Vector3(placement["bridge_direction"]).is_equal_approx(up):
			continue
		for record: Dictionary in RuinKit.collision_records(placement["piece"]):
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = record["shape"]
			collision.transform = anchor.affine_inverse() * Transform3D(placement["transform"]) * Transform3D(record["transform"])
			bridge.add_child(collision)
	scene.add_child(bridge)
	var actor: CharacterBody3D = CharacterBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.3
	shape.shape = capsule
	shape.position.y = 0.875
	actor.add_child(shape)
	actor.position = Vector3(-3.4, 6.05, 0)
	actor.floor_snap_length = 0.3
	scene.add_child(actor)
	var jumped: bool = false
	var landed: bool = false
	var maximum_height: float = 0.0
	for frame: int in 300:
		await physics_frame
		var delta: float = actor.get_physics_process_delta_time()
		actor.velocity.x = 4.0
		if actor.is_on_floor() and actor.position.x > -2.4 and not jumped:
			actor.velocity.y = 5.0
			jumped = true
		elif not actor.is_on_floor():
			actor.velocity.y -= 9.8 * delta
		actor.move_and_slide()
		maximum_height = maxf(maximum_height, actor.position.y - 6.0)
		if jumped and actor.is_on_floor() and actor.position.x > 0.8:
			landed = true
			break
		if actor.position.y < 3.0:
			break
	var result: Dictionary = {"passed": jumped and landed, "jumped": jumped, "landed": landed, "landing_x_m": actor.position.x, "maximum_height_m": maximum_height, "design_gap_m": data.bridge["gap"], "gravity_m_s2": 9.8}
	scene.queue_free()
	for frame: int in 3:
		await process_frame
	return result


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
