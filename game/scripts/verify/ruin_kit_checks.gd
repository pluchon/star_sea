extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var expected: Dictionary = {"floor_slab": Vector3(2, 0.4, 2), "plinth": Vector3(8, 1.2, 8), "steps": Vector3(4, 1.5, 3.6), "wall": Vector3(2, 3.6, 0.6), "wall_window": Vector3(2, 3.6, 0.6), "door": Vector3(2.4, 4.2, 0.8), "wall_low": Vector3(2, 1, 0.5), "column": Vector3(0.7, 4.2, 0.7), "lintel": Vector3(4, 0.6, 0.6), "arch": Vector3(4, 5, 0.8), "dome": Vector3(6, 1.6, 6), "bridge_span": Vector3(12, 6, 4), "bridge_pier": Vector3(2, 6, 4), "aqueduct_channel": Vector3(8, 1.2, 1.4), "aqueduct_pier": Vector3(1.4, 4, 1.4), "road_stone": Vector3(2, 0.2, 1), "stele": Vector3(1.2, 3, 0.4), "standing_stone": Vector3(0.6, 2.2, 0.4), "lamp_post": Vector3(0.4, 2.6, 0.4), "brazier": Vector3(2.4, 1.4, 2.4), "ring_monument": Vector3(5, 6, 2), "statue": Vector3(1.6, 4.6, 1.2), "cave_mouth": Vector3(10, 8, 4), "temple_gate": Vector3(6, 8, 2), "mural_panel": Vector3(4, 3, 0.3), "tower_drum": Vector3(6.4, 3, 6.4), "tower_crown": Vector3(8, 2, 8)}
	for piece: String in RuinMeshes.recipes():
		var model: Mesh = RuinKit.mesh(piece)
		var procedural: Mesh = RuinKit.mesh(piece, true)
		if model == null or procedural == null:
			failures.append(piece + " 缺少网格。")
			continue
		var count: int = model.get_faces().size() / 3
		_check_vertex_colors(model, procedural, piece, failures)
		var limit: int = _triangle_limit(piece)
		if count > limit:
			failures.append(piece + " 超出三角形预算：%d > %d" % [count, limit])
		var bounds: AABB = model.get_aabb()
		var reference: AABB = procedural.get_aabb()
		if bounds.position.distance_to(reference.position) > 0.005 or bounds.size.distance_to(reference.size) > 0.005:
			failures.append(piece + " 两条制作路线的尺寸不一致。")
		if expected.has(piece):
			var size: Vector3 = expected[piece]
			var error: Vector3 = (bounds.size - size).abs() / size
			if error.x > 0.05 or error.y > 0.05 or error.z > 0.05:
				failures.append(piece + " 尺寸不符合规格：" + str(bounds.size))
		if absf(bounds.position.y) > 0.12:
			failures.append(piece + " 原点不在底面。")
		var shapes: Array[Shape3D] = RuinKit.collision(piece)
		var imported: Node = (load("res://models/ruins/" + piece + ".glb") as PackedScene).instantiate()
		var native_collisions: int = imported.find_children("*", "CollisionShape3D", true, false).size()
		if native_collisions != shapes.size():
			failures.append(piece + " glb 碰撞与程序化路线数量不一致。")
		if piece.begins_with("echo_"):
			_check_joints(imported, piece, bounds.size.y, failures)
		if piece.ends_with("_broken"):
			var whole: String = "statue" if piece == "statue_arm_broken" else piece.trim_suffix("_broken")
			var intact: Mesh = RuinKit.mesh(whole)
			var intact_bounds: AABB = intact.get_aabb()
			if bounds.size.y > intact_bounds.size.y + 0.005 or bounds.size.x > intact_bounds.size.x * 1.5 or bounds.size.z > intact_bounds.size.z * 1.5:
				failures.append(piece + " 的残破包围盒超出完好版范围。")
			if count <= intact.get_faces().size() / 3:
				failures.append(piece + " 的断面缺少几何细分。")
		imported.free()
		var needs_collision: bool = not piece.begins_with("vines") and piece != "vine_wall" and piece != "sand_drift" and not piece.begins_with("echo_")
		if needs_collision and shapes.is_empty():
			failures.append(piece + " 缺少碰撞。")
		for shape: Shape3D in shapes:
			if shape is ConcavePolygonShape3D and (shape as ConcavePolygonShape3D).get_faces().size() / 3 > 64:
				failures.append(piece + " 的简化碰撞超过 64 个三角形。")
			if shape is ConvexPolygonShape3D and (shape as ConvexPolygonShape3D).points.size() > 34:
				failures.append(piece + " 的凸包碰撞超过 64 个面的顶点预算。")
		if piece in ["echo_figure", "echo_child", "vine_wall", "vines", "vines_1"]:
			var target_height: float = {"echo_figure": 2.1, "echo_child": 1.3, "vine_wall": 6.0, "vines": 1.8, "vines_1": 2.6}[piece]
			if absf(bounds.size.y - target_height) > target_height * 0.05:
				failures.append(piece + " 高度不符合修订规格。")
			if piece in ["vine_wall", "vines", "vines_1"]:
				var target_width: float = {"vine_wall": 3.0, "vines": 2.0, "vines_1": 1.2}[piece]
				if absf(bounds.size.x - target_width) > target_width * 0.05 or bounds.position.z < -0.15 or bounds.end.z > -0.009:
					failures.append(piece + " 宽度或贴墙距离不符合规格。")
		records.append({"piece": piece, "triangles": count, "size": str(bounds.size), "collisions": shapes.size()})
	var physics_failures: Array[String] = await _physical_checks()
	failures.append_array(physics_failures)
	_check_wall_recess(failures)
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "pieces": records.size(), "records": records, "door_clearance_checked": true}
	VerificationMetrics.write_json("res://../test-output/wanderer/ruin_kit_checks.json", report)
	print(JSON.stringify({"passed": report["passed"], "pieces": records.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_vertex_colors(mesh: Mesh, reference: Mesh, piece: String, failures: Array[String]) -> void:
	var expected_colors: Dictionary = {}
	for surface: int in reference.get_surface_count():
		var arrays: Array = reference.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for index: int in vertices.size():
			var key: Vector3i = Vector3i((vertices[index] * 1000.0).round())
			if not expected_colors.has(key):
				expected_colors[key] = []
			(expected_colors[key] as Array).append(colors[index])
	var cavity_vertices: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if colors.size() != vertices.size():
			failures.append(piece + " 缺少完整顶点颜色。")
			continue
		for index: int in vertices.size():
			var color: Color = colors[index]
			if color.r < 0.14 or color.r > 1.01 or color.a < 0.99 or absf(color.b - (1.0 if piece.begins_with("vines") or piece == "vine_wall" else 0.0)) > 0.01:
				failures.append(piece + " 的顶点颜色通道错位。")
				return
			var key: Vector3i = Vector3i((vertices[index] * 1000.0).round())
			var found: bool = false
			var candidates: Array = expected_colors.get(key, []).duplicate()
			for x: int in range(-1, 2):
				for y: int in range(-1, 2):
					for z: int in range(-1, 2):
						candidates.append_array(expected_colors.get(key + Vector3i(x, y, z), []))
			for candidate: Color in candidates:
				if absf(color.r - candidate.r) < 0.02 and absf(color.g - candidate.g) < 0.02 and absf(color.b - candidate.b) < 0.02:
					found = true
					break
			if not found:
				failures.append(piece + " 的模型颜色与备用网格不一致。")
				return
			if color.r < 0.2:
				cavity_vertices += 1
	if piece in ["statue", "statue_kneel", "statue_arm_broken", "echo_figure", "echo_child"] and cavity_vertices < 24:
		failures.append(piece + " 缺少兜帽深腔的环境遮蔽。")


func _triangle_limit(piece: String) -> int:
	if piece.begins_with("statue"):
		return 5000
	if piece.begins_with("echo_"):
		return 3000
	if piece.begins_with("rubble"):
		return 600
	if piece.begins_with("stele") or piece.begins_with("lamp_post"):
		return 300
	if piece.begins_with("bridge") or piece.begins_with("dome") or piece.begins_with("brazier"):
		return 4000
	return 1200 if piece.begins_with("vines") else 1800


func _check_wall_recess(failures: Array[String]) -> void:
	# 使用可见三角形检查砌缝，不能用整块碰撞代替墙面是否连续的判断。
	var height: float = 0.3 + (3.6 - 0.45) / 4.0
	var eye: Vector3 = Vector3(0, height, -2)
	var closest: Vector3 = Vector3.INF
	var faces: PackedVector3Array = RuinKit.mesh("wall").get_faces()
	for start: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(eye, Vector3.BACK, faces[start], faces[start + 1], faces[start + 2])
		if hit is Vector3 and (hit as Vector3).z < closest.z:
			closest = hit
	var expected_z: float = -(0.3 - 0.1 * height / 3.6 - 0.01)
	if not closest.is_finite() or absf(closest.z - expected_z) > 0.006:
		failures.append("墙面砌缝需要一厘米深的连续内芯，不能贯穿墙体。")


func _check_joints(imported: Node, piece: String, height: float, failures: Array[String]) -> void:
	for joint: String in ["Head", "Robe", "ArmLeft", "ArmRight"]:
		var node: Node3D = imported.find_child(joint, true, false) as Node3D
		if node == null:
			failures.append(piece + " 缺少关节节点：" + joint)
			continue
		var ratio: float = node.position.y / height
		var lower: float = 0.80 if joint == "Head" else (0.4 if joint == "Robe" else 0.70)
		var upper: float = 0.901 if joint == "Head" else (0.6 if joint == "Robe" else 0.95)
		if ratio < lower or ratio > upper:
			failures.append(piece + " 的 " + joint + " 原点不在关节附近：" + str(ratio))


func _physical_checks() -> Array[String]:
	var result: Array[String] = []
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 8
	for record: Dictionary in RuinKit.collision_records("door"):
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = record["shape"]
		collision.transform = record["transform"]
		body.add_child(collision)
	holder.add_child(body)
	await physics_frame
	await physics_frame
	for probe: Array in [[Vector3(0, 1.7, 0), false], [Vector3(0.79, 1.7, 0), false], [Vector3(0.84, 1.7, 0), true], [Vector3(0, 3.12, 0), false], [Vector3(0, 3.3, 0), true]]:
		var point: Vector3 = probe[0]
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.BACK * 2.0, point + Vector3.FORWARD * 2.0, 8)
		var hit: bool = not holder.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if hit != probe[1]:
			result.append("门洞净空与 1.6 × 3.2 米规格不一致：" + str(point))
	holder.queue_free()
	await process_frame
	return result
