class_name StoneworkMeshes
extends VegetationMeshes


static func block(size: Vector3, seed_value: int, arch: Vector2 = Vector2.ZERO) -> ArrayMesh:
	var builder: StoneworkMeshes = StoneworkMeshes.new()
	builder._tag = 2.0
	var half: Vector3 = size * 0.5
	var bevel: float = minf(size.x, minf(size.y, size.z)) * 0.085
	var faces: Array[Array] = []
	# 六个主面、十二条倒角和八个切角共同组成闭合石块。
	for axis: int in 3:
		var u: int = (axis + 1) % 3
		var v: int = (axis + 2) % 3
		for sign_value: float in [-1.0, 1.0]:
			var face: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point: Vector3 = Vector3.ZERO
				point[axis] = half[axis] * sign_value
				point[u] = (half[u] - bevel) * corner.x
				point[v] = (half[v] - bevel) * corner.y
				face.append(point)
			faces.append(face)
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				var face: Array[Vector3] = []
				for corner: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var point: Vector3 = Vector3.ZERO
					point[axis] = (half[axis] - bevel) * corner.x
					point[u] = (half[u] - bevel * corner.y) * su
					point[v] = (half[v] - bevel * (1.0 - corner.y)) * sv
					face.append(point)
				faces.append(face)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner: Vector3 = half * Vector3(sx, sy, sz)
				faces.append([corner - Vector3(0, sy, sz) * bevel, corner - Vector3(sx, 0, sz) * bevel, corner - Vector3(sx, sy, 0) * bevel])
	var center: Vector3 = Vector3.ZERO if arch == Vector2.ZERO else Vector3(sin(arch.x) * arch.y, cos(arch.x) * arch.y, 0)
	for face: Array in faces:
		var points: Array[Vector3] = []
		for raw: Vector3 in face:
			# 同一顶点的扰动只依赖位置，保证倒角和主面没有裂缝。
			var wear: float = sin(raw.dot(Vector3(7.1, 11.3, 5.7)) + seed_value * 1.9) * bevel * 0.18
			var point: Vector3 = raw + raw.normalized() * wear
			if arch != Vector2.ZERO:
				var angle: float = arch.x + point.x / arch.y
				point = Vector3(sin(angle) * (arch.y + point.y), cos(angle) * (arch.y + point.y), point.z)
			points.append(point)
		for index: int in range(1, points.size() - 1):
			var a: Vector3 = points[0]
			var b: Vector3 = points[index]
			var c: Vector3 = points[index + 1]
			var outward: Vector3 = (a + b + c) / 3.0 - center
			if (c - a).cross(b - a).dot(outward) < 0.0:
				var swap: Vector3 = b
				b = c
				c = swap
			builder._rock_face(a, b, c, Color(0.65, 0.65, 0.59) * (0.96 + sin(seed_value * 2.1) * 0.04))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = builder._vertices
	arrays[Mesh.ARRAY_NORMAL] = builder._normals
	arrays[Mesh.ARRAY_COLOR] = builder._colors
	arrays[Mesh.ARRAY_TEX_UV] = builder._uvs
	arrays[Mesh.ARRAY_TEX_UV2] = builder._uv2s
	arrays[Mesh.ARRAY_TANGENT] = builder._tangents()
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
