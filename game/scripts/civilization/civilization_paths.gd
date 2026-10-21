class_name CivilizationPaths
extends RefCounted

const GRID: float = 20.0 # 寻路间距，米。
const SAMPLE: float = 10.0 # 最终道路点间距，米。


static func find(noise: TerrainNoise, start: Vector3, end: Vector3, bridges: Array[Dictionary] = []) -> PackedVector3Array:
	var center: Vector3 = start.slerp(end, 0.5).normalized()
	var forward: Vector3 = start.direction_to(end).slide(center).normalized()
	var right: Vector3 = forward.cross(center).normalized()
	var half_length: float = tan(start.angle_to(end) * 0.5) * noise.radius
	for margin: float in [800.0, 1800.0, 3500.0, 6500.0, 10000.0]:
		var grid: AStarGrid2D = AStarGrid2D.new()
		grid.region = Rect2i(-ceili(margin / GRID), -ceili((half_length + margin) / GRID), ceili(margin * 2.0 / GRID) + 1, ceili((half_length + margin) * 2.0 / GRID) + 1)
		grid.cell_size = Vector2.ONE * GRID
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for y: int in range(grid.region.position.y, grid.region.end.y):
			for x: int in range(grid.region.position.x, grid.region.end.x):
				var id: Vector2i = Vector2i(x, y)
				var direction: Vector3 = (center * noise.radius + right * x * GRID + forward * y * GRID).normalized()
				var height: float = noise.height(direction)
				var wet: bool = height < 1.0 or noise.water_surface(direction, height) > -INF
				var planned_crossing: bool = false
				if wet:
					var crossing: bool = false
					for bridge: Dictionary in bridges:
						var p: Vector3 = direction * noise.radius
						crossing = crossing or p.distance_to(Geometry3D.get_closest_point_to_segment(p, bridge["a"] * noise.radius, bridge["b"] * noise.radius)) < GRID * 0.8
					var river: Vector4 = noise.features.hydrology.nearest(direction)
					# 河流交点作为待建桥的图节点；湖泊和开阔海面仍不可通行。
					planned_crossing = river.w >= 0 and river.x < river.z * 1.1 and river.z <= 28.0 and noise.features.hydrology.lake_surface(direction) == -INF
					crossing = crossing or planned_crossing
					if not crossing:
						grid.set_point_solid(id)
						continue
				var slope: float = noise.slope(direction, height)
				grid.set_point_weight_scale(id, (1.0 + slope * slope * 800.0 / GRID) * (10.0 if slope > 0.35 else 1.0) + (100.0 if planned_crossing else 0.0))
		var a: Vector2i = Vector2i(roundi(start.dot(right) / start.dot(center) * noise.radius / GRID), roundi(start.dot(forward) / start.dot(center) * noise.radius / GRID))
		var b: Vector2i = Vector2i(roundi(end.dot(right) / end.dot(center) * noise.radius / GRID), roundi(end.dot(forward) / end.dot(center) * noise.radius / GRID))
		grid.set_point_solid(a, false)
		grid.set_point_solid(b, false)
		var path: Array[Vector2i] = grid.get_id_path(a, b)
		if path.is_empty():
			continue
		var points: PackedVector3Array = [start]
		for id: Vector2i in path:
			points.append((center * noise.radius + right * id.x * GRID + forward * id.y * GRID).normalized())
		points.append(end)
		for iteration: int in 2:
			var smooth: PackedVector3Array = [points[0]]
			for index: int in points.size() - 1:
				smooth.append(points[index].slerp(points[index + 1], 0.25).normalized())
				smooth.append(points[index].slerp(points[index + 1], 0.75).normalized())
			smooth.append(points[-1])
			points = smooth
		return resample(points, noise.radius)
	push_error("文明烘焙失败：道路寻路没有找到可通行的陆地或桥梁。")
	return []


static func resample(points: PackedVector3Array, radius: float, spacing: float = SAMPLE) -> PackedVector3Array:
	var result: PackedVector3Array = [points[0]]
	var carry: float = 0.0
	for index: int in points.size() - 1:
		var distance: float = points[index].angle_to(points[index + 1]) * radius
		var along: float = spacing - carry
		while along < distance:
			result.append(points[index].slerp(points[index + 1], along / distance).normalized())
			along += spacing
		carry = distance - (along - spacing)
	if result[-1].distance_to(points[-1]) * radius > 0.05:
		result.append(points[-1])
	return result


static func road(noise: TerrainNoise, points: PackedVector3Array, width: float, name: String) -> Dictionary:
	var heights: PackedFloat32Array = []
	var levels: PackedFloat32Array = []
	var wear: PackedFloat32Array = []
	for direction: Vector3 in points:
		heights.append(noise.height(direction))
	for index: int in points.size():
		var sum: float = 0.0
		var count: int = 0
		for sample: int in range(maxi(index - 2, 0), mini(index + 3, points.size())):
			sum += heights[sample]
			count += 1
		var river: Vector4 = noise.features.hydrology.nearest(points[index])
		var civil: CivilizationTerrain = noise.features.civilization
		if civil != null and points[index].distance_to(civil.data.town["direction"]) * noise.radius < 32.0:
			levels.append(civil.data.town["level"])
		else:
			levels.append(heights[index] if river.w >= 0 and river.x < river.z + 15.0 else clampf(sum / count, heights[index] - 1.5, heights[index] + 1.5))
		wear.append(lerpf(0.4, 0.95, clampf(1.0 - (points.size() - index - 1) * SAMPLE / 800.0, 0, 1)) if name == "old_road" else 0.1)
	return {"name": name, "points": points, "levels": levels, "width": width, "wear": wear}
