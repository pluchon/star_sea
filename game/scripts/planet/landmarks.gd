class_name Landmarks
extends Node3D

# 样板区里远处可见的地标：海蚀柱、海蚀拱门、灯塔残骸、山顶石塔和倒下的巨环。
# 位置由 TerrainFeatures 计算，这里只负责建网格和碰撞；坐标以星球中心为原点。

var built: Array[String] = []
var _material: ShaderMaterial
var _features: TerrainFeatures
var _noise: TerrainNoise


func build(noise: TerrainNoise) -> void:
	_noise = noise
	_features = noise.features
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/surface_detail.gdshader") as Shader
	_material.set_shader_parameter("wind_strength", 0.0)
	_material.set_shader_parameter("bark_color", load("res://textures/painted/bark.svg"))
	_material.set_shader_parameter("rock_color", load("res://textures/painted/stone.svg"))
	_material.set_shader_parameter("leaf_color", load("res://textures/painted/leaves.svg"))
	for landmark: Dictionary in _features.landmarks:
		var kind: String = landmark["kind"]
		match kind:
			"sea_stack":
				_sea_stack(landmark)
			"sea_arch":
				_sea_arch(landmark)
			"lighthouse":
				_lighthouse(landmark)
			"peak_tower":
				if _features.civilization == null or _features.civilization.data.beacons.is_empty():
					_peak_tower(landmark)
			"fallen_ring":
				_fallen_ring(landmark)
		built.append(kind)


func _anchor(landmark: Dictionary, sink: float = 0.0) -> Transform3D:
	var point: Vector2 = landmark["point"]
	var up: Vector3 = _features.direction_at(point)
	var facing: float = landmark["facing"]
	var heading: Vector3 = _features.axis_u * cos(facing) + _features.axis_v * sin(facing)
	heading = (heading - up * heading.dot(up)).normalized()
	var ground: float = _features.height_at(_noise, point)
	return Transform3D(Basis.looking_at(heading, up), up * (_features.radius + ground - sink))


func _body(name_value: String, transform: Transform3D, mesh: ArrayMesh, shapes: Array) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_value
	body.collision_layer = 2
	body.transform = transform
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material
	body.add_child(visual)
	for shape: Array in shapes:
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape[0]
		collider.transform = shape[1]
		body.add_child(collider)
	add_child(body)
	return body


func _sea_stack(landmark: Dictionary) -> void:
	# 柱脚落在海床上，总高度包含水下部分。
	var anchor: Transform3D = _anchor(landmark)
	var seabed: float = _features.height_at(_noise, landmark["point"])
	var mesh: ArrayMesh = LandmarkMeshes.pillar(landmark["height"] - seabed, landmark["radius"], int(landmark["facing"] * 10.0))
	_body("SeaStack", anchor, mesh, [[mesh.create_convex_shape(), Transform3D.IDENTITY]])


func _sea_arch(landmark: Dictionary) -> void:
	var anchor: Transform3D = _anchor(landmark)
	var seabed: float = _features.height_at(_noise, landmark["point"])
	var mesh: ArrayMesh = LandmarkMeshes.arch(landmark["radius"], landmark["height"] - seabed, 5.5, 7)
	_body("SeaArch", anchor, mesh, [[mesh.create_trimesh_shape(), Transform3D.IDENTITY]])


func _lighthouse(landmark: Dictionary) -> void:
	# 圆形塔身由弧形石块一层层砌成，顶上几层逐渐缺块，塔下散落几块落石。
	var radius_value: float = landmark["radius"]
	var courses: int = int(float(landmark["height"]) / 0.86)
	var parts: Array = []
	var upright: Basis = Basis(Vector3.RIGHT, -PI * 0.5)
	for course: int in courses:
		var blocks: int = 10
		for block: int in blocks:
			var missing: bool = course > courses - 5 and (block * 7 + course * 3) % 10 < (course - courses + 6) * 2
			if missing:
				continue
			var angle: float = (float(block) + (0.5 if course % 2 == 1 else 0.0)) * TAU / blocks
			var mesh: ArrayMesh = StoneworkMeshes.block(Vector3(TAU * radius_value / blocks * 0.97, 0.75, 0.84), course * 13 + block, Vector2(angle, radius_value))
			parts.append([mesh, Transform3D(upright, Vector3(0.0, 0.42 + course * 0.86, 0.0))])
	for fallen: int in 5:
		var spot: Vector3 = Vector3(cos(fallen * 1.7) * (radius_value + 2.5 + fallen), 0.2, sin(fallen * 1.7) * (radius_value + 2.0 + fallen * 0.7))
		parts.append([StoneworkMeshes.block(Vector3(1.4, 0.8, 0.9), 90 + fallen), Transform3D(Basis.from_euler(Vector3(0.2 * fallen, fallen * 0.9, 0.1)), spot)])
	var mesh_value: ArrayMesh = LandmarkMeshes.merge(parts)
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = radius_value + 0.4
	cylinder.height = courses * 0.86
	_body("LighthouseRuin", _anchor(landmark, 0.4), mesh_value, [[cylinder, Transform3D(Basis.IDENTITY, Vector3(0.0, cylinder.height * 0.5, 0.0))]])


func _peak_tower(landmark: Dictionary) -> void:
	# 方形石塔：每层四面墙各一块长石，层间错缝；塔顶一圈略外挑的檐口。
	var half: float = landmark["radius"]
	var height_value: float = landmark["height"]
	var courses: int = int(height_value / 0.95)
	var parts: Array = []
	for course: int in courses:
		var crown: float = 0.45 if course >= courses - 2 else 0.0
		for side: int in 4:
			var basis: Basis = Basis(Vector3.UP, side * PI * 0.5)
			var length: float = half * 2.0 + 1.0 + crown * 2.0 - (1.0 if (course + side) % 2 == 0 else 0.0)
			var mesh: ArrayMesh = StoneworkMeshes.block(Vector3(length, 0.92, 1.0), course * 5 + side)
			parts.append([mesh, Transform3D(basis, basis * Vector3(0.0, 0.47 + course * 0.95, half + crown))])
	# 塔身用偏暗的石色，和雪顶拉开对比；顶上插一面长旗。
	var mesh_value: ArrayMesh = LandmarkMeshes.merge(parts, Color(0.62, 0.56, 0.52))
	var top: float = courses * 0.95
	var flag: MeshInstance3D = MeshInstance3D.new()
	flag.mesh = LandmarkMeshes.banner(9.0, 7.0)
	flag.material_override = _material
	flag.position = Vector3(0.0, top, 0.0)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(half * 2.0 + 1.0, courses * 0.95, half * 2.0 + 1.0)
	var tower: StaticBody3D = _body("PeakTower", _anchor(landmark, 1.5), mesh_value, [[box, Transform3D(Basis.IDENTITY, Vector3(0.0, box.size.y * 0.5, 0.0))]])
	tower.add_child(flag)


func _fallen_ring(landmark: Dictionary) -> void:
	# 一个直径三十米的石环斜立在草地上，下半部埋进土里，顶上缺了几块，远处就能看到这道拱圈。
	var radius_value: float = landmark["radius"]
	var blocks: int = 26
	var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(-22.0))
	var center: Vector3 = Vector3(0.0, radius_value * 0.35, 0.0)
	var parts: Array = []
	var shapes: Array = []
	for block: int in blocks:
		if block in [1, 2, 24]:
			continue
		var angle: float = (float(block) + 0.5) * TAU / blocks
		var mesh: ArrayMesh = StoneworkMeshes.block(Vector3(TAU * radius_value / blocks * 0.96, 2.4, 2.2), 40 + block, Vector2(angle, radius_value))
		var transform: Transform3D = Transform3D(tilt, center)
		parts.append([mesh, transform])
		var middle: Vector3 = Vector3(sin(angle) * (radius_value + 1.2), cos(angle) * (radius_value + 1.2), 0.0)
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(TAU * radius_value / blocks, 2.4, 2.2)
		shapes.append([box, transform * Transform3D(Basis(Vector3.BACK, -angle), middle)])
	_body("FallenRing", _anchor(landmark), LandmarkMeshes.merge(parts), shapes)
