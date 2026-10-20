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
		if piece != "echo_figure":
			_check_vertex_colors(model, piece, failures)
		var limit: int = 5000 if piece.begins_with("statue") else (300 if piece.begins_with("rubble") or piece.begins_with("stele") or piece.begins_with("lamp_post") else (4000 if piece.begins_with("bridge") or piece.begins_with("dome") or piece.begins_with("brazier") else 1200))
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
		if piece == "echo_figure" and (imported.find_child("Head", true, false) == null or imported.find_child("ArmLeft", true, false) == null or imported.find_child("ArmRight", true, false) == null):
			failures.append("回声人影缺少可独立驱动的身体节点。")
		imported.free()
		var needs_collision: bool = not piece.begins_with("vines") and piece != "sand_drift" and piece != "echo_figure"
		if needs_collision and shapes.is_empty():
			failures.append(piece + " 缺少碰撞。")
		for shape: Shape3D in shapes:
			if shape is ConcavePolygonShape3D and (shape as ConcavePolygonShape3D).get_faces().size() / 3 > 64:
				failures.append(piece + " 的简化碰撞超过 64 个三角形。")
		records.append({"piece": piece, "triangles": count, "size": str(bounds.size), "collisions": shapes.size()})
	var physics_failures: Array[String] = await _physical_checks()
	failures.append_array(physics_failures)
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "pieces": records.size(), "records": records, "door_clearance_checked": true}
	VerificationMetrics.write_json("res://../test-output/wanderer/ruin_kit_checks.json", report)
	print(JSON.stringify({"passed": report["passed"], "pieces": records.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_vertex_colors(mesh: Mesh, piece: String, failures: Array[String]) -> void:
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if colors.size() != vertices.size():
			failures.append(piece + " 缺少完整顶点颜色。")
			continue
		for index: int in vertices.size():
			var color: Color = colors[index]
			var ao: float = lerpf(0.65, 1.0, clampf(vertices[index].y / 3.0, 0.0, 1.0))
			if absf(color.r - ao) > 0.02 or color.a < 0.99 or absf(color.b - (1.0 if piece.begins_with("vines") else 0.0)) > 0.01:
				failures.append(piece + " 的顶点颜色通道错位。")
				return


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
