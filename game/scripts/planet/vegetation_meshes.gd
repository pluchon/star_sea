class_name VegetationMeshes
extends RefCounted

var _vertices: PackedVector3Array = []
var _normals: PackedVector3Array = []
var _colors: PackedColorArray = []
var _uvs: PackedVector2Array = []


static func create(kind: String) -> ArrayMesh:
	var builder: VegetationMeshes = VegetationMeshes.new()
	match kind:
		"grass":
			builder._grass()
		"broadleaf":
			builder._tube(Vector3(0, -0.25, 0), Vector3(0.2, 7.7, 0.1), 0.42, 0.16, Color(0.30, 0.23, 0.15))
			for index: int in 5:
				var angle: float = index * TAU / 5.0
				var end: Vector3 = Vector3(cos(angle) * 2.3, 6.7 + float(index % 2), sin(angle) * 2.3)
				builder._tube(Vector3(0, 4.2, 0), end, 0.18, 0.06, Color(0.34, 0.26, 0.16))
				builder._crown(end + Vector3.UP * 1.1, Vector3(2.7, 2.4, 2.8), Color(0.40, 0.58, 0.22), 1.0, index)
			builder._crown(Vector3(0.1, 9.3, 0), Vector3(2.8, 2.5, 2.7), Color(0.52, 0.67, 0.27), 1.0, 6)
		"pine":
			builder._tube(Vector3(0, -0.25, 0), Vector3(0, 12.5, 0), 0.32, 0.03, Color(0.27, 0.22, 0.16))
			for index: int in 5:
				var base: float = 2.5 + index * 1.8
				builder._cone(base, 4.2 - index * 0.35, 3.2 - index * 0.48, Color(0.19 + index * 0.025, 0.39 + index * 0.025, 0.27))
		"shrub":
			for index: int in 3:
				var angle: float = index * TAU / 3.0
				builder._crown(Vector3(cos(angle) * 0.45, 0.65, sin(angle) * 0.45), Vector3(0.85, 0.85, 0.8), Color(0.36, 0.48, 0.19), 0.7, index)
		"flowers":
			for index: int in 3:
				var stem: Vector3 = Vector3(sin(index * 4.0) * 0.3, 0.35 + index * 0.09, cos(index * 4.0) * 0.3)
				builder._tube(Vector3(stem.x, 0, stem.z), stem, 0.018, 0.01, Color(0.26, 0.39, 0.12))
				for petal: int in 5:
					var angle: float = petal * TAU / 5.0
					var side: Vector3 = Vector3(-sin(angle), 0, cos(angle)) * 0.065
					var tip: Vector3 = stem + Vector3(cos(angle) * 0.16, 0.03, sin(angle) * 0.16)
					builder._triangle(stem - side, tip, stem + side, Vector3.UP, Vector3.UP, Vector3.UP, Color(0.94, 0.77, 0.38), 1.0)
		"stone":
			builder._crown(Vector3(0, 0.30, 0), Vector3(1, 0.7, 0.85), Color(0.62, 0.62, 0.55), 0.0, 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = builder._vertices
	arrays[Mesh.ARRAY_NORMAL] = builder._normals
	arrays[Mesh.ARRAY_COLOR] = builder._colors
	arrays[Mesh.ARRAY_TEX_UV] = builder._uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color, wind: float) -> void:
	_vertices.append_array(PackedVector3Array([a, b, c]))
	_normals.append_array(PackedVector3Array([na, nb, nc]))
	var linear: Color = color.srgb_to_linear()
	_colors.append_array(PackedColorArray([linear, linear, linear]))
	_uvs.append_array(PackedVector2Array([Vector2(0, wind), Vector2(0.5, wind), Vector2(1, wind)]))


func _crown(center: Vector3, scale: Vector3, color: Color, wind: float, seed_value: int) -> void:
	# 不规则树冠保留柔和法线与轮廓起伏，颜色按冠层上下变化。
	var segments: int = 10
	var rings: int = 5
	for row: int in rings:
		for column: int in segments:
			var points: Array[Vector3] = []
			var directions: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
				var latitude: float = PI * float(row + corner.y) / rings
				var angle: float = TAU * float(column + corner.x) / segments
				var normal: Vector3 = Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
				var irregular: float = 1.0 + sin(angle * 3.0 + seed_value * 2.1 + latitude * 2.0) * sin(latitude) * 0.10
				points.append(center + normal * scale * irregular)
				directions.append((normal / scale).normalized())
			_triangle(points[0], points[1], points[2], directions[0], directions[1], directions[2], color, wind)
			_triangle(points[2], points[1], points[3], directions[2], directions[1], directions[3], color, wind)
			for vertex: int in range(_vertices.size() - 6, _vertices.size()):
				_colors[vertex] = (color * lerpf(0.72, 1.05, _normals[vertex].y * 0.5 + 0.5)).srgb_to_linear()


func _tube(start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	var axis: Vector3 = (end - start).normalized()
	var tangent: Vector3 = SurfaceSites.tangent_forward(axis)
	var right: Vector3 = axis.cross(tangent)
	for index: int in 7:
		var a: float = index * TAU / 7.0
		var b: float = (index + 1) * TAU / 7.0
		var na: Vector3 = tangent * cos(a) + right * sin(a)
		var nb: Vector3 = tangent * cos(b) + right * sin(b)
		_triangle(start + na * bottom, end + na * top, start + nb * bottom, na, na, nb, color, 0.0)
		_triangle(start + nb * bottom, end + na * top, end + nb * top, nb, na, nb, color, 0.0)


func _cone(base: float, height: float, radius_value: float, color: Color) -> void:
	for index: int in 9:
		var a: float = index * TAU / 9.0
		var b: float = (index + 1) * TAU / 9.0
		var na: Vector3 = Vector3(cos(a), 0.5, sin(a)).normalized()
		var nb: Vector3 = Vector3(cos(b), 0.5, sin(b)).normalized()
		var p: Vector3 = Vector3(cos(a) * radius_value, base, sin(a) * radius_value)
		var q: Vector3 = Vector3(cos(b) * radius_value, base, sin(b) * radius_value)
		_triangle(p, q, Vector3(0, base + height, 0), na, nb, Vector3.UP, color, 1.0)
		_triangle(q, p, Vector3(0, base, 0), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color * 0.65, 1.0)


func _grass() -> void:
	for index: int in 7:
		var angle: float = index * 2.39996
		var right: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var base: Vector3 = right * (0.04 + float(index % 3) * 0.09)
		var height: float = 0.38 + float(index % 4) * 0.09
		var midpoint: Vector3 = base + Vector3.UP * height * 0.55 + right * 0.05
		var tip: Vector3 = base + Vector3.UP * height + right * 0.20
		var normal: Vector3 = (Vector3.UP * 0.7 + right * 0.3).normalized()
		_triangle(base - right * 0.035, midpoint - right * 0.022, base + right * 0.035, normal, normal, normal, Color(0.52, 0.66, 0.28), 0.0)
		_triangle(base + right * 0.035, midpoint - right * 0.022, midpoint + right * 0.022, normal, normal, normal, Color(0.64, 0.76, 0.36), 0.5)
		_triangle(midpoint - right * 0.022, tip, midpoint + right * 0.022, normal, normal, normal, Color(0.73, 0.81, 0.43), 1.0)
		# 同一叶片的共享顶点使用相同摆动权重，避免风吹时三角形分离。
		for vertex: int in range(_vertices.size() - 9, _vertices.size()):
			_uvs[vertex].y = clampf(_vertices[vertex].y / height, 0.0, 1.0)
