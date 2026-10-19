extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0)
	var plant_triangles: int = 0
	var models: Dictionary = ModelChecks.run()
	_failures.append_array(models["failures"])
	for kind: String in ["broadleaf", "pine", "shrub", "stone", "fern", "reeds"]:
		var mesh: ArrayMesh = VegetationMeshes.create(kind)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index: int in range(0, vertices.size(), 3):
			var cross_product: Vector3 = (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
			var normal: Vector3 = normals[index] + normals[index + 1] + normals[index + 2]
			if cross_product.dot(normal) > 0.0001:
				_failures.append(kind + "的三角形绕序与外法线不符。")
			plant_triangles += 1
	var stats: Dictionary = TerrainStatistics.collect(noise)
	for biome: String in DawnBiomes.NAMES:
		if int((stats["biomes"] as Dictionary).get(biome, 0)) == 0:
			_failures.append("球面抽样缺少群系：" + biome)
	if not stats["passed"]:
		_failures.append("地形海陆和高度范围不符合约束。")
	var geometry: Dictionary = TerrainGeometryChecks.run()
	if not geometry["passed"]:
		_failures.append("整球网格或碰撞高度不一致。")
	var directions: Array[Vector3] = []
	for face: int in PlanetTerrain.FACES.size():
		var axes: Array = PlanetTerrain.FACES[face]
		for edge: Vector2 in [Vector2.ZERO, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(0.9999, 0.3)]:
			directions.append(((axes[0] as Vector3) + (axes[1] as Vector3) * edge.x + (axes[2] as Vector3) * edge.y).normalized())
	var coverage_samples: int = 0
	for up: Vector3 in directions:
		for divisions: int in [SurfaceDetails.NEAR_DIVISIONS, SurfaceDetails.FOREST_DIVISIONS]:
			var distance: float = SurfaceDetails.NEAR_DISTANCE if divisions == SurfaceDetails.NEAR_DIVISIONS else SurfaceDetails.FOREST_DISTANCE
			var keys: Array[Vector3i] = SurfaceGrid.nearby(up, noise.radius, distance, divisions)
			var forward: Vector3 = SurfaceSites.tangent_forward(up)
			for heading: int in 24:
				var target: Vector3 = SurfaceSites.offset_direction(up, forward.rotated(up, heading * TAU / 24.0), distance * 0.95, noise.radius)
				var found: bool = keys.has(SurfaceGrid.cell_at(target, divisions))
				if not found:
					_failures.append("球面边界附近遗漏植被分块：" + str(up))
				coverage_samples += 1
	var total_instances: Dictionary = {}
	for kind: String in SurfaceDetails.KINDS:
		total_instances[kind] = 0
	var site: Dictionary = SurfaceSites.find(noise)
	var ruin_direction: Vector3 = SurfaceSites.ruin_direction(site, noise.radius)
	for divisions: int in [SurfaceDetails.NEAR_DIVISIONS, SurfaceDetails.FOREST_DIVISIONS]:
		var keys: Array[Vector3i] = SurfaceGrid.nearby(site["direction"], noise.radius, 450.0, divisions)
		for cell: Vector3i in keys:
			var key: Vector4i = Vector4i(divisions, cell.x, cell.y, cell.z)
			var first: Dictionary = SurfaceDetails.generate(noise, key, 20261019, site["direction"], ruin_direction)
			# 模拟卸载后重新创建；不依赖摄像机或切平面的历史状态。
			var second: Dictionary = SurfaceDetails.generate(TerrainNoise.new(20261019, 40000.0), key, 20261019, site["direction"], ruin_direction)
			for kind: String in SurfaceDetails.KINDS:
				if first[kind] != second[kind] or first[kind + "_colors"] != second[kind + "_colors"]:
					_failures.append("卸载后重新生成改变了植物分布。")
				total_instances[kind] += (first[kind] as Array).size()
				for transform: Transform3D in first[kind]:
					var position: Vector3 = (first["center"] as Vector3) + transform.origin
					var direction: Vector3 = position.normalized()
					var elevation: float = noise.height(direction)
					if elevation < 2.9 or absf(position.length() - noise.radius - elevation + 0.08) > 0.03:
						_failures.append("植物贴地异常：高度 %.5f，贴地误差 %.5f" % [elevation, absf(position.length() - noise.radius - elevation + 0.08)])
					if kind == "broadleaf" or kind == "pine":
						if noise.temperature(direction, elevation) < 0.239 or noise.moisture(direction) < 0.339 or elevation > 1400.1:
							_failures.append("树木越过群系气候限制。")
						if direction.distance_to(ruin_direction) * noise.radius < 9.99:
							_failures.append("树木侵入遗迹空地。")
						if noise.slope(direction, elevation) > 0.66:
							_failures.append("树木出现在过陡坡面。")
	if total_instances["broadleaf"] + total_instances["pine"] == 0 or total_instances["shrub"] == 0 or total_instances["flowers"] == 0:
		_failures.append("出生区域缺少植被层次。")
	var global_trees: Dictionary = {"broadleaf": 0, "pine": 0}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261019
	for face: int in 6:
		for sample: int in 32:
			var key: Vector4i = Vector4i(SurfaceDetails.FOREST_DIVISIONS, face, rng.randi_range(0, 127), rng.randi_range(0, 127))
			var generated: Dictionary = SurfaceDetails.generate(noise, key, 20261019)
			global_trees["broadleaf"] += (generated["broadleaf"] as Array).size()
			global_trees["pine"] += (generated["pine"] as Array).size()
	if global_trees["broadleaf"] == 0 or global_trees["pine"] == 0:
		_failures.append("全球采样缺少阔叶林或针叶林。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "models": models, "plant_triangles_checked": plant_triangles, "global_tree_samples": global_trees, "terrain": stats, "geometry": geometry, "seam_coverage_samples": coverage_samples, "instances_within_450m_cells": total_instances}
	VerificationMetrics.write_json("res://../test-output/p4/ecology_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)
