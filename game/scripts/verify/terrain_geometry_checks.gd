class_name TerrainGeometryChecks
extends RefCounted


static func run() -> Dictionary:
	var failures: Array[String] = []
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0)
	var grid: int = PlanetTerrain.GRID
	var vertices_checked: int = 0
	for face: int in PlanetTerrain.FACES.size():
		var axes: Array = PlanetTerrain.FACES[face]
		var normal: Vector3 = axes[0]
		var axis_a: Vector3 = axes[1]
		var axis_b: Vector3 = axes[2]
		if not axis_a.cross(axis_b).is_equal_approx(normal):
			failures.append("立方体面 %d 的坐标轴方向错误。" % face)
		var result: Dictionary = TerrainChunkBuilder.build(noise, normal, axis_a, axis_b, -1.0, -1.0, 2.0, grid, 60.0)
		var arrays: Array = result["terrain"]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base_count: int = (grid + 1) * (grid + 1)
		if vertices.size() != base_count + 4 * (grid + 1):
			failures.append("面 %d 缺少裙边顶点。" % face)
		if indices.size() != grid * grid * 6 + 4 * grid * 12:
			failures.append("面 %d 的双面裙边索引数错误。" % face)
		var water: Array = result["water"]
		if not water.is_empty():
			var water_indices: PackedInt32Array = water[Mesh.ARRAY_INDEX]
			if water_indices.size() != grid * grid * 6:
				failures.append("面 %d 的海面包含计划外的竖直裙边。" % face)
		for index: int in base_count:
			var row: int = floori(float(index) / float(grid + 1))
			var column: int = index % (grid + 1)
			var direction: Vector3 = PlanetTerrain.cube_to_sphere(normal + axis_a * (-1.0 + 2.0 * float(column) / float(grid)) + axis_b * (-1.0 + 2.0 * float(row) / float(grid)))
			if absf(direction.length() - 1.0) > 0.00001:
				failures.append("面 %d 的球面映射未归一化。" % face)
			var expected: Vector3 = direction * (noise.radius + noise.height(direction))
			if (vertices[index] + (result["center"] as Vector3)).distance_to(expected) > 0.02:
				failures.append("面 %d 的顶点与统一高度函数不一致。" % face)
			if normals[index].dot(direction) <= 0.0:
				failures.append("面 %d 的地形法线朝内。" % face)
			vertices_checked += 1
		for index: int in range(0, grid * grid * 6, 3):
			var a: Vector3 = vertices[indices[index]]
			var b: Vector3 = vertices[indices[index + 1]]
			var c: Vector3 = vertices[indices[index + 2]]
			if (b - a).cross(c - a).dot(a + (result["center"] as Vector3)) >= 0.0:
				failures.append("面 %d 的三角形未按 Godot 正面绕序排列。" % face)
		var collision: Dictionary = TerrainChunkBuilder.build(noise, normal, axis_a, axis_b, -1.0, -1.0, 2.0, grid, 60.0, true)
		var faces: PackedVector3Array = collision["faces"]
		if faces.size() != grid * grid * 6:
			failures.append("面 %d 的碰撞面数量错误。" % face)
		else:
			for index: int in faces.size():
				if not faces[index].is_equal_approx(vertices[indices[index]]):
					failures.append("面 %d 的碰撞面与可见网格不一致。" % face)
	return {"passed": failures.is_empty(), "faces_checked": 6, "vertices_checked": vertices_checked, "failures": failures}
