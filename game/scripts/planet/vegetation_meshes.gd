class_name VegetationMeshes
extends RefCounted

var _vertices: PackedVector3Array = []
var _normals: PackedVector3Array = []
var _colors: PackedColorArray = []
var _uvs: PackedVector2Array = []
var _uv2s: PackedVector2Array = []
var _detail: int = 0
var _tag: float = 0.0


static func create(kind: String) -> ArrayMesh:
	var builder: VegetationMeshes = VegetationMeshes.new()
	builder._build(kind, 0)
	var high_count: int = builder._vertices.size()
	var lods: Dictionary = {}
	if kind != "grass" and kind != "flowers":
		for level: int in [1, 2]:
			var simplified: VegetationMeshes = VegetationMeshes.new()
			simplified._build(kind, level)
			var start: int = builder._vertices.size()
			builder._vertices.append_array(simplified._vertices)
			builder._normals.append_array(simplified._normals)
			builder._colors.append_array(simplified._colors)
			builder._uvs.append_array(simplified._uvs)
			builder._uv2s.append_array(simplified._uv2s)
			lods[0.08 if level == 1 else 0.35] = _indices(start, simplified._vertices.size())
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = builder._vertices
	arrays[Mesh.ARRAY_NORMAL] = builder._normals
	arrays[Mesh.ARRAY_COLOR] = builder._colors
	arrays[Mesh.ARRAY_TEX_UV] = builder._uvs
	arrays[Mesh.ARRAY_TEX_UV2] = builder._uv2s
	arrays[Mesh.ARRAY_TANGENT] = builder._tangents()
	arrays[Mesh.ARRAY_INDEX] = _indices(0, high_count)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	mesh.set_meta("triangles", high_count / 3)
	mesh.set_meta("lod_triangles", [lods[0.08].size() / 3, lods[0.35].size() / 3] if not lods.is_empty() else [])
	return mesh


static func _indices(start: int, count: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	result.resize(count)
	for index: int in count:
		result[index] = start + index
	return result


func _build(kind: String, detail: int) -> void:
	_detail = detail
	match kind:
		"grass":
			_grass()
		"broadleaf":
			_broadleaf()
		"pine":
			_pine()
		"shrub":
			for index: int in 3:
				_tag = 3.0
				var angle: float = index * TAU / 3.0
				_crown(Vector3(cos(angle) * 0.45, 0.65, sin(angle) * 0.45), Vector3(0.85, 0.85, 0.8), Color(0.36, 0.48, 0.19), 0.7, index)
				if detail == 0:
					_tube(Vector3.ZERO, Vector3(cos(angle) * 0.8, 0.7, sin(angle) * 0.8), 0.045, 0.015, Color(0.37, 0.29, 0.16))
		"flowers":
			for index: int in 3:
				var stem: Vector3 = Vector3(sin(index * 4.0) * 0.3, 0.35 + index * 0.09, cos(index * 4.0) * 0.3)
				_tube(Vector3(stem.x, 0, stem.z), stem, 0.018, 0.01, Color(0.26, 0.39, 0.12))
				_tag = 0.0
				for petal: int in 5:
					var angle: float = petal * TAU / 5.0
					var side: Vector3 = Vector3(-sin(angle), 0, cos(angle)) * 0.065
					var tip: Vector3 = stem + Vector3(cos(angle) * 0.16, 0.03, sin(angle) * 0.16)
					var middle: Vector3 = (stem + tip) * 0.5 + Vector3.UP * 0.025
					_triangle(stem - side, tip, middle, Vector3.UP, Vector3.UP, Vector3.UP, Color(0.98, 0.84, 0.49), 1.0)
					_triangle(middle, tip, stem + side, Vector3.UP, Vector3.UP, Vector3.UP, Color(0.91, 0.69, 0.28), 1.0)
				_crown(stem + Vector3.UP * 0.025, Vector3.ONE * 0.045, Color(0.59, 0.36, 0.12), 1.0, index, 6, 3)
		"stone":
			_rock()
		"fern":
			_fern()
		"reeds":
			_reeds()
		"mushrooms":
			_mushrooms()


func _mushrooms() -> void:
	# 菌盖与菌柄分别建模，使用柔和的赭红色和奶白色，不采用照片材质。
	for index: int in [3, 2, 1][_detail]:
		var base: Vector3 = Vector3(sin(index * 3.4) * 0.26, 0, cos(index * 3.4) * 0.22)
		var height: float = 0.20 + index * 0.07
		_tube(base, base + Vector3.UP * height, 0.035, 0.025, Color(0.85, 0.77, 0.57))
		_tag = 0.0
		_crown(base + Vector3.UP * height, Vector3(0.15, 0.065, 0.15), Color(0.68, 0.35, 0.22), 0.0, index, [10, 7, 5][_detail], [5, 4, 3][_detail])
		if _detail == 0:
			for spot: int in 3:
				var angle: float = spot * TAU / 3.0 + index
				_crown(base + Vector3(cos(angle) * 0.075, height + 0.054, sin(angle) * 0.075), Vector3(0.018, 0.006, 0.018), Color(0.91, 0.82, 0.63), 0.0, spot, 5, 3)


func _leaf(start: Vector3, tip: Vector3, width: float, color: Color) -> void:
	var side: Vector3 = Vector3.UP.cross(tip - start).normalized() * width
	var middle: Vector3 = start.lerp(tip, 0.55) + Vector3.UP * 0.025
	_triangle(start, tip, middle - side, Vector3.UP, Vector3.UP, Vector3.UP, color, 0.6)
	_triangle(start, middle + side, tip, Vector3.UP, Vector3.UP, Vector3.UP, color * 1.05, 0.6)
	for vertex: int in range(_vertices.size() - 6, _vertices.size()):
		_uv2s[vertex].x = clampf(_vertices[vertex].distance_to(start) / start.distance_to(tip), 0.0, 1.0) * 0.6


func _fern() -> void:
	var fronds: int = [7, 5, 3][_detail]
	var divisions: int = [5, 3, 2][_detail]
	for frond: int in fronds:
		var angle: float = frond * TAU / fronds + 0.3
		var forward: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var side: Vector3 = Vector3.UP.cross(forward)
		var stem: Array[Vector3] = [Vector3(0, 0.03, 0), forward * 0.3 + Vector3.UP * 0.45, forward * 0.72 + Vector3.UP * 0.24]
		_branch(stem, [0.012, 0.008, 0.002], Color(0.31, 0.43, 0.19))
		_tag = 3.0
		for index: int in divisions:
			var progress: float = float(index + 1) / (divisions + 1)
			var center: Vector3 = forward * progress * 0.72 + Vector3.UP * (sin(progress * PI) * 0.32 + 0.08)
			for sign_value: float in [-1.0, 1.0]:
				_leaf(center, center + side * sign_value * (0.25 * (1.0 - progress) + 0.04) + forward * 0.09, 0.04, Color(0.32, 0.50, 0.24))


func _reeds() -> void:
	var count: int = [6, 4, 2][_detail]
	for index: int in count:
		var angle: float = index * 2.39996
		var side: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var base: Vector3 = side * (0.08 + (index % 3) * 0.08)
		var tip: Vector3 = base + side * 0.10 + Vector3.UP * (0.95 + (index % 3) * 0.16)
		_tube(base, tip, 0.012, 0.006, Color(0.48, 0.57, 0.25))
		_tag = 0.0
		_crown(tip, Vector3(0.035, 0.16, 0.035), Color(0.43, 0.30, 0.18), 0.0, index, [6, 5, 4][_detail], [4, 3, 2][_detail])
		_tag = 3.0
		_leaf(base + Vector3.UP * 0.20, base + side * 0.40 + Vector3.UP * 0.78, 0.035, Color(0.49, 0.62, 0.29))
		_leaf(base + Vector3.UP * 0.35, base - side * 0.33 + Vector3.UP * 0.98, 0.03, Color(0.56, 0.67, 0.32))


func _broadleaf() -> void:
	var wood: Color = Color(0.40, 0.32, 0.22)
	var points: Array[Vector3] = [Vector3(0, -0.3, 0), Vector3(-0.08, 1.5, 0.04), Vector3(0.12, 3.4, 0.14), Vector3(0.20, 5.3, -0.04), Vector3(0.35, 7.8, 0.10)]
	_branch(points, [0.50, 0.405, 0.31, 0.215, 0.12], wood)
	if _detail == 0:
		for index: int in 5:
			var angle: float = index * TAU / 5.0 + 0.2
			var end: Vector3 = Vector3(cos(angle) * 1.25, -0.12, sin(angle) * 1.25)
			_branch([Vector3(0, 0.9, 0), end * 0.55 + Vector3.UP * 0.10, end], [0.18, 0.14, 0.035], wood)
	for index: int in 5:
		var angle: float = index * TAU / 5.0 + 0.4
		var side: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var elbow: Vector3 = side * 1.35 + Vector3(0.1, 5.2 + (index % 2) * 0.7, 0.0)
		var tip: Vector3 = side * (3.2 + sin(index * 3.1) * 0.3) + Vector3.UP * (7.0 + (index % 3) * 0.55)
		_branch([Vector3(0.15, 3.9, 0.04), elbow, tip], [0.22, 0.14, 0.045], wood)
		_tag = 3.0
		_crown(tip + Vector3.UP * 0.5, Vector3(1.65, 1.45, 1.8), Color(0.44 + index * 0.012, 0.60, 0.25), 0.7, index)
		if _detail < 2:
			var fork: Vector3 = side.rotated(Vector3.UP, 0.55) * 2.4 + Vector3.UP * (7.6 + (index % 2) * 0.8)
			_tube(elbow, fork, 0.08, 0.025, wood)
			_tag = 3.0
			_crown(fork, Vector3(1.5, 1.5, 1.6), Color(0.49, 0.64, 0.28), 0.8, index + 8)
	_tag = 3.0
	for index: int in 3:
		var angle: float = index * TAU / 3.0
		_crown(Vector3(cos(angle), 9.1 + index * 0.25, sin(angle)), Vector3(1.8, 1.65, 1.8), Color(0.54, 0.68, 0.31), 1.0, index + 14)


func _pine() -> void:
	var wood: Color = Color(0.43, 0.30, 0.20)
	_branch([Vector3(0, -0.3, 0), Vector3(0.1, 6.0, 0.08), Vector3(0, 12.5, 0)], [0.36, 0.19, 0.025], wood)
	for level: int in 6:
		var base: float = 2.3 + level * 1.5
		var radius_value: float = 2.7 - level * 0.35
		var color: Color = Color(0.24 + level * 0.018, 0.43 + level * 0.018, 0.29)
		if _detail > 0:
			_tag = 3.0
			_cone(base, 3.1 - level * 0.2, radius_value, color)
			continue
		for branch: int in 6:
			var angle: float = branch * TAU / 6.0 + level * 0.71
			var side: Vector3 = Vector3(cos(angle), 0, sin(angle))
			var tip: Vector3 = side * radius_value + Vector3.UP * (base + 0.25 + sin(branch * 2.1) * 0.14)
			var start: Vector3 = Vector3(0.08, base + 0.85, 0.05)
			_tube(start, tip, 0.065, 0.015, wood)
			_tag = 3.0
			_crown(start.lerp(tip, 0.70), Vector3(0.7, 0.65, radius_value * 0.65), color, 0.7, level * 7 + branch, 8, 4, Basis.looking_at(side, Vector3.UP))
			# 在枝条末端叠加较小针叶簇，打破整层圆环轮廓。
			_crown(tip + Vector3.UP * 0.15, Vector3(0.42, 0.32, 0.6), color * 1.10, 0.8, branch + level, 6, 3, Basis.looking_at(side, Vector3.UP))
	_tag = 3.0
	if _detail == 0:
		_crown(Vector3(0.12, 11.5, 0.04), Vector3(0.62, 1.25, 0.65), Color(0.38, 0.56, 0.34), 0.8, 58, 8, 5)
	else:
		_cone(10.6, 2.3, 0.8, Color(0.38, 0.56, 0.34))


func _triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color, wind: float) -> void:
	_vertices.append_array(PackedVector3Array([a, b, c]))
	_normals.append_array(PackedVector3Array([na, nb, nc]))
	var linear: Color = color.srgb_to_linear()
	_colors.append_array(PackedColorArray([linear, linear, linear]))
	_uvs.append_array(PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]))
	_uv2s.append_array(PackedVector2Array([Vector2(wind, _tag), Vector2(wind, _tag), Vector2(wind, _tag)]))


func _crown(center: Vector3, scale: Vector3, color: Color, wind: float, seed_value: int, custom_segments: int = 0, custom_rings: int = 0, orientation: Basis = Basis.IDENTITY) -> void:
	# 不规则树冠保留柔和法线与轮廓起伏，颜色按冠层上下变化。
	var segments: int = custom_segments if custom_segments > 0 else [12, 7, 6][_detail]
	var rings: int = custom_rings if custom_rings > 0 else [7, 4, 3][_detail]
	for row: int in rings:
		for column: int in segments:
			var points: Array[Vector3] = []
			var directions: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
				var latitude: float = PI * float(row + corner.y) / rings
				var angle: float = TAU * float(column + corner.x) / segments
				var normal: Vector3 = Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
				var irregular: float = 1.0 + sin(angle * 4.0 + seed_value * 2.1 + latitude * 2.0) * sin(latitude) * 0.09
				points.append(center + orientation * (normal * scale * irregular))
				directions.append((orientation * (normal / scale)).normalized())
				uvs.append(Vector2(angle / TAU, latitude / PI))
			var start: int = _vertices.size()
			if row > 0:
				_triangle(points[0], points[1], points[2], directions[0], directions[1], directions[2], color, wind)
				_set_last_uv(uvs[0], uvs[1], uvs[2])
			if row < rings - 1:
				_triangle(points[2], points[1], points[3], directions[2], directions[1], directions[3], color, wind)
				_set_last_uv(uvs[2], uvs[1], uvs[3])
			for vertex: int in range(start, _vertices.size()):
				_colors[vertex] = (color * lerpf(0.72, 1.05, _normals[vertex].y * 0.5 + 0.5)).srgb_to_linear()


func _tube(start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	_branch([start, end], [bottom, top], color)


func _branch(points: Array[Vector3], radii: Array[float], color: Color) -> void:
	_tag = 1.0 if radii[0] > 0.04 else 0.0
	var segments: int = [10, 6, 5][_detail]
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var lengths: Array[float] = [0.0]
	# 相邻段共用弯折处的圆环，避免树干接缝出现空隙或纹理跳变。
	for row: int in points.size():
		var axis: Vector3 = (points[mini(row + 1, points.size() - 1)] - points[maxi(row - 1, 0)]).normalized()
		var tangent: Vector3 = SurfaceSites.tangent_forward(axis)
		var right: Vector3 = axis.cross(tangent)
		var ring: PackedVector3Array = []
		var directions: PackedVector3Array = []
		for column: int in segments:
			var angle: float = column * TAU / segments
			var normal: Vector3 = tangent * cos(angle) + right * sin(angle)
			ring.append(points[row] + normal * radii[row])
			directions.append(normal)
		rings.append(ring)
		normals.append(directions)
		if row > 0:
			lengths.append(lengths.back() + points[row].distance_to(points[row - 1]) * 0.65)
	for row: int in points.size() - 1:
		for column: int in segments:
			var next: int = (column + 1) % segments
			var u: float = float(column) / segments * 2.0
			var v: float = float(column + 1) / segments * 2.0
			_triangle(rings[row][column], rings[row + 1][column], rings[row][next], normals[row][column], normals[row + 1][column], normals[row][next], color, 0.0)
			_set_last_uv(Vector2(u, lengths[row]), Vector2(u, lengths[row + 1]), Vector2(v, lengths[row]))
			_triangle(rings[row][next], rings[row + 1][column], rings[row + 1][next], normals[row][next], normals[row + 1][column], normals[row + 1][next], color, 0.0)
			_set_last_uv(Vector2(v, lengths[row]), Vector2(u, lengths[row + 1]), Vector2(v, lengths[row + 1]))


func _cone(base: float, height: float, radius_value: float, color: Color) -> void:
	var segments: int = [12, 10, 7][_detail]
	for index: int in segments:
		var a: float = index * TAU / segments
		var b: float = (index + 1) * TAU / segments
		var na: Vector3 = Vector3(cos(a), 0.5, sin(a)).normalized()
		var nb: Vector3 = Vector3(cos(b), 0.5, sin(b)).normalized()
		var p: Vector3 = Vector3(cos(a) * radius_value * (1.0 + sin(a * 5.0 + base) * 0.13), base + sin(a * 4.0) * 0.15, sin(a) * radius_value)
		var q: Vector3 = Vector3(cos(b) * radius_value * (1.0 + sin(b * 5.0 + base) * 0.13), base + sin(b * 4.0) * 0.15, sin(b) * radius_value)
		_triangle(p, q, Vector3(0, base + height, 0), na, nb, Vector3.UP, color, 1.0)
		_triangle(q, p, Vector3(0, base, 0), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color * 0.65, 1.0)


func _grass() -> void:
	_tag = 0.0
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
			_uv2s[vertex].x = clampf(_vertices[vertex].y / height, 0.0, 1.0)


func _set_last_uv(a: Vector2, b: Vector2, c: Vector2) -> void:
	_uvs[_uvs.size() - 3] = a
	_uvs[_uvs.size() - 2] = b
	_uvs[_uvs.size() - 1] = c


func _tangents() -> PackedFloat32Array:
	var result: PackedFloat32Array = []
	result.resize(_vertices.size() * 4)
	for index: int in range(0, _vertices.size(), 3):
		var edge_a: Vector3 = _vertices[index + 1] - _vertices[index]
		var edge_b: Vector3 = _vertices[index + 2] - _vertices[index]
		var uv_a: Vector2 = _uvs[index + 1] - _uvs[index]
		var uv_b: Vector2 = _uvs[index + 2] - _uvs[index]
		var determinant: float = uv_a.cross(uv_b)
		var tangent: Vector3 = (edge_a * uv_b.y - edge_b * uv_a.y) / determinant if absf(determinant) > 0.000001 else Vector3.ZERO
		var bitangent: Vector3 = (edge_b * uv_a.x - edge_a * uv_b.x) / determinant if absf(determinant) > 0.000001 else Vector3.ZERO
		for corner: int in 3:
			var normal: Vector3 = _normals[index + corner]
			var local: Vector3 = tangent - normal * tangent.dot(normal)
			local = local.normalized() if local.length_squared() > 0.00001 else SurfaceSites.tangent_forward(normal)
			var offset: int = (index + corner) * 4
			result[offset] = local.x
			result[offset + 1] = local.y
			result[offset + 2] = local.z
			result[offset + 3] = -1.0 if normal.cross(local).dot(bitangent) < 0.0 else 1.0
	return result


func _rock() -> void:
	_tag = 2.0
	var segments: int = [16, 10, 7][_detail]
	for row: int in 4:
		for column: int in segments:
			var points: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
				var angle: float = (column + corner.x) * TAU / segments
				points.append(_rock_point(row + corner.y, angle))
			_rock_face(points[0], points[1], points[2], Color(0.67, 0.66, 0.59))
			_rock_face(points[2], points[1], points[3], Color(0.65, 0.65, 0.59))
	for column: int in segments:
		var angle: float = column * TAU / segments
		var next: float = (column + 1) * TAU / segments
		_rock_face(_rock_point(4, angle), _rock_point(4, next), Vector3(0, 0.94, 0), Color(0.71, 0.70, 0.62))
		_rock_face(_rock_point(0, next), _rock_point(0, angle), Vector3(0, -0.25, 0), Color(0.57, 0.57, 0.52))


func _rock_point(layer: int, angle: float) -> Vector3:
	var heights: Array[float] = [-0.25, -0.02, 0.32, 0.67, 0.94]
	var radii: Array[float] = [0.65, 1.0, 0.94, 0.88, 0.52]
	var radius_value: float = radii[layer] * (1.0 + sin(angle * 3.0 + 0.7) * 0.13 + cos(angle * 5.0) * 0.06)
	var point: Vector3 = Vector3(cos(angle) * radius_value, heights[layer] + sin(angle * 3.0) * 0.045, sin(angle) * radius_value * 0.83)
	point.x = minf(point.x, 0.79 - point.y * 0.18 - point.z * 0.12)
	return point


func _rock_face(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	_triangle(a, b, c, normal, normal, normal, color, 0.0)
	# 按主法线方向投影，避免竖直断面的纹理退化成单条色带。
	var axis: int = normal.abs().max_axis_index()
	var uvs: Array[Vector2] = []
	for point: Vector3 in [a, b, c]:
		uvs.append(Vector2(point.z, point.y) if axis == 0 else (Vector2(point.x, point.z) if axis == 1 else Vector2(point.x, point.y)))
	_set_last_uv(uvs[0], uvs[1], uvs[2])
