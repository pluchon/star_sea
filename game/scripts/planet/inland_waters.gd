class_name InlandWaters
extends Node3D

# 样板区的河面与湖面网格。挂在星球节点下，坐标以星球中心为原点，随星球一起参与浮动原点平移。
# 河面是沿河道的条带，略宽于河床，边缘压在河岸下面；湖面是覆盖湖区格子的弯曲平面，
# 由地形自然遮住高于水位的部分。

var river_count: int = 0
var lake_count: int = 0


func build(features: TerrainFeatures) -> void:
	var river_material: ShaderMaterial = ShaderMaterial.new()
	river_material.shader = load("res://shaders/inland_water.gdshader") as Shader
	river_material.set_shader_parameter("flowing", true)
	var lake_material: ShaderMaterial = ShaderMaterial.new()
	lake_material.shader = river_material.shader
	lake_material.set_shader_parameter("flowing", false)
	for river: Dictionary in features.rivers:
		var mesh: ArrayMesh = _river_mesh(features, river)
		if mesh != null:
			_add(mesh, river_material, features, (river["points"] as PackedVector2Array)[0])
			river_count += 1
	for lake: Dictionary in features.lakes:
		var cells: PackedInt32Array = lake["cells"]
		_add(_lake_mesh(features, lake), lake_material, features, features.cell_center(cells[0]))
		lake_count += 1


func _add(mesh: ArrayMesh, material: ShaderMaterial, features: TerrainFeatures, anchor: Vector2) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 网格顶点相对锚点保存，避免四万米的球面坐标损失单精度。
	instance.position = features.direction_at(anchor) * features.radius
	add_child(instance)


func _river_mesh(features: TerrainFeatures, river: Dictionary) -> ArrayMesh:
	var points: PackedVector2Array = river["points"]
	var levels: PackedFloat32Array = river["levels"]
	var widths: PackedFloat32Array = river["widths"]
	if points.size() < 2:
		return null
	var origin: Vector3 = features.direction_at(points[0]) * features.radius
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var uv2s: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var travelled: float = 0.0
	for index: int in points.size():
		var previous: Vector2 = points[maxi(index - 1, 0)]
		var following: Vector2 = points[mini(index + 1, points.size() - 1)]
		var along: Vector2 = (following - previous).normalized()
		var side: Vector2 = Vector2(-along.y, along.x)
		if index > 0:
			travelled += points[index].distance_to(points[index - 1])
		# 水面比河床宽一些，两侧边缘埋进河岸。
		var half: float = widths[index] * 1.15
		for sign_value: float in [-1.0, 1.0]:
			var direction: Vector3 = features.direction_at(points[index] + side * half * sign_value)
			vertices.append(direction * (features.radius + levels[index]) - origin)
			normals.append(direction)
			uvs.append(Vector2(sign_value, travelled))
			uv2s.append(Vector2(widths[index], 0.0))
		if index > 0:
			var base: int = (index - 1) * 2
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	return _mesh(vertices, normals, uvs, uv2s, indices)


func _lake_mesh(features: TerrainFeatures, lake: Dictionary) -> ArrayMesh:
	var cells: PackedInt32Array = lake["cells"]
	var level: float = lake["level"]
	var origin: Vector3 = features.direction_at(features.cell_center(cells[0])) * features.radius
	# 湖区外再加一圈格子，让湖岸由地形与水面的交线决定，而不是格子的直边。
	var covered: Dictionary = {}
	var size: int = features.grid_size()
	for cell: int in cells:
		var row: int = cell / size
		var column: int = cell % size
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var next_row: int = row + offset_y
				var next_column: int = column + offset_x
				if next_row >= 0 and next_column >= 0 and next_row < size and next_column < size:
					covered[next_row * size + next_column] = true
	var corners: Dictionary = {}
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var uv2s: PackedVector2Array = []
	var indices: PackedInt32Array = []
	for cell: int in covered:
		var row: int = cell / size
		var column: int = cell % size
		var quad: PackedInt32Array = []
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var key: Vector2i = Vector2i(column + corner.x, row + corner.y)
			if not corners.has(key):
				var point: Vector2 = Vector2(-TerrainFeatures.HALF_SIZE + key.x * TerrainFeatures.CELL, -TerrainFeatures.HALF_SIZE + key.y * TerrainFeatures.CELL)
				var direction: Vector3 = features.direction_at(point)
				corners[key] = vertices.size()
				vertices.append(direction * (features.radius + level) - origin)
				normals.append(direction)
				uvs.append(point)
				uv2s.append(Vector2(0.0, 1.0))
			quad.append(corners[key])
		indices.append_array(PackedInt32Array([quad[0], quad[2], quad[1], quad[1], quad[2], quad[3]]))
	return _mesh(vertices, normals, uvs, uv2s, indices)


func _mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
