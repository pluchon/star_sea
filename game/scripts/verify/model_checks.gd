class_name ModelChecks
extends RefCounted


static func assets() -> Dictionary:
	return AssetModelChecks.run()


static func run() -> Dictionary:
	var failures: Array[String] = []
	var counts: Dictionary = {}
	for kind: String in SurfaceDetails.KINDS:
		if kind == "field_stalks":
			var field: ArrayMesh = SurfaceDetails.mesh_for_kind(kind)
			counts[kind] = [field.get_faces().size() / 3]
			for surface: int in field.get_surface_count():
				var arrays: Array = field.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var wind: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				if wind.size() != vertices.size():
					failures.append("稻秆缺少随高度变化的风权重。")
					continue
				for index: int in vertices.size():
					if absf(wind[index].y) > 0.001 or absf(wind[index].x - vertices[index].y / 0.6) > 0.02:
						failures.append("稻秆第二组 UV 的风权重或材质分类不正确。")
						break
			continue
		var mesh: ArrayMesh = VegetationMeshes.create(kind)
		var high: int = mesh.get_meta("triangles")
		var levels: Array = [high]
		levels.append_array(mesh.get_meta("lod_triangles"))
		counts[kind] = levels
		var total: int = 0
		var previous: int = 100000
		for count: int in levels:
			if count <= 0 or count >= previous:
				failures.append(kind + "的细节层级没有递减。")
			if kind == "stone":
				_check_closed(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], total * 3, count * 3, failures, kind)
			total += count
			previous = count
		_check_attributes(mesh, failures, kind)
		if (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != total * 3:
			failures.append(kind + "的层级索引范围异常。")
	for arch: Vector2 in [Vector2.ZERO, Vector2(-1.2, 2.025), Vector2(0, 2.025), Vector2(1.2, 2.025)]:
		var mesh: ArrayMesh = StoneworkMeshes.block(Vector3(0.70, 0.75, 1.10), 9, arch)
		_check_attributes(mesh, failures, "遗迹石块")
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check_closed(vertices, 0, vertices.size(), failures, "遗迹石块")
		if vertices.size() != 132 or mesh.create_convex_shape() == null:
			failures.append("遗迹倒角石块的面数或碰撞形状异常。")
	return {"passed": failures.is_empty(), "failures": failures, "triangles_high_medium_far": counts, "stonework_triangles_per_block": 44, "stonework_variants_checked": 4}


static func _check_attributes(mesh: ArrayMesh, failures: Array[String], label: String) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if normals.size() != vertices.size() or uvs.size() != vertices.size() or tangents.size() != vertices.size() * 4:
		failures.append(label + "的顶点属性数量不一致。")
		return
	for index: int in vertices.size():
		var tangent: Vector3 = Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
		if not vertices[index].is_finite() or not uvs[index].is_finite() or not tangent.is_finite() or absf(normals[index].length() - 1.0) > 0.02 or absf(normals[index].dot(tangent)) > 0.02:
			failures.append(label + "包含无效坐标、法线或切线。")
			return


static func _check_closed(vertices: PackedVector3Array, start: int, count: int, failures: Array[String], label: String) -> void:
	var edges: Dictionary = {}
	for index: int in range(start, start + count, 3):
		for corner: int in 3:
			var a: Vector3 = vertices[index + corner].snapped(Vector3.ONE * 0.0001)
			var b: Vector3 = vertices[index + (corner + 1) % 3].snapped(Vector3.ONE * 0.0001)
			var key: String = str(a) + "/" + str(b) if a < b else str(b) + "/" + str(a)
			edges[key] = int(edges.get(key, 0)) + 1
	for occurrences: int in edges.values():
		if occurrences != 2:
			failures.append(label + "包含未闭合边或重复面。")
			return
