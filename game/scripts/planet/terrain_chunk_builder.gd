class_name TerrainChunkBuilder
extends RefCounted


# 后台任务仅返回数组；节点、网格资源和碰撞资源均由主线程创建。
static func build(noise: TerrainNoise, normal: Vector3, axis_a: Vector3, axis_b: Vector3, u0: float, v0: float, size: float, grid: int, skirt: float, with_faces: bool = false) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var count: int = grid + 3
	var positions: PackedVector3Array = PackedVector3Array()
	var heights: PackedFloat32Array = PackedFloat32Array()
	positions.resize(count * count)
	heights.resize(count * count)
	var minimum_height: float = INF
	for row: int in count:
		for column: int in count:
			var u: float = u0 + size * float(column - 1) / float(grid)
			var v: float = v0 + size * float(row - 1) / float(grid)
			var direction: Vector3 = PlanetTerrain.cube_to_sphere(normal + axis_a * u + axis_b * v)
			var height: float = noise.height(direction)
			heights[row * count + column] = height
			positions[row * count + column] = direction * (noise.radius + height)
			minimum_height = minf(minimum_height, height)
	var midpoint: int = grid >> 1
	var center: Vector3 = positions[(midpoint + 1) * count + midpoint + 1]
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var marks: PackedByteArray = PackedByteArray()
	var water_vertices: PackedVector3Array = PackedVector3Array()
	var water_normals: PackedVector3Array = PackedVector3Array()
	var vertex_count: int = (grid + 1) * (grid + 1)
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	marks.resize(vertex_count * 4)
	if minimum_height < 0.0 and not with_faces:
		water_vertices.resize(vertex_count)
		water_normals.resize(vertex_count)
	for row: int in grid + 1:
		for column: int in grid + 1:
			var padded_index: int = (row + 1) * count + column + 1
			var index: int = row * (grid + 1) + column
			var position: Vector3 = positions[padded_index]
			var direction: Vector3 = position.normalized()
			var tangent_a: Vector3 = positions[padded_index + 1] - positions[padded_index - 1]
			var tangent_b: Vector3 = positions[padded_index + count] - positions[padded_index - count]
			var vertex_normal: Vector3 = tangent_a.cross(tangent_b).normalized()
			vertices[index] = position - center
			normals[index] = vertex_normal
			# 利用已有的边界采样估计凹曲率，不增加高度查询，也不改动网格或碰撞。
			var neighbors: float = (heights[padded_index - 1] + heights[padded_index + 1] + heights[padded_index - count] + heights[padded_index + count]) * 0.25
			var spacing: float = maxf((tangent_a.length() + tangent_b.length()) * 0.25, 0.01)
			var cavity: float = smoothstep(0.012, 0.16, (neighbors - heights[padded_index]) / spacing)
			colors[index] = Color(1.0 - cavity * 0.32, 1.0 - vertex_normal.dot(direction), noise.moisture(direction), noise.woodland(direction))
			var special: Color = noise.features.surface_marks(direction, heights[padded_index], sqrt(maxf(0.0, 1.0 / maxf(pow(vertex_normal.dot(direction), 2), 0.001) - 1.0))) if noise.features != null else Color(0, 0, 0, 0)
			for channel: int in 4:
				marks[index * 4 + channel] = int(clampf(special[channel], 0, 1) * 255.0)
			if not water_vertices.is_empty():
				water_vertices[index] = direction * noise.radius - center
				water_normals[index] = direction
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(grid * grid * 6)
	var cursor: int = 0
	var holes: PackedByteArray = PackedByteArray()
	holes.resize(vertex_count)
	if noise.features != null and noise.features.caves != null and size * noise.radius / grid < 3:
		for index: int in vertex_count:
			holes[index] = int(noise.features.in_hole(vertices[index] + center))
	for row: int in grid:
		for column: int in grid:
			var v00: int = row * (grid + 1) + column
			var v10: int = v00 + 1
			var v01: int = v00 + grid + 1
			var v11: int = v01 + 1
			if not (holes[v00] and holes[v01] and holes[v10]):
				indices[cursor] = v00
				indices[cursor + 1] = v01
				indices[cursor + 2] = v10
				cursor += 3
			if not (holes[v10] and holes[v01] and holes[v11]):
				indices[cursor] = v10
				indices[cursor + 1] = v01
				indices[cursor + 2] = v11
				cursor += 3
	indices.resize(cursor)
	if with_faces:
		var faces: PackedVector3Array = PackedVector3Array()
		faces.resize(indices.size())
		for index: int in indices.size():
			faces[index] = vertices[indices[index]]
		return {"center": center, "faces": faces, "build_us": Time.get_ticks_usec() - started}
	var edges: Array[PackedInt32Array] = []
	for edge: int in 4:
		var edge_indices: PackedInt32Array = PackedInt32Array()
		for offset: int in grid + 1:
			match edge:
				0:
					edge_indices.append(offset)
				1:
					edge_indices.append(offset * (grid + 1) + grid)
				2:
					edge_indices.append(grid * (grid + 1) + grid - offset)
				3:
					edge_indices.append((grid - offset) * (grid + 1))
		edges.append(edge_indices)
	var water_indices: PackedInt32Array = indices.duplicate()
	for edge: PackedInt32Array in edges:
		for index: int in edge:
			for channel: int in 4:
				marks.append(marks[index * 4 + channel])
		_append_skirt(vertices, normals, colors, indices, edge, center, skirt)
	var terrain_arrays: Array = []
	terrain_arrays.resize(Mesh.ARRAY_MAX)
	terrain_arrays[Mesh.ARRAY_VERTEX] = vertices
	terrain_arrays[Mesh.ARRAY_NORMAL] = normals
	terrain_arrays[Mesh.ARRAY_COLOR] = colors
	terrain_arrays[Mesh.ARRAY_CUSTOM0] = marks
	terrain_arrays[Mesh.ARRAY_INDEX] = indices
	var water_arrays: Array = []
	if not water_vertices.is_empty():
		water_arrays.resize(Mesh.ARRAY_MAX)
		water_arrays[Mesh.ARRAY_VERTEX] = water_vertices
		water_arrays[Mesh.ARRAY_NORMAL] = water_normals
		water_arrays[Mesh.ARRAY_INDEX] = water_indices
	return {"center": center, "terrain": terrain_arrays, "water": water_arrays, "build_us": Time.get_ticks_usec() - started}


static func _append_skirt(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, edge: PackedInt32Array, center: Vector3, depth: float) -> void:
	var first_lowered: int = vertices.size()
	for index: int in edge:
		var direction: Vector3 = (vertices[index] + center).normalized()
		vertices.append(vertices[index] - direction * depth)
		normals.append(normals[index])
		if not colors.is_empty():
			colors.append(colors[index])
	for offset: int in edge.size() - 1:
		var top_a: int = edge[offset]
		var top_b: int = edge[offset + 1]
		var bottom_a: int = first_lowered + offset
		var bottom_b: int = bottom_a + 1
		indices.append_array(PackedInt32Array([top_a, bottom_a, top_b, top_b, bottom_a, bottom_b, top_b, bottom_a, top_a, bottom_b, bottom_a, top_b]))
