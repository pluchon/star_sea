class_name RuinMeshes
extends RefCounted

const KINDS: Array[String] = ["stone", "patina", "glyph", "cloth"]
static var _recipes: Dictionary = {}


static func recipes() -> Dictionary:
	if _recipes.is_empty():
		_recipes = JSON.parse_string(FileAccess.get_file_as_string("res://models/ruins/geometry.json")) as Dictionary
	return _recipes


static func mesh(piece: String) -> ArrayMesh:
	if not recipes().has(piece):
		return null
	var record: Dictionary = recipes()[piece]
	var result: ArrayMesh = ArrayMesh.new()
	for kind: String in KINDS:
		var points: Array = record["surfaces"][kind]
		if points.is_empty():
			continue
		var builder: SurfaceTool = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for start: int in range(0, points.size(), 3):
			var a: Vector3 = vector(points[start])
			var b: Vector3 = vector(points[start + 1])
			var c: Vector3 = vector(points[start + 2])
			var normal: Vector3 = (b - a).cross(c - a).normalized()
			for corner: int in [2, 1, 0]:
				var vertex: Vector3 = vector(points[start + corner])
				builder.set_normal(normal)
				var ao: float = lerpf(0.65, 1.0, clampf(vertex.y / 3.0, 0.0, 1.0))
				builder.set_color(Color(ao, clampf(vertex.y / 2.0, 0.0, 1.0), 1.0 if piece.begins_with("vines") else 0.0))
				var absolute: Vector3 = normal.abs()
				builder.set_uv(Vector2(vertex.z, vertex.y) if absolute.x > absolute.y and absolute.x > absolute.z else (Vector2(vertex.x, vertex.z) if absolute.y > absolute.z else Vector2(vertex.x, vertex.y)))
				builder.add_vertex(vertex)
		builder.set_material(RuinKit.material(KINDS.find(kind)))
		builder.commit(result)
	return result


static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func collision_records(piece: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in recipes()[piece]["collisions"]:
		var kind: String = record["kind"]
		if kind == "box":
			var shape: BoxShape3D = BoxShape3D.new()
			var size: Vector3 = vector(record["size"])
			shape.size = Vector3(size.x, size.z, size.y)
			var location: Vector3 = vector(record["position"])
			result.append({"shape": shape, "transform": Transform3D(Basis(Vector3.UP, record["rotation"]), Vector3(location.x, location.z, -location.y))})
		elif kind == "cylinder":
			# 十二边凸包与可见圆柱一致，不用高面数的三角网格碰撞。
			var points: PackedVector3Array = []
			for index: int in 12:
				for sign_value: float in [-0.5, 0.5]:
					points.append(Vector3(cos(index * TAU / 12.0) * float(record["radius"]), float(record["height"]) * sign_value, sin(index * TAU / 12.0) * float(record["radius"])))
			var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			shape.points = points
			var location: Vector3 = vector(record["position"])
			result.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(location.x, location.z, -location.y))})
		elif kind == "ramp":
			var size: Vector3 = vector(record["size"])
			var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array([Vector3(-size.x / 2, 0, size.y / 2), Vector3(size.x / 2, 0, size.y / 2), Vector3(-size.x / 2, 0, -size.y / 2), Vector3(size.x / 2, 0, -size.y / 2), Vector3(-size.x / 2, size.z, -size.y / 2), Vector3(size.x / 2, size.z, -size.y / 2)])
			result.append({"shape": shape, "transform": Transform3D.IDENTITY})
		elif kind == "arch":
			var width: float = record["width"]
			var height: float = record["height"]
			var depth: float = record["depth"]
			var thickness: float = record["thickness"]
			var rise: float = minf(width * 0.5, height * 0.55)
			for side: float in [-1.0, 1.0]:
				var shape: BoxShape3D = BoxShape3D.new()
				shape.size = Vector3(thickness, height - rise, depth)
				result.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(side * (width - thickness) * 0.5, (height - rise) * 0.5, 0))})
			for index: int in 8:
				if record["broken"] and index in [3, 4]:
					continue
				var angle: float = PI * (index + 0.5) / 8.0
				var shape: BoxShape3D = BoxShape3D.new()
				shape.size = Vector3(PI * width / 16.0, thickness, depth)
				var location: Vector3 = Vector3((width - thickness) * 0.5 * cos(angle), height - rise + (rise - thickness * 0.5) * sin(angle), 0)
				result.append({"shape": shape, "transform": Transform3D(Basis(Vector3.BACK, angle - PI * 0.5), location)})
		elif kind == "dome":
			var faces: PackedVector3Array = []
			for index: int in (12 if record["broken"] else 16):
				for row: int in 2:
					var quad: PackedVector3Array = []
					for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
						var angle: float = (index + uv.x) * TAU / 16.0
						var phi: float = (row + uv.y) * PI / 4.0
						quad.append(Vector3(cos(angle) * cos(phi) * float(record["radius"]), sin(phi) * float(record["height"]), sin(angle) * cos(phi) * float(record["radius"])))
					for corner: int in [0, 2, 1, 1, 2, 3]:
						faces.append(quad[corner])
			var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			result.append({"shape": shape, "transform": Transform3D.IDENTITY})
		elif kind == "stair_arc":
			for index: int in 6:
				if record["broken"] and index == 2:
					continue
				var points: PackedVector3Array = []
				for step: int in 2:
					var angle: float = (index + step) * PI / 12.0
					for radius: float in [3.2, 4.6]:
						for offset: float in [-0.25, 0.0]:
							points.append(Vector3(cos(angle) * radius, (index + step) * 0.5 + offset, -sin(angle) * radius))
				var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
				shape.points = points
				result.append({"shape": shape, "transform": Transform3D.IDENTITY})
		elif kind == "ring":
			for index: int in 24:
				var angle: float = (index + 0.5) * float(record["end"]) / 24.0
				var shape: BoxShape3D = BoxShape3D.new()
				shape.size = Vector3(float(record["radius"]) * float(record["end"]) / 24.0, float(record["tube"]) * 2.0, float(record["tube"]) * 2.0)
				var location: Vector3 = Vector3(float(record["radius"]) * cos(angle), float(record["height"]) + float(record["radius"]) * sin(angle), 0)
				result.append({"shape": shape, "transform": Transform3D(Basis(Vector3.BACK, angle - PI * 0.5), location)})
	return result
