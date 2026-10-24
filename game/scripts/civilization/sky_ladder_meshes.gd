class_name SkyLadderMeshes
extends RefCounted


static func radius_at(height: float) -> float:
	return lerpf(60, 38, clampf(height / 1000, 0, 1))


static func body(near: bool, balcony_height: float = 240.0) -> ArrayMesh:
	var builder: SurfaceTool = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels: Array[float] = []
	levels.assign([0, 35, 300] if near else [0, 300, 1000, 6198])
	for height: float in [balcony_height - 10, balcony_height + 35]:
		if height > 35 and (not near or height < 300) and not levels.has(height):
			levels.append(height)
	levels.sort()
	var sides: int = 64 if near else 16
	for level: int in levels.size() - 1:
		for side: int in sides:
			var a: float = TAU * side / sides
			var b: float = TAU * (side + 1) / sides
			# 两层门洞在朝出发地的同一侧，门内保留升降井净空。
			if ((near and levels[level] < 35) or (levels[level] >= balcony_height - 10 and levels[level + 1] <= balcony_height + 35)) and absf(wrapf((a + b) * 0.5 - PI, -PI, PI)) < 0.36:
				continue
			var points: Array[Vector3] = []
			for pair: Vector2 in [Vector2(a, levels[level]), Vector2(b, levels[level]), Vector2(b, levels[level + 1]), Vector2(a, levels[level + 1])]:
				points.append(Vector3(sin(pair.x), 0, cos(pair.x)) * radius_at(pair.y) + Vector3.UP * pair.y)
			for index: int in [0, 2, 1, 0, 3, 2]:
				var vertex: Vector3 = points[index]
				builder.set_normal(Vector3(vertex.x, 0, vertex.z).normalized())
				builder.set_uv(Vector2(atan2(vertex.x, vertex.z) / TAU, vertex.y))
				builder.add_vertex(vertex)
	return builder.commit()
