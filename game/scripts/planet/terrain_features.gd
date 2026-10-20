class_name TerrainFeatures
extends RefCounted

# 晨样板区的地形特征：火山、河流与湖泊。只作用于出生点周围的方形区域，
# 由 TerrainNoise.height() 叠加在基础地形上；建好后只读，后台线程可以同时查询。

const HALF_SIZE: float = 9000.0
const CELL: float = 60.0
const BUCKET: float = 150.0
# 上游汇水面积超过此值的格子成为河道，单位平方米。
const RIVER_AREA: float = 2.2e6
const LAKE_MIN_CELLS: int = 40
const LAKE_MIN_DEPTH: float = 4.0

static var _cache: Dictionary = {}
static var _cache_mutex: Mutex = Mutex.new()

var radius: float
# 用基础地形找到的出发地；地形特征以它为中心，出发地本身不会因特征而改变位置。
var site: Dictionary
var center: Vector3
var axis_u: Vector3
var axis_v: Vector3
var volcano: Vector2 = Vector2.INF
var volcano_height: float = 760.0
var volcano_radius: float = 2000.0
var crater_radius: float = 280.0
var crater_depth: float = 115.0
# 火山中心处的基础地形高度；山体建在这个高度上，不随周围丘陵起伏而破口。
var volcano_base: float = 0.0
# 每条河是一串平面坐标点，附带每点的水位和半宽。
var rivers: Array[Dictionary] = []
# 每个湖记录水位和所含格子的编号。
var lakes: Array[Dictionary] = []
# 远处可见的地标：种类、平面坐标、朝向和周围不长植被的半径。
var landmarks: Array[Dictionary] = []
var _size: int = 0
var _cos_reach: float = 1.0
var _seg_a: PackedVector2Array = []
var _seg_b: PackedVector2Array = []
var _seg_level: PackedVector2Array = []
var _seg_width: PackedVector2Array = []
var _buckets: Dictionary = {}
var _lake_level: PackedFloat32Array = []


# 同一颗星球的特征只计算一次；地图和检查脚本各自新建的噪声对象共享同一份结果。
static func for_noise(noise: TerrainNoise) -> TerrainFeatures:
	var key: String = "%d/%.1f" % [noise.planet_seed, noise.radius]
	_cache_mutex.lock()
	var features: TerrainFeatures = _cache.get(key) as TerrainFeatures
	if features == null:
		features = TerrainFeatures.new()
		features._build(noise)
		_cache[key] = features
	_cache_mutex.unlock()
	return features


func plane(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(axis_u), direction.dot(axis_v)) * radius


func direction_at(point: Vector2) -> Vector3:
	var lateral: Vector3 = (axis_u * point.x + axis_v * point.y) / radius
	return (lateral + center * sqrt(maxf(1.0 - lateral.length_squared(), 0.0))).normalized()


func contains(direction: Vector3) -> bool:
	if direction.dot(center) < _cos_reach:
		return false
	var point: Vector2 = plane(direction)
	return absf(point.x) <= HALF_SIZE and absf(point.y) <= HALF_SIZE


# 基础地形加上火山与河道；河道在火山之后计算，所以火山口里的湖和流下山的河彼此一致。
func apply(direction: Vector3, base: float) -> float:
	if not contains(direction):
		return base
	var point: Vector2 = plane(direction)
	return _carve(point, with_volcano(point, base))


func with_volcano(point: Vector2, base: float) -> float:
	if volcano == Vector2.INF:
		return base
	var offset: Vector2 = point - volcano
	var distance: float = offset.length()
	if distance >= volcano_radius:
		return base
	# 山脚以内逐渐把地面压到火山中心的高度，山体和火山口都建在这个平面上。
	var ground: float = lerpf(base, volcano_base, smoothstep(volcano_radius, volcano_radius * 0.45, distance))
	if distance < crater_radius:
		# 火山口是一个碗形洼地，边缘保留一道略高的口沿。
		var bowl: float = 1.0 - pow(distance / crater_radius, 2.0)
		return ground + volcano_height - crater_depth * bowl + 6.0 * smoothstep(0.7, 1.0, distance / crater_radius)
	var slope: float = (volcano_radius - distance) / (volcano_radius - crater_radius)
	var cone: float = volcano_height * pow(slope, 1.45) + 6.0 * smoothstep(0.85, 1.0, slope)
	# 山腰的放射状冲沟，越靠山顶越明显，避免锥体像一个光滑的圆锥。
	var angle: float = atan2(offset.y, offset.x)
	var gully: float = 0.5 + 0.5 * sin(angle * 13.0 + sin(angle * 5.0) * 2.2)
	return ground + cone * (1.0 - 0.035 * gully * slope)


# 返回该方向上河面或湖面的水位；不在水里时返回负无穷。
func water_surface(direction: Vector3) -> float:
	if not contains(direction):
		return -INF
	var point: Vector2 = plane(direction)
	var nearest: Vector4 = _nearest_segment(point)
	if nearest.w >= 0.0 and nearest.x < nearest.z * 1.05:
		return nearest.y
	return _lake_level[_cell_index(point)]


func water_body(direction: Vector3) -> String:
	if not contains(direction):
		return ""
	var point: Vector2 = plane(direction)
	var nearest: Vector4 = _nearest_segment(point)
	if nearest.w >= 0.0 and nearest.x < nearest.z * 1.05:
		return "河流"
	if _lake_level[_cell_index(point)] > -INF:
		return "湖泊"
	return ""


# 到最近河道中心线的距离（米）；没有河道时返回正无穷。
func river_distance(direction: Vector3) -> float:
	if not contains(direction):
		return INF
	var nearest: Vector4 = _nearest_segment(plane(direction))
	return nearest.x - nearest.z if nearest.w >= 0.0 else INF


# 地标周围留出空地，植被不会长进石柱、塔身或巨环里。
func in_clearing(direction: Vector3) -> bool:
	if landmarks.is_empty() or not contains(direction):
		return false
	var point: Vector2 = plane(direction)
	for landmark: Dictionary in landmarks:
		if point.distance_to(landmark["point"]) < landmark["clearance"]:
			return true
	return false


func height_at(noise: TerrainNoise, point: Vector2) -> float:
	var direction: Vector3 = direction_at(point)
	return apply(direction, noise.base_height(direction))


func _cell_index(point: Vector2) -> int:
	var column: int = clampi(floori((point.x + HALF_SIZE) / CELL), 0, _size - 1)
	var row: int = clampi(floori((point.y + HALF_SIZE) / CELL), 0, _size - 1)
	return row * _size + column


func grid_size() -> int:
	return _size


func cell_center(index: int) -> Vector2:
	return Vector2(-HALF_SIZE + (float(index % _size) + 0.5) * CELL, -HALF_SIZE + (float(index / _size) + 0.5) * CELL)


# 返回最近河段的距离、该处水位、半宽和河段编号；附近没有河段时编号为 -1。
func _nearest_segment(point: Vector2) -> Vector4:
	var key: Vector2i = Vector2i(floori(point.x / BUCKET), floori(point.y / BUCKET))
	var result: Vector4 = Vector4(INF, 0.0, 0.0, -1.0)
	if not _buckets.has(key):
		return result
	for segment: int in _buckets[key] as PackedInt32Array:
		var a: Vector2 = _seg_a[segment]
		var b: Vector2 = _seg_b[segment]
		var along: Vector2 = b - a
		var t: float = clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
		var distance: float = point.distance_to(a + along * t)
		if distance < result.x:
			var levels: Vector2 = _seg_level[segment]
			var widths: Vector2 = _seg_width[segment]
			result = Vector4(distance, lerpf(levels.x, levels.y, t), lerpf(widths.x, widths.y, t), float(segment))
	return result


func _carve(point: Vector2, height: float) -> float:
	var nearest: Vector4 = _nearest_segment(point)
	if nearest.w < 0.0:
		return height
	var distance: float = nearest.x
	var level: float = nearest.y
	var half_width: float = nearest.z
	var bank: float = half_width * 2.5 + 25.0
	if distance >= half_width + bank:
		return height
	if distance < half_width:
		# 河床为抛物线断面，深度随河宽增加；河道内既下切也填平，保证水面不会悬空。
		var depth: float = 0.8 + half_width * 0.12
		return level - depth * (1.0 - pow(distance / half_width, 2.0))
	# 河岸先缓后陡地升起；岸边比水面略高，远处逐渐回到原地形。
	var shaped: float = minf(maxf(height, level + 0.15), level + 0.2 + (distance - half_width) * 0.35)
	var blend: float = 1.0 - smoothstep(half_width, half_width + bank, distance)
	return lerpf(height, shaped, blend)


func _build(noise: TerrainNoise) -> void:
	radius = noise.radius
	site = SurfaceSites.find(noise)
	if site.is_empty():
		return
	center = site["direction"]
	axis_u = site["forward"]
	axis_v = center.cross(axis_u).normalized()
	_cos_reach = cos(HALF_SIZE * sqrt(2.0) / radius + 0.01)
	_size = int(HALF_SIZE * 2.0 / CELL)
	_place_volcano(noise)
	var count: int = _size * _size
	var heights: PackedFloat32Array = []
	heights.resize(count)
	for index: int in count:
		var point: Vector2 = cell_center(index)
		heights[index] = with_volcano(point, noise.base_height(direction_at(point)))
	var flood: Dictionary = _flood(heights)
	_extract_lakes(heights, flood["filled"])
	_extract_rivers(noise, heights, flood)
	_place_landmarks(noise)


func _place_volcano(noise: TerrainNoise) -> void:
	# 在出发地四周 3.5～6.5 公里处找一块陆地放火山；避开远山方向，不挡住出发地的主要视野。
	for distance: float in [5200.0, 4200.0, 6200.0, 3500.0]:
		for step: int in 16:
			var angle: float = PI * 0.5 + float(step) * TAU / 16.0
			if absf(angle_difference(angle, 0.0)) < deg_to_rad(60.0):
				continue
			var candidate: Vector2 = Vector2.from_angle(angle) * distance
			var base: float = noise.base_height(direction_at(candidate))
			if base < 10.0 or base > 600.0:
				continue
			var land: int = 0
			for ring: int in 8:
				var around: Vector2 = candidate + Vector2.from_angle(float(ring) * TAU / 8.0) * 1600.0
				if noise.base_height(direction_at(around)) > 0.0:
					land += 1
			if land >= 5:
				volcano = candidate
				volcano_base = base
				return


func _flood(heights: PackedFloat32Array) -> Dictionary:
	# 改进的优先填洼：从海和区域边界出发，按高度由低到高向内扩展，
	# 得到每格的填洼高度和下游方向。洼地内的格子走先进先出队列，减少堆操作。
	var count: int = heights.size()
	var filled: PackedFloat32Array = heights.duplicate()
	var parent: PackedInt32Array = []
	parent.resize(count)
	parent.fill(-1)
	var closed: PackedByteArray = []
	closed.resize(count)
	var ocean: PackedByteArray = []
	ocean.resize(count)
	var order: PackedInt32Array = []
	var heap_keys: PackedFloat32Array = []
	var heap_values: PackedInt32Array = []
	var pit: PackedInt32Array = []
	var pit_head: int = 0
	for index: int in count:
		var row: int = index / _size
		var column: int = index % _size
		if heights[index] < 0.0 or row == 0 or column == 0 or row == _size - 1 or column == _size - 1:
			closed[index] = 1
			ocean[index] = 1 if heights[index] < 0.0 else 0
			_heap_push(heap_keys, heap_values, heights[index], index)
	var offsets: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	while pit_head < pit.size() or not heap_values.is_empty():
		var current: int
		if pit_head < pit.size():
			current = pit[pit_head]
			pit_head += 1
		else:
			current = _heap_pop(heap_keys, heap_values)
		order.append(current)
		var row: int = current / _size
		var column: int = current % _size
		for offset: Vector2i in offsets:
			var next_row: int = row + offset.y
			var next_column: int = column + offset.x
			if next_row < 0 or next_column < 0 or next_row >= _size or next_column >= _size:
				continue
			var next: int = next_row * _size + next_column
			if closed[next] == 1:
				continue
			closed[next] = 1
			parent[next] = current
			ocean[next] = ocean[current]
			if heights[next] <= filled[current]:
				filled[next] = filled[current]
				pit.append(next)
			else:
				_heap_push(heap_keys, heap_values, heights[next], next)
	return {"filled": filled, "parent": parent, "order": order, "ocean": ocean}


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


func _extract_lakes(heights: PackedFloat32Array, filled: PackedFloat32Array) -> void:
	var count: int = heights.size()
	_lake_level.resize(count)
	_lake_level.fill(-INF)
	var visited: PackedByteArray = []
	visited.resize(count)
	for start: int in count:
		if visited[start] == 1 or heights[start] < 0.0 or filled[start] - heights[start] < 0.3:
			continue
		# 同一洼地的填洼高度相同，按相同水位连通的格子归为一个湖。
		var level: float = filled[start]
		var cells: PackedInt32Array = [start]
		visited[start] = 1
		var cursor: int = 0
		var deepest: float = 0.0
		while cursor < cells.size():
			var current: int = cells[cursor]
			cursor += 1
			deepest = maxf(deepest, level - heights[current])
			var row: int = current / _size
			var column: int = current % _size
			for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var next_row: int = row + offset.y
				var next_column: int = column + offset.x
				if next_row < 0 or next_column < 0 or next_row >= _size or next_column >= _size:
					continue
				var next: int = next_row * _size + next_column
				if visited[next] == 1 or heights[next] < 0.0 or absf(filled[next] - level) > 0.01 or filled[next] - heights[next] < 0.3:
					continue
				visited[next] = 1
				cells.append(next)
		if cells.size() < LAKE_MIN_CELLS or deepest < LAKE_MIN_DEPTH:
			continue
		# 水位略低于溢出口，格网之间的低鞍部不至于让湖面越过湖岸。
		var surface: float = level - 0.6
		for cell: int in cells:
			_lake_level[cell] = surface
		lakes.append({"level": surface, "cells": cells})


func _extract_rivers(noise: TerrainNoise, heights: PackedFloat32Array, flood: Dictionary) -> void:
	var filled: PackedFloat32Array = flood["filled"]
	var parent: PackedInt32Array = flood["parent"]
	var order: PackedInt32Array = flood["order"]
	var ocean: PackedByteArray = flood["ocean"]
	var count: int = heights.size()
	var area: PackedFloat32Array = []
	area.resize(count)
	area.fill(CELL * CELL)
	for position: int in range(order.size() - 1, -1, -1):
		var cell: int = order[position]
		if parent[cell] >= 0:
			area[parent[cell]] += area[cell]
	# 只保留最终流入大海的河；流出区域边界的水系在这里没有完整的下游，不画。
	var is_river: PackedByteArray = []
	is_river.resize(count)
	var has_upstream: PackedByteArray = []
	has_upstream.resize(count)
	for cell: int in count:
		if area[cell] >= RIVER_AREA and heights[cell] >= 0.0 and ocean[cell] == 1:
			is_river[cell] = 1
	for cell: int in count:
		if is_river[cell] == 1 and parent[cell] >= 0:
			has_upstream[parent[cell]] = 1
	var claimed: PackedByteArray = []
	claimed.resize(count)
	# 从汇水面积最大的源头开始描，主干先成形，支流在汇合处结束。
	var sources: Array[int] = []
	for cell: int in count:
		if is_river[cell] == 1 and has_upstream[cell] == 0:
			sources.append(cell)
	sources.sort_custom(func(a: int, b: int) -> bool: return _downstream_area(a, parent, area, is_river) > _downstream_area(b, parent, area, is_river))
	for source: int in sources:
		var chain: PackedInt32Array = []
		var cell: int = source
		while cell >= 0:
			chain.append(cell)
			if claimed[cell] == 1 or heights[cell] < 0.0:
				break
			claimed[cell] = 1
			if _lake_level[cell] > -INF:
				# 进入湖泊：本段到湖边为止，出湖后从湖的出口重新开始。
				_add_river(noise, chain, filled, area, heights)
				var outlet: int = cell
				while cell >= 0 and _lake_level[cell] > -INF:
					claimed[cell] = 1
					outlet = cell
					cell = parent[cell]
				chain = PackedInt32Array([outlet])
				continue
			cell = parent[cell]
		_add_river(noise, chain, filled, area, heights)
	_index_segments()


func _downstream_area(cell: int, parent: PackedInt32Array, area: PackedFloat32Array, is_river: PackedByteArray) -> float:
	var current: int = cell
	var steps: int = 0
	while parent[current] >= 0 and is_river[parent[current]] == 1 and steps < 40:
		current = parent[current]
		steps += 1
	return area[current] + float(steps)


func _add_river(noise: TerrainNoise, chain: PackedInt32Array, filled: PackedFloat32Array, area: PackedFloat32Array, heights: PackedFloat32Array) -> void:
	if chain.size() < 3:
		return
	var points: PackedVector2Array = []
	var levels: PackedFloat32Array = []
	var widths: PackedFloat32Array = []
	for cell: int in chain:
		points.append(cell_center(cell))
		levels.append(filled[cell] if heights[cell] >= 0.0 else -1.0)
		widths.append(clampf(3.0 + 2.2 * sqrt(area[cell] / 1.0e6), 3.5, 16.0))
	# 八方向格网路径呈锯齿状，两次切角平滑成自然的弯道。
	for iteration: int in 2:
		var smooth_points: PackedVector2Array = [points[0]]
		var smooth_levels: PackedFloat32Array = [levels[0]]
		var smooth_widths: PackedFloat32Array = [widths[0]]
		for index: int in points.size() - 1:
			for weight: float in [0.25, 0.75]:
				smooth_points.append(points[index].lerp(points[index + 1], weight))
				smooth_levels.append(lerpf(levels[index], levels[index + 1], weight))
				smooth_widths.append(lerpf(widths[index], widths[index + 1], weight))
		smooth_points.append(points[points.size() - 1])
		smooth_levels.append(levels[levels.size() - 1])
		smooth_widths.append(widths[widths.size() - 1])
		points = smooth_points
		levels = smooth_levels
		widths = smooth_widths
	# 水位不高于实际地面，并且沿流向只降不升，河面始终落在河道里。
	for index: int in points.size():
		var ground: float = with_volcano(points[index], noise.base_height(direction_at(points[index])))
		levels[index] = maxf(minf(levels[index], ground - 0.35), -1.0)
		if index > 0:
			levels[index] = minf(levels[index], levels[index - 1])
	rivers.append({"points": points, "levels": levels, "widths": widths})


func _index_segments() -> void:
	for river: Dictionary in rivers:
		var points: PackedVector2Array = river["points"]
		var levels: PackedFloat32Array = river["levels"]
		var widths: PackedFloat32Array = river["widths"]
		for index: int in points.size() - 1:
			var segment: int = _seg_a.size()
			_seg_a.append(points[index])
			_seg_b.append(points[index + 1])
			_seg_level.append(Vector2(levels[index], levels[index + 1]))
			_seg_width.append(Vector2(widths[index], widths[index + 1]))
			var reach: float = maxf(widths[index], widths[index + 1]) * 3.5 + 25.0
			var low: Vector2 = Vector2(minf(points[index].x, points[index + 1].x), minf(points[index].y, points[index + 1].y)) - Vector2.ONE * reach
			var high: Vector2 = Vector2(maxf(points[index].x, points[index + 1].x), maxf(points[index].y, points[index + 1].y)) + Vector2.ONE * reach
			for bucket_y: int in range(floori(low.y / BUCKET), floori(high.y / BUCKET) + 1):
				for bucket_x: int in range(floori(low.x / BUCKET), floori(high.x / BUCKET) + 1):
					var key: Vector2i = Vector2i(bucket_x, bucket_y)
					if not _buckets.has(key):
						_buckets[key] = PackedInt32Array()
					var list: PackedInt32Array = _buckets[key]
					list.append(segment)
					_buckets[key] = list


func _place_landmarks(noise: TerrainNoise) -> void:
	var shore: Vector2 = plane(site["shore_direction"])
	var seaward: Vector2 = Vector2(Vector3(site["shore_forward"]).dot(axis_u), Vector3(site["shore_forward"]).dot(axis_v)).normalized()
	var along_coast: Vector2 = Vector2(-seaward.y, seaward.x)
	# 出发地前方海面上的三根海蚀柱和一座海蚀拱门，从出发地就能看见。
	var stacks: Array[Vector3] = [Vector3(90.0, -40.0, 24.0), Vector3(150.0, 35.0, 34.0), Vector3(240.0, -10.0, 16.0)]
	for index: int in stacks.size():
		var offset: Vector3 = stacks[index]
		var point: Vector2 = shore + seaward * offset.x + along_coast * offset.y
		if height_at(noise, point) < -2.0:
			landmarks.append({"kind": "sea_stack", "point": point, "height": offset.z, "radius": 4.0 + offset.z * 0.12, "clearance": 0.0, "facing": float(index) * 1.3})
	var arch_point: Vector2 = shore + seaward * 190.0 + along_coast * 140.0
	if height_at(noise, arch_point) < -2.0:
		landmarks.append({"kind": "sea_arch", "point": arch_point, "height": 22.0, "radius": 30.0, "clearance": 0.0, "facing": seaward.angle()})
	# 沿海岸找一处临海的高坡放灯塔残骸。
	var lighthouse: Vector2 = _find_spot(noise, shore, 500.0, 1300.0, func(point: Vector2, ground: float) -> bool:
		if ground < 8.0 or ground > 60.0 or water_surface(direction_at(point)) > -INF:
			return false
		for step: int in 8:
			if height_at(noise, point + Vector2.from_angle(float(step) * TAU / 8.0) * 70.0) < -1.0:
				return true
		return false)
	if lighthouse != Vector2.INF:
		landmarks.append({"kind": "lighthouse", "point": lighthouse, "height": 16.0, "radius": 3.4, "clearance": 9.0, "facing": seaward.angle()})
	# 远山顶上的石塔：在山峰附近找最高点。
	var peak: Vector2 = plane(site["mountain_direction"])
	var best: float = height_at(noise, peak)
	for ring: int in range(1, 5):
		for step: int in 12:
			var candidate: Vector2 = plane(site["mountain_direction"]) + Vector2.from_angle(float(step) * TAU / 12.0) * ring * 90.0
			var ground: float = height_at(noise, candidate)
			if ground > best:
				best = ground
				peak = candidate
	landmarks.append({"kind": "peak_tower", "point": peak, "height": 34.0, "radius": 3.6, "clearance": 10.0, "facing": 0.3})
	# 内陆草地上半埋着一个倒下的巨大石环。
	var ring_point: Vector2 = _find_spot(noise, Vector2.ZERO, 1100.0, 2200.0, func(point: Vector2, ground: float) -> bool:
		return ground > 25.0 and ground < 400.0 and noise.slope(direction_at(point), ground) < 0.08 and river_distance(direction_at(point)) > 120.0 and _lake_level[_cell_index(point)] == -INF)
	if ring_point != Vector2.INF:
		# 环面正对出发地，从出发地方向望去是一个完整的圆圈。
		landmarks.append({"kind": "fallen_ring", "point": ring_point, "height": 0.0, "radius": 15.0, "clearance": 19.0, "facing": (-ring_point).angle()})


func _find_spot(noise: TerrainNoise, origin: Vector2, near: float, far: float, accept: Callable) -> Vector2:
	for distance: float in [near, (near + far) * 0.5, far]:
		for step: int in 24:
			var point: Vector2 = origin + Vector2.from_angle(float(step) * TAU / 24.0 + 0.4) * distance
			if absf(point.x) > HALF_SIZE - 200.0 or absf(point.y) > HALF_SIZE - 200.0:
				continue
			if accept.call(point, height_at(noise, point)):
				return point
	return Vector2.INF
