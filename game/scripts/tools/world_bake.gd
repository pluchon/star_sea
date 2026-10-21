extends SceneTree

const SIZE: int = HydrologyData.GRID
const COUNT: int = 6 * SIZE * SIZE
const OFFSETS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
var _data: HydrologyData
var _noise: TerrainNoise
var _features: TerrainFeatures
var _neighbors: PackedInt32Array
var _directions: PackedVector3Array
var _heights: PackedFloat32Array
var _areas: PackedFloat32Array
var _parent: PackedInt32Array
var _filled: PackedFloat32Array
var _order: PackedInt32Array
var _lake_ids: PackedInt32Array
var _heap_keys: PackedFloat32Array
var _heap_values: PackedInt32Array
var _junctions: Dictionary = {}


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var started: int = Time.get_ticks_msec()
	# 独立保存原有布局；删除烘焙结果后也能从基础地形完整重建水系。
	var layout_path: String = "res://data/dawn_layout.tres"
	if not ResourceLoader.exists(layout_path):
		var previous: HydrologyData = load(HydrologyData.PATH) as HydrologyData
		var initial_layout: HydrologyData = HydrologyData.new()
		initial_layout.metadata = previous.metadata
		ResourceSaver.save(initial_layout, layout_path)
	var layout: HydrologyData = load(layout_path) as HydrologyData
	_noise = TerrainNoise.new(20261019, 40000.0, 0, false)
	_features = TerrainFeatures.new()
	_features.radius = _noise.radius
	for property: String in ["site", "center", "axis_u", "axis_v", "volcano", "volcano_base"]:
		_features.set(property, layout.metadata[property])
	_features.landmarks.assign(layout.metadata["landmarks"])
	if int(layout.metadata.get("landforms", {}).get("version", 0)) != 2:
		layout.metadata["landforms"] = LandformLayout.generate(_noise, layout.metadata)
		ResourceSaver.save(layout, layout_path)
	_features.landforms = DawnLandforms.new(layout.metadata["landforms"], _noise.radius)
	var nearest_pass: Dictionary = {}
	var nearest_distance: float = INF
	for pass_site: Dictionary in _features.landforms.metadata["passes"]:
		var distance: float = Vector3(pass_site["direction"]).distance_to(_features.site["direction"])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_pass = pass_site
	var tower_direction: Vector3 = SurfaceSites.offset_direction(nearest_pass["direction"], nearest_pass["along"], 900.0, _noise.radius)
	for landmark: Dictionary in _features.landmarks:
		if landmark["kind"] == "peak_tower":
			landmark["point"] = _features.plane(tower_direction)
	layout.metadata["landmarks"] = _features.landmarks
	ResourceSaver.save(layout, layout_path)
	_data = HydrologyData.new()
	_data.metadata = {"site": _features.site, "center": _features.center, "axis_u": _features.axis_u, "axis_v": _features.axis_v, "volcano": _features.volcano, "volcano_base": _features.volcano_base, "landmarks": _features.landmarks}
	_data.metadata["landforms"] = layout.metadata["landforms"]
	print("烘焙：球面格网与基础高度")
	_grid()
	print("烘焙：全球优先填洼")
	_flood()
	print("烘焙：湖泊与汇水面积")
	_lakes()
	for cursor: int in range(_order.size() - 1, -1, -1):
		var cell: int = _order[cursor]
		if _parent[cell] >= 0:
			_areas[_parent[cell]] += _areas[cell]
	print("烘焙：连续河道")
	_rivers()
	_canyon_river()
	_join_levels()
	_mark_falls()
	print("烘焙：空间索引")
	_index()
	_fine_index()
	print("烘焙：文明区")
	_features.hydrology = GlobalHydrology.new(_data, _noise.radius)
	_features.protected_spawn = _features.site["direction"]
	_noise.features = _features
	_data.civilization = CivilizationBake.new().generate(_noise, _data)
	if _data.civilization == null:
		quit(1)
		return
	print("烘焙：烽火塔链")
	_data.civilization.beacons = BeaconBake.new().generate(_noise, _data.civilization)
	if _data.civilization.beacons.is_empty():
		quit(1)
		return
	_features.civilization = CivilizationTerrain.new(_data.civilization, _noise.radius)
	var beacon_path: PackedVector3Array = CivilizationPaths.find(_noise, _data.civilization.town["direction"], _data.civilization.beacons[0]["direction"])
	if beacon_path.is_empty():
		quit(1)
		return
	_data.civilization.roads.append(CivilizationPaths.road(_noise, beacon_path, 2.0, "first_beacon"))
	_features.civilization = CivilizationTerrain.new(_data.civilization, _noise.radius)
	print("烘焙：回声洞选址与神殿道路")
	var cave_started: int = Time.get_ticks_msec()
	var network: Dictionary = CaveBake.fit(_noise, _data.civilization)
	if network.is_empty():
		quit(1)
		return
	CaveBake.complete(_noise, network)
	var caves: CaveData = CaveData.new()
	caves.networks.append(network)
	caves.prepare()
	_features.caves = caves
	var gate: Transform3D = network["frame"]
	var gate_approach: Vector3 = (gate * Vector3(0, 0, -8)).normalized()
	var temple_path: PackedVector3Array = CivilizationPaths.find(_noise, _data.civilization.town["direction"], gate_approach)
	if temple_path.is_empty():
		quit(1)
		return
	_data.civilization.roads.append(CivilizationPaths.road(_noise, temple_path, 2.0, "temple"))
	_data.civilization.town["cave_gate"] = gate.origin
	_features.civilization = CivilizationTerrain.new(_data.civilization, _noise.radius)
	# 新道路和塔基也影响地面；构件在最终高度上重新摆放，避免旧基础悬空。
	_data.civilization.placements.clear()
	_data.civilization.climbs.clear()
	_data.civilization.trees.clear()
	_data.civilization.town["paving_gaps"] = PackedVector3Array()
	CivilizationBuildings.new(_noise, _data.civilization).build()
	print("烘焙：洞穴距离场与分块网格")
	CaveMesher.new().generate(caves, _noise)
	caves.statistics["bake_seconds"] = float(Time.get_ticks_msec() - cave_started) / 1000.0
	caves.signature = CaveData.source_signature()
	var cave_error: Error = ResourceSaver.save(caves, CaveData.PATH, ResourceSaver.FLAG_COMPRESS)
	if cave_error != OK:
		push_error("洞穴资源保存失败。")
		quit(1)
		return
	caves.statistics["bytes"] = FileAccess.get_file_as_bytes(CaveData.PATH).size()
	VerificationMetrics.write_json("res://../test-output/wanderer/cave_bake.json", caves.statistics)
	_data.signature = HydrologyData.source_signature()
	var bake_seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	_data.statistics["grid_cells"] = COUNT
	_data.statistics["river_count"] = _data.river_starts.size() - 1
	_data.statistics["lake_count"] = _data.lake_levels.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var error: Error = ResourceSaver.save(_data, HydrologyData.PATH, ResourceSaver.FLAG_COMPRESS)
	var report: Dictionary = {"error": error, "bake_seconds": bake_seconds, "bytes": FileAccess.get_file_as_bytes(HydrologyData.PATH).size(), "statistics": _data.statistics}
	VerificationMetrics.write_json("res://../test-output/wanderer/bake.json", report)
	print(JSON.stringify(report))
	quit(0 if error == OK else 1)


func _grid() -> void:
	_directions.resize(COUNT)
	_neighbors.resize(COUNT * 8)
	_heights.resize(COUNT)
	_areas.resize(COUNT)
	for cell: int in COUNT:
		var face: int = cell / (SIZE * SIZE)
		var x: int = cell % SIZE
		var y: int = (cell / SIZE) % SIZE
		var u: float = (float(x) + 0.5) * 2.0 / SIZE - 1.0
		var v: float = (float(y) + 0.5) * 2.0 / SIZE - 1.0
		var direction: Vector3 = HydrologyData.corner(face, u, v)
		_directions[cell] = direction
		_heights[cell] = _features.ground_height(direction, _noise.base_height(direction))
		_areas[cell] = 4.0 * _noise.radius * _noise.radius / (SIZE * SIZE * pow(1.0 + u * u + v * v, 1.5))
		for index: int in 8:
			var nx: int = x + OFFSETS[index].x
			var ny: int = y + OFFSETS[index].y
			var neighbor: int = face * SIZE * SIZE + ny * SIZE + nx
			if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE:
				neighbor = HydrologyData.cell_at(HydrologyData.corner(face, (float(nx) + 0.5) * 2.0 / SIZE - 1.0, (float(ny) + 0.5) * 2.0 / SIZE - 1.0))
			_neighbors[cell * 8 + index] = neighbor


func _canyon_river() -> void:
	# 窄谷底可能小于全球格网间距，沿已烘焙的谷底补采样，避免格网漏掉整段河道。
	var forms: DawnLandforms = _features.landforms
	var length: float = 0.0
	var last_level: float = INF
	for segment: int in forms.canyon.size() - 1:
		var distance: float = forms.canyon[segment].angle_to(forms.canyon[segment + 1]) * _noise.radius
		var steps: int = ceili(distance / 15.0)
		for sample: int in steps:
			var direction: Vector3 = forms.canyon[segment].slerp(forms.canyon[segment + 1], sample / float(steps)).normalized()
			var ground: float = _features.ground_height(direction, _noise.base_height(direction))
			last_level = minf(last_level, maxf(-1.0, ground - 0.35))
			_data.river_points.append(direction)
			_data.river_levels.append(last_level)
			_data.river_widths.append(9.0 + 7.0 * length / forms.canyon_lengths[-1])
			_data.river_flags.append(2)
			length += distance / steps
	_data.river_points.append(forms.canyon[-1])
	_data.river_levels.append(-1.0)
	_data.river_widths.append(16.0)
	_data.river_flags.append(2)
	_data.river_starts.append(_data.river_points.size())
	_data.river_ends.append(HydrologyData.cell_at(forms.canyon[-1]))
	_data.river_joins.append(-1)
	_data.statistics["river_km"] = float(_data.statistics["river_km"]) + length / 1000.0
	_data.statistics["canyon_km"] = float(_data.statistics["canyon_km"]) + length / 1000.0


func _flood() -> void:
	_filled = _heights.duplicate()
	_parent.resize(COUNT)
	_parent.fill(-1)
	var closed: PackedByteArray = []
	closed.resize(COUNT)
	var pit: PackedInt32Array = []
	var head: int = 0
	for cell: int in COUNT:
		if _heights[cell] < 0.0:
			pit.append(cell)
			closed[cell] = 1
	while head < pit.size() or not _heap_values.is_empty():
		var cell: int
		if head < pit.size():
			cell = pit[head]
			head += 1
		else:
			cell = _heap_pop(_heap_keys, _heap_values)
		_order.append(cell)
		for index: int in 8:
			var next: int = _neighbors[cell * 8 + index]
			if closed[next] != 0:
				continue
			closed[next] = 1
			_parent[next] = cell
			if _heights[next] <= maxf(0.0, _filled[cell]):
				_filled[next] = maxf(0.0, _filled[cell])
				pit.append(next)
			else:
				_heap_push(_heap_keys, _heap_values, _heights[next], next)


func _lakes() -> void:
	_lake_ids.resize(COUNT)
	_lake_ids.fill(-1)
	var seen: PackedByteArray = []
	seen.resize(COUNT)
	_data.lake_starts.append(0)
	var total_area: float = 0.0
	for start: int in COUNT:
		if seen[start] != 0 or _heights[start] < 0.0 or _filled[start] - _heights[start] < 0.7:
			continue
		var level: float = _filled[start]
		var cells: PackedInt32Array = [start]
		var cursor: int = 0
		var area: float = 0.0
		var depth: float = 0.0
		seen[start] = 1
		while cursor < cells.size():
			var cell: int = cells[cursor]
			cursor += 1
			area += _areas[cell]
			depth = maxf(depth, level - _heights[cell])
			for index: int in [1, 3, 4, 6]:
				var next: int = _neighbors[cell * 8 + index]
				if seen[next] == 0 and _heights[next] >= 0.0 and absf(_filled[next] - level) < 0.01 and level - _heights[next] > 0.7:
					seen[next] = 1
					cells.append(next)
		if area < HydrologyData.LAKE_AREA or depth < HydrologyData.LAKE_DEPTH:
			continue
		for cell: int in cells:
			_lake_ids[cell] = _data.lake_levels.size()
		_data.lake_levels.append(level - 0.6)
		_data.lake_cells.append_array(cells)
		_data.lake_starts.append(_data.lake_cells.size())
		total_area += area
	_data.statistics["lake_area_km2"] = total_area / 1e6


func _rivers() -> void:
	var active: PackedByteArray = []
	active.resize(COUNT)
	var upstream: PackedByteArray = []
	upstream.resize(COUNT)
	var claimed: PackedByteArray = []
	claimed.resize(COUNT)
	for cell: int in COUNT:
		if _areas[cell] >= HydrologyData.RIVER_AREA and _heights[cell] >= 0.0:
			active[cell] = 1
			if _parent[cell] >= 0:
				upstream[_parent[cell]] = 1
	_data.river_starts.append(0)
	for source: int in COUNT:
		if active[source] == 0 or upstream[source] != 0:
			continue
		var chain: PackedInt32Array = []
		var cell: int = source
		while cell >= 0:
			chain.append(cell)
			if claimed[cell] != 0 or _heights[cell] < 0.0:
				_add_river(chain)
				break
			claimed[cell] = 1
			if _lake_ids[cell] >= 0:
				_add_river(chain)
				var outlet: int = cell
				while cell >= 0 and _lake_ids[cell] >= 0:
					outlet = cell
					claimed[cell] = 1
					cell = _parent[cell]
				chain = PackedInt32Array([outlet])
				continue
			cell = _parent[cell]
		if cell < 0:
			_add_river(chain)


func _add_river(chain: PackedInt32Array) -> void:
	if chain.size() < 2:
		return
	var first_point: int = _data.river_points.size()
	var points: PackedVector3Array = []
	var widths: PackedFloat32Array = []
	for cell: int in chain:
		points.append(_directions[cell])
		widths.append(clampf(3.0 + 2.2 * sqrt(_areas[cell] / 1e6), 3.5, 28.0))
	for iteration: int in 2:
		var smooth_points: PackedVector3Array = [points[0]]
		var smooth_widths: PackedFloat32Array = [widths[0]]
		for index: int in points.size() - 1:
			for weight: float in [0.25, 0.75]:
				smooth_points.append(points[index].slerp(points[index + 1], weight).normalized())
				smooth_widths.append(lerpf(widths[index], widths[index + 1], weight))
		smooth_points.append(points[-1])
		smooth_widths.append(widths[-1])
		points = smooth_points
		widths = smooth_widths
	var last_level: float = INF
	var travelled: float = 0.0
	var waterfall_count: int = int(_data.statistics.get("waterfalls", 0))
	var canyon_length: float = float(_data.statistics.get("canyon_km", 0.0))
	for index: int in points.size() - 1:
		var length: float = points[index].distance_to(points[index + 1]) * _noise.radius
		var steps: int = maxi(1, ceili(length / 15.0))
		for step: int in steps:
			var weight: float = float(step) / steps
			var direction: Vector3 = points[index].slerp(points[index + 1], weight).normalized()
			var width: float = lerpf(widths[index], widths[index + 1], weight)
			# 两端保持连接；蜿蜒在河段内部平滑归零，不移动汇合口。
			var tangent: Vector3 = points[index].cross(points[index + 1]).normalized()
			var phase: float = float(_data.river_starts.size()) * 1.37
			var fade: float = sin(PI * (index + weight) / (points.size() - 1))
			direction = (direction * _noise.radius + tangent * clampf(width * 1.5, 3.0, 25.0) * sin(travelled / 130.0 + phase) * fade).normalized()
			var ground: float = _features.ground_height(direction, _noise.base_height(direction))
			var level: float = minf(last_level, maxf(ground - 0.35, -1.0))
			var flags: int = 0
			if last_level < INF and last_level - level > 6.0 and (last_level - level) / maxf(length / steps, 0.01) > 0.35:
				flags |= 1
				waterfall_count += 1
			if ground > 250.0 and width > 14.0:
				flags |= 2
				canyon_length += length / steps / 1000.0
			_data.river_points.append(direction)
			_data.river_levels.append(level)
			_data.river_widths.append(width)
			_data.river_flags.append(flags)
			last_level = level
			travelled += length / steps
	var end: int = chain[-1]
	var final_level: float = minf(last_level, _data.lake_levels[_lake_ids[end]] if _lake_ids[end] >= 0 else maxf(_heights[end] - 0.35, -1.0))
	var join: int = int(_junctions.get(end, -1))
	_data.river_points.append(_data.river_points[join] if join >= 0 else points[-1])
	_data.river_levels.append(final_level)
	_data.river_widths.append(widths[-1])
	_data.river_flags.append(0)
	_data.river_starts.append(_data.river_points.size())
	_data.river_ends.append(end)
	_data.river_joins.append(join)
	# 保存原始格点在平滑河道上的实际位置，支流必须接到这条曲线上。
	var cursor: int = first_point
	for cell: int in chain:
		if _junctions.has(cell):
			continue
		var minimum: float = INF
		var best: int = cursor
		for candidate: int in range(maxi(first_point, cursor - 12), mini(cursor + 80, _data.river_points.size())):
			var distance: float = _directions[cell].distance_squared_to(_data.river_points[candidate])
			if distance < minimum:
				minimum = distance
				best = candidate
		_junctions[cell] = best
		cursor = best
	_data.statistics["river_km"] = float(_data.statistics.get("river_km", 0.0)) + travelled / 1000.0
	_data.statistics["waterfalls"] = waterfall_count
	_data.statistics["canyon_km"] = canyon_length


func _join_levels() -> void:
	# 连接点共享水位，并沿有向水系向下传播；不抬高任何已有水位。
	for iteration: int in 64:
		var changed: bool = false
		for river: int in _data.river_joins.size():
			var start: int = _data.river_starts[river]
			var end: int = _data.river_starts[river + 1] - 1
			var join: int = _data.river_joins[river]
			if join >= 0:
				var level: float = minf(_data.river_levels[join], _data.river_levels[end])
				if _data.river_levels[join] != level or _data.river_levels[end] != level:
					changed = true
				_data.river_levels[join] = level
				_data.river_levels[end] = level
			for index: int in range(start + 1, end + 1):
				if _data.river_levels[index] > _data.river_levels[index - 1]:
					_data.river_levels[index] = _data.river_levels[index - 1]
					changed = true
		if not changed:
			return
	push_error("水系连接水位未能收敛。")


func _mark_falls() -> void:
	var count: int = 0
	for river: int in _data.river_starts.size() - 1:
		for index: int in range(_data.river_starts[river], _data.river_starts[river + 1] - 1):
			_data.river_flags[index] &= 2
			var distance: float = _data.river_points[index].distance_to(_data.river_points[index + 1]) * _noise.radius
			var drop: float = _data.river_levels[index] - _data.river_levels[index + 1]
			if drop > 6.0 and drop / maxf(distance, 0.01) > 0.35:
				_data.river_flags[index] |= 1
				count += 1
	_data.statistics["waterfalls"] = count


func _index() -> void:
	var buckets: Dictionary = {}
	for river: int in _data.river_starts.size() - 1:
		for index: int in range(_data.river_starts[river], _data.river_starts[river + 1] - 1):
			var direction: Vector3 = (_data.river_points[index] + _data.river_points[index + 1]).normalized()
			var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
			var right: Vector3 = tangent.cross(direction)
			var reach: float = maxf(_data.river_widths[index], _data.river_widths[index + 1]) * 4.5 + 80.0
			var touched: Dictionary = {}
			for x: float in [-1.0, 0.0, 1.0]:
				for y: float in [-1.0, 0.0, 1.0]:
					var sample: Vector3 = direction * _noise.radius + (tangent * x + right * y) * reach
					touched[HydrologyData.cell_at(sample.normalized(), HydrologyData.BUCKET_GRID)] = true
			for bucket: int in touched:
				if not buckets.has(bucket):
					buckets[bucket] = PackedInt32Array()
				var list: PackedInt32Array = buckets[bucket]
				list.append(index)
				buckets[bucket] = list
	for bucket: int in 6 * HydrologyData.BUCKET_GRID * HydrologyData.BUCKET_GRID:
		_data.bucket_offsets.append(_data.bucket_segments.size())
		if buckets.has(bucket):
			_data.bucket_segments.append_array(buckets[bucket])
	_data.bucket_offsets.append(_data.bucket_segments.size())


static func _heap_push(keys: PackedFloat32Array, values: PackedInt32Array, key: float, value: int) -> void:
	keys.append(key)
	values.append(value)
	var child: int = keys.size() - 1
	while child > 0:
		var parent: int = (child - 1) >> 1
		if keys[parent] <= key:
			break
		keys[child] = keys[parent]
		values[child] = values[parent]
		child = parent
	keys[child] = key
	values[child] = value


func _fine_index() -> void:
	var buckets: Dictionary = {}
	for river: int in _data.river_starts.size() - 1:
		for index: int in range(_data.river_starts[river], _data.river_starts[river + 1] - 1):
			var direction: Vector3 = (_data.river_points[index] + _data.river_points[index + 1]).normalized()
			var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
			var right: Vector3 = tangent.cross(direction)
			var reach: float = maxf(_data.river_widths[index], _data.river_widths[index + 1]) * 5.0 + 90.0
			var touched: Dictionary = {}
			for x: int in range(-2, 3):
				for y: int in range(-2, 3):
					var sample: Vector3 = direction * _noise.radius + (tangent * x + right * y) * reach * 0.5
					touched[HydrologyData.cell_at(sample.normalized(), HydrologyData.CARVE_GRID)] = true
			for bucket: int in touched:
				if not buckets.has(bucket):
					buckets[bucket] = PackedInt32Array()
				var list: PackedInt32Array = buckets[bucket]
				list.append(index)
				buckets[bucket] = list
	for bucket: int in 6 * HydrologyData.CARVE_GRID * HydrologyData.CARVE_GRID:
		_data.carve_offsets.append(_data.carve_segments.size())
		if buckets.has(bucket):
			_data.carve_segments.append_array(buckets[bucket])
	_data.carve_offsets.append(_data.carve_segments.size())


static func _heap_pop(keys: PackedFloat32Array, values: PackedInt32Array) -> int:
	var top: int = values[0]
	var last_key: float = keys[keys.size() - 1]
	var last_value: int = values[values.size() - 1]
	keys.resize(keys.size() - 1)
	values.resize(values.size() - 1)
	var size: int = keys.size()
	if size == 0:
		return top
	var index: int = 0
	while true:
		var child: int = index * 2 + 1
		if child >= size:
			break
		if child + 1 < size and keys[child + 1] < keys[child]:
			child += 1
		if keys[child] >= last_key:
			break
		keys[index] = keys[child]
		values[index] = values[child]
		index = child
	keys[index] = last_key
	values[index] = last_value
	return top
