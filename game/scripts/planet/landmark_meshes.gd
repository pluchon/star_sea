class_name LandmarkMeshes
extends VegetationMeshes

# 远处可见的岩石地貌与人造遗迹。岩石用不规则截面沿路径扫掠，保留层理色带；
# 遗迹由 StoneworkMeshes 的石块拼合成单个网格，减少节点和绘制次数。


# 海蚀柱：底部埋入海床，越往上越细，每隔几米有一道内收的层理。
static func pillar(height: float, radius: float, seed_value: int) -> ArrayMesh:
	var path: Array[Vector3] = []
	var steps: int = maxi(int(height / 2.5), 4)
	for step: int in steps + 1:
		var along: float = float(step) / steps
		path.append(Vector3(sin(along * 2.3 + seed_value) * radius * 0.12, -6.0 + (height + 6.0) * along, cos(along * 1.7 + seed_value) * radius * 0.12))
	var radii: Array[float] = []
	for step: int in steps + 1:
		var along: float = float(step) / steps
		var ledge: float = 0.92 if step % 3 == 1 else 1.0
		radii.append(radius * lerpf(1.08, 0.72, along) * ledge)
	var builder: LandmarkMeshes = LandmarkMeshes.new()
	builder._sweep(path, radii, seed_value, true)
	return builder._finish()


# 天然石拱：沿半椭圆扫掠，两脚粗、拱顶细，拱顶上表面稍平。
static func arch(span: float, height: float, thickness: float, seed_value: int) -> ArrayMesh:
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	var steps: int = 22
	for step: int in steps + 1:
		var angle: float = PI * float(step) / steps
		path.append(Vector3(-cos(angle) * span * 0.5, sin(angle) * height - 4.0 * (1.0 - sin(angle)), 0.0))
		radii.append(thickness * lerpf(0.62, 1.0, pow(absf(cos(angle)), 1.5)))
	var builder: LandmarkMeshes = LandmarkMeshes.new()
	builder._sweep(path, radii, seed_value, false)
	return builder._finish()


# 把若干石块按各自的变换合成一个网格。
static func merge(parts: Array) -> ArrayMesh:
	var builder: LandmarkMeshes = LandmarkMeshes.new()
	for part: Array in parts:
		var mesh: ArrayMesh = part[0]
		var transform: Transform3D = part[1]
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for index: int in vertices.size():
			builder._vertices.append(transform * vertices[index])
			builder._normals.append((transform.basis * normals[index]).normalized())
			builder._colors.append(colors[index])
			builder._uvs.append(uvs[index])
			builder._uv2s.append(uv2s[index])
	return builder._finish()


func _sweep(path: Array[Vector3], radii: Array[float], seed_value: int, capped: bool) -> void:
	_tag = 2.0
	var sides: int = 9
	var rings: Array[Array] = []
	for index: int in path.size():
		var previous: Vector3 = path[maxi(index - 1, 0)]
		var following: Vector3 = path[mini(index + 1, path.size() - 1)]
		var forward: Vector3 = (following - previous).normalized()
		var side: Vector3 = Vector3.FORWARD if absf(forward.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var axis_a: Vector3 = forward.cross(side).normalized()
		var axis_b: Vector3 = forward.cross(axis_a).normalized()
		var ring: Array[Vector3] = []
		for corner: int in sides:
			var angle: float = TAU * float(corner) / sides
			# 截面半径按角度和高度起伏，相邻环的起伏相关，岩面不会出现规则的棱柱。
			var bulge: float = 1.0 + sin(angle * 3.0 + seed_value * 1.7 + index * 0.45) * 0.10 + sin(angle * 5.0 - seed_value + index * 0.9) * 0.06
			ring.append(path[index] + (axis_a * cos(angle) + axis_b * sin(angle)) * radii[index] * bulge)
		rings.append(ring)
	for index: int in rings.size() - 1:
		# 层理：相邻两环颜色略有深浅，远看是横向的色带。
		var tone: float = 0.93 + 0.07 * sin(index * 1.9 + seed_value)
		var color: Color = Color(0.66, 0.63, 0.57) * tone
		for corner: int in sides:
			var next: int = (corner + 1) % sides
			var a: Vector3 = rings[index][corner]
			var b: Vector3 = rings[index + 1][corner]
			var c: Vector3 = rings[index][next]
			var d: Vector3 = rings[index + 1][next]
			_outward_face(a, b, c, path[index], color)
			_outward_face(c, b, d, path[index], color)
	if capped:
		var top: Array = rings[rings.size() - 1]
		var summit: Vector3 = path[path.size() - 1] + Vector3.UP * radii[radii.size() - 1] * 0.25
		for corner: int in sides:
			# 柱顶长着一层草皮，颜色偏黄绿。
			_outward_face(top[corner], top[(corner + 1) % sides], summit, summit - Vector3.UP * 10.0, Color(0.52, 0.60, 0.33))


func _outward_face(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var outward: Vector3 = (a + b + c) / 3.0 - inside
	if (c - a).cross(b - a).dot(outward) < 0.0:
		_rock_face(a, c, b, color)
	else:
		_rock_face(a, b, c, color)


func _finish() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
