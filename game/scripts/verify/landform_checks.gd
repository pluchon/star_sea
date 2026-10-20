extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var failures: Array[String] = []
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0)
	var forms: DawnLandforms = noise.features.landforms
	var highest: float = -INF
	var highest_direction: Vector3 = Vector3.ZERO
	for peak: Dictionary in forms.metadata["peaks"]:
		var direction: Vector3 = peak["direction"]
		for x: int in range(-5, 6):
			for y: int in range(-5, 6):
				var point: Vector3 = (direction * noise.radius + Vector3(peak["right"]) * x * 150.0 + Vector3(peak["forward"]) * y * 150.0).normalized()
				var elevation: float = noise.height(point)
				if elevation > highest:
					highest = elevation
					highest_direction = point
	if highest < 3500.0 or highest > 4200.0 or forms.nearest(highest_direction).x > DawnLandforms.RANGE_HALF_WIDTH:
		failures.append("主山脉最高点不在 3500～4200 米之间。")
	var spawn: Vector3 = forms.metadata["spawn"]
	var ridge_distance: float = forms.nearest(spawn).x
	if ridge_distance < 6000.0 or ridge_distance > 10000.0:
		failures.append("脊线离出发地距离不符合 6～10 公里。")
	if absf(noise.height(spawn) - float(noise.features.site["height_m"])) > 0.1:
		failures.append("出发地高度发生变化。")
	var visible_peak: bool = false
	for peak: Dictionary in forms.metadata["peaks"]:
		var start: Vector3 = spawn * (noise.radius + noise.height(spawn) + 1.75)
		var end: Vector3 = Vector3(peak["direction"]) * (noise.radius + noise.height(peak["direction"]) + 20.0)
		var blocked: bool = false
		for index: int in range(1, 100):
			var point: Vector3 = start.lerp(end, index / 100.0)
			if point.length() < noise.radius + noise.height(point.normalized()):
				blocked = true
				break
		visible_peak = visible_peak or not blocked
	if not visible_peak:
		failures.append("出发地看不到任一名峰。")
	var routes: Array[Dictionary] = []
	for pass_site: Dictionary in forms.metadata["passes"]:
		routes.append(_pass_route(noise, pass_site, forms))
	var walkable: int = 0
	for route: Dictionary in routes:
		if route["passed"]:
			walkable += 1
	if walkable < 2:
		failures.append("能走通的山口不足两个。")
	var maximum_depth: float = 0.0
	var minimum_depth: float = INF
	var river_samples: int = 0
	var floor_monotonic: bool = true
	var previous: float = INF
	for segment: int in forms.canyon.size() - 1:
		for sample: int in 20:
			var direction: Vector3 = forms.canyon[segment].slerp(forms.canyon[segment + 1], sample / 20.0).normalized()
			var floor_height: float = forms.height(direction, noise.base_height(direction))
			floor_monotonic = floor_monotonic and floor_height <= previous + 0.05
			previous = floor_height
			var tangent: Vector3 = forms.canyon[segment].direction_to(forms.canyon[segment + 1]).slide(direction).normalized()
			var side: Vector3 = tangent.cross(direction).normalized()
			var rim: Vector3 = SurfaceSites.offset_direction(direction, side, DawnLandforms.CANYON_HALF_WIDTH, noise.radius)
			var depth: float = noise.height(rim) - noise.height(direction)
			maximum_depth = maxf(maximum_depth, depth)
			minimum_depth = minf(minimum_depth, depth)
			if noise.water_surface(direction) > -INF and noise.river_distance(direction) < 150.0:
				river_samples += 1
	if maximum_depth < 700.0 or maximum_depth > 1000.0:
		failures.append("峡谷最大深度不在 700～1000 米之间：%.2f" % maximum_depth)
	if not floor_monotonic:
		failures.append("峡谷谷底未保持单调下降。")
	if river_samples == 0:
		failures.append("峡谷谷底没有烘焙河流。")
	var wall_vertices: int = 0
	var glacier_vertices: int = 0
	var ordinary: Color = forms.surface_marks(spawn, noise.height(spawn), 0.0)
	if ordinary.r > 0.001 or ordinary.g > 0.001:
		failures.append("普通出发地包含特殊地表标记。")
	for peak: Dictionary in forms.metadata["peaks"]:
		for offset: int in range(-20, 21):
			var direction: Vector3 = (Vector3(peak["direction"]) * noise.radius + Vector3(peak["forward"]) * offset * 100.0).normalized()
			var elevation: float = noise.height(direction)
			if forms.surface_marks(direction, elevation, noise.slope(direction, elevation)).g > 0.0:
				glacier_vertices += 1
	for direction: Vector3 in forms.canyon:
		var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
		for offset: float in [300.0, 500.0, 900.0]:
			var point: Vector3 = SurfaceSites.offset_direction(direction, tangent, offset, noise.radius)
			var elevation: float = noise.height(point)
			if forms.surface_marks(point, elevation, noise.slope(point, elevation)).r > 0.0:
				wall_vertices += 1
	if wall_vertices == 0 or glacier_vertices == 0:
		failures.append("峡谷或冰川缺少有效的特殊地表标记。")
	var patch: Dictionary = TerrainChunkBuilder.build(noise, Vector3.UP, Vector3.FORWARD, Vector3.LEFT, -0.05, -0.05, 0.1, 4, 10.0)
	var arrays: Array = patch["terrain"]
	var marks: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if marks.size() != positions.size() * 4:
		failures.append("地形及裙边没有为每个顶点写入 CUSTOM0 四通道。")
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "highest_m": highest, "spawn_ridge_distance_m": ridge_distance, "peak_visible": visible_peak, "range_length_m": forms.ridge_lengths[-1], "canyon_length_m": forms.canyon_lengths[-1], "maximum_depth_m": maximum_depth, "minimum_depth_m": minimum_depth, "floor_monotonic": floor_monotonic, "river_samples": river_samples, "layers": DawnLandforms.CANYON_LAYERS, "wall_marks": wall_vertices, "glacier_marks": glacier_vertices, "passes": routes}
	VerificationMetrics.write_json("res://../test-output/wanderer/landform_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _pass_route(noise: TerrainNoise, pass_site: Dictionary, forms: DawnLandforms) -> Dictionary:
	const SPACING: float = 20.0
	const COLUMNS: int = 801
	const ROWS: int = 21
	var center: Vector3 = pass_site["direction"]
	var nearest: Vector3 = forms.nearest(center)
	var segment: int = clampi(int(nearest.z), 0, forms.ridge.size() - 2)
	var along: Vector3 = pass_site["along"]
	var across: Vector3 = pass_site["across"]
	var heights: PackedFloat32Array = []
	heights.resize(COLUMNS * ROWS)
	for row: int in ROWS:
		for column: int in COLUMNS:
			var point: Vector3 = (center * noise.radius + across * (column - COLUMNS / 2) * SPACING + along * (row - ROWS / 2) * SPACING).normalized()
			heights[row * COLUMNS + column] = noise.height(point)
	var queue: PackedInt32Array = [ROWS / 2 * COLUMNS]
	var distances: PackedFloat32Array = []
	distances.resize(heights.size())
	distances.fill(-1)
	distances[queue[0]] = 0
	var cursor: int = 0
	var route_length: float = -1
	while cursor < queue.size():
		var cell: int = queue[cursor]
		cursor += 1
		if cell % COLUMNS == COLUMNS - 1:
			route_length = distances[cell]
			break
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = cell % COLUMNS + offset.x
			var y: int = cell / COLUMNS + offset.y
			if x < 0 or x >= COLUMNS or y < 0 or y >= ROWS:
				continue
			var next: int = y * COLUMNS + x
			if distances[next] >= 0 or absf(heights[next] - heights[cell]) > SPACING * 0.45:
				continue
			distances[next] = distances[cell] + SPACING
			queue.append(next)
	return {"passed": route_length > 0, "route_length_m": route_length, "grid_spacing_m": SPACING, "saddle_height_m": noise.height(center)}
