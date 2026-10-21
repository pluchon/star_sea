class_name BeaconBake
extends RefCounted

const GRID: float = 250.0 # 离线候选采样间距，米。
const MIN_SPACING: float = 2000.0 # 相邻烽火塔最小距离，米。
const MAX_SPACING: float = 6000.0 # 通视困难时允许的最大距离，米。
const TOP: float = 20.0 # 通视使用火盆所在高度，米。
var _noise: TerrainNoise
var _candidates: Array[Dictionary] = []
var _visibility: Dictionary = {}


func generate(noise: TerrainNoise, data: CivilizationData) -> Array[Dictionary]:
	_noise = noise
	var town: Vector3 = data.town["direction"]
	var ladder: Vector3 = data.ladder["direction"]
	var old_peak: Vector3
	for landmark: Dictionary in noise.features.landmarks:
		if landmark["kind"] == "peak_tower":
			old_peak = noise.features.direction_at(landmark["point"])
	var forward: Vector3 = SurfaceSites.tangent_forward(town)
	var side: Vector3 = forward.cross(town).normalized()
	var peak_plane: Vector2 = _plane(old_peak, town, forward, side)
	var ladder_plane: Vector2 = _plane(ladder, town, forward, side)
	var minimum: Vector2 = Vector2.ZERO.min(peak_plane).min(ladder_plane) - Vector2.ONE * 5000.0
	var maximum: Vector2 = Vector2.ZERO.max(peak_plane).max(ladder_plane) + Vector2.ONE * 5000.0
	for x: int in range(floori(minimum.x / GRID), ceili(maximum.x / GRID) + 1):
		for y: int in range(floori(minimum.y / GRID), ceili(maximum.y / GRID) + 1):
			var p: Vector2 = Vector2(x, y) * GRID
			var direction: Vector3 = (town + (forward * p.x + side * p.y) / noise.radius).normalized()
			# 为天梯二百米基座和过渡地形预留净空，避免末塔落进后续台地。
			if direction.distance_to(ladder) * noise.radius < 350:
				continue
			var height: float = noise.height(direction)
			if height < 30 or noise.water_surface(direction, height) > -INF or noise.river_distance(direction) < 100 or noise.slope(direction, height) >= 0.6:
				continue
			var low: float = height
			for angle: int in 8:
				var point: Vector3 = SurfaceSites.offset_direction(direction, SurfaceSites.tangent_forward(direction).rotated(direction, angle * TAU / 8), 1000, noise.radius)
				low = minf(low, noise.height(point))
			if height - low >= 80:
				_candidates.append({"direction": direction, "height": height, "relief": height - low, "index": _candidates.size()})
	var first: int = _near(town, 1800.0, old_peak, town)
	var peak: int = _near(old_peak, 1500.0, old_peak)
	var last: int = _near(ladder, 2000.0, old_peak)
	if mini(first, mini(peak, last)) < 0:
		push_error("塔链烘焙失败：古城、山口或天梯附近没有符合条件的候选。")
		return []
	var a: PackedInt32Array = _route(first, peak)
	var b: PackedInt32Array = _route(peak, last)
	if a.is_empty() or b.is_empty():
		push_error("塔链烘焙失败：无法经过山口连通古城与天梯。")
		return []
	a.append_array(b.slice(1))
	# 已交付版本使用九个存档编号；补入通视中继，避免重选末塔后删除旧编号。
	while a.size() < 9:
		var insertion: Vector2i = _relay(a)
		if insertion.x < 0:
			push_error("塔链烘焙失败：无法保留九个已有存档编号。")
			return []
		a.insert(insertion.x, insertion.y)
	if a.size() < 6 or a.size() > 10:
		push_error("塔链烘焙失败：塔数不在六至十座之间：" + str(a.size()))
		return []
	var result: Array[Dictionary] = []
	for index: int in a.size():
		var tower: Dictionary = _candidates[a[index]].duplicate()
		tower.erase("index")
		tower["id"] = index
		tower["next"] = index + 1 if index + 1 < a.size() else -1
		tower["mountain_pass"] = a[index] == peak
		tower["old_peak_distance"] = Vector3(tower["direction"]).angle_to(old_peak) * noise.radius if a[index] == peak else 0.0
		tower["forward"] = SurfaceSites.tangent_forward(tower["direction"])
		result.append(tower)
	print("塔链选址：候选 %d，塔 %d，山口旧址偏移 %.1f 米" % [_candidates.size(), result.size(), Vector3(_candidates[peak]["direction"]).angle_to(old_peak) * noise.radius])
	return result


func _relay(path: PackedInt32Array) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var score: float = INF
	for at: int in path.size() - 1:
		var a: Dictionary = _candidates[path[at]]
		var b: Dictionary = _candidates[path[at + 1]]
		for id: int in _candidates.size():
			if id in path:
				continue
			var c: Dictionary = _candidates[id]
			var da: float = Vector3(a["direction"]).angle_to(c["direction"]) * _noise.radius
			var db: float = Vector3(b["direction"]).angle_to(c["direction"]) * _noise.radius
			if minf(da, db) < MIN_SPACING or maxf(da, db) > MAX_SPACING or da + db >= score:
				continue
			var origin: Vector3 = Vector3(c["direction"]) * (_noise.radius + float(c["height"]) + TOP)
			if visible(_noise, origin, Vector3(a["direction"]) * (_noise.radius + float(a["height"]) + TOP)) and visible(_noise, origin, Vector3(b["direction"]) * (_noise.radius + float(b["height"]) + TOP)):
				best = Vector2i(at + 1, id)
				score = da + db
	return best


func _near(center: Vector3, limit: float, target: Vector3, visible_from: Vector3 = Vector3.ZERO) -> int:
	var best: int = -1
	var score: float = INF
	for index: int in _candidates.size():
		var candidate: Dictionary = _candidates[index]
		var direction: Vector3 = candidate["direction"]
		var distance: float = direction.angle_to(center) * _noise.radius
		if distance > limit:
			continue
		if visible_from != Vector3.ZERO and distance < 500.0:
			continue
		if visible_from != Vector3.ZERO and not visible(_noise, visible_from * (_noise.radius + _noise.height(visible_from) + 1.7), direction * (_noise.radius + float(candidate["height"]) + TOP)):
			continue
		var value: float = distance + direction.angle_to(target) * _noise.radius * 0.2 - float(candidate["height"]) * 0.1
		if value < score:
			score = value
			best = index
	return best


func _route(start: int, target: int) -> PackedInt32Array:
	# A* 在离线候选图搜索，保留贪心规则的朝向约束，并允许通视障碍前回退。
	var open: Array[int] = [start]
	var costs: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var closed: Dictionary = {}
	var destination: Vector3 = _candidates[target]["direction"]
	while not open.is_empty():
		var at: int = 0
		var score: float = INF
		for index: int in open.size():
			var value: float = float(costs[open[index]]) + Vector3(_candidates[open[index]]["direction"]).angle_to(destination) * _noise.radius
			if value < score:
				at = index
				score = value
		var current: int = open[at]
		open.remove_at(at)
		if current == target:
			var path: PackedInt32Array = [current]
			while previous.has(current):
				current = previous[current]
				path.insert(0, current)
			return path
		closed[current] = true
		var origin: Vector3 = _candidates[current]["direction"]
		var toward: Vector3 = destination.slide(origin).normalized()
		for next: int in _candidates.size():
			if closed.has(next):
				continue
			var direction: Vector3 = _candidates[next]["direction"]
			var distance: float = origin.angle_to(direction) * _noise.radius
			if distance < MIN_SPACING or distance > MAX_SPACING or direction.slide(origin).normalized().dot(toward) < cos(deg_to_rad(50.0)):
				continue
			var key: Vector2i = Vector2i(mini(current, next), maxi(current, next))
			if not _visibility.has(key):
				_visibility[key] = visible(_noise, origin * (_noise.radius + float(_candidates[current]["height"]) + TOP), direction * (_noise.radius + float(_candidates[next]["height"]) + TOP))
			if not _visibility[key]:
				continue
			var cost: float = float(costs[current]) + distance + (1500.0 if distance > 5000 else 0.0)
			if not costs.has(next) or cost < float(costs[next]):
				costs[next] = cost
				previous[next] = current
				if not next in open:
					open.append(next)
	return []


static func visible(noise: TerrainNoise, eye: Vector3, target: Vector3) -> bool:
	var steps: int = ceili(eye.distance_to(target) / 50.0)
	for sample: int in range(1, steps):
		var point: Vector3 = eye.lerp(target, sample / float(steps))
		if point.length() < noise.radius + noise.height(point.normalized()) + 0.5:
			return false
	return true


func _plane(direction: Vector3, center: Vector3, forward: Vector3, side: Vector3) -> Vector2:
	return Vector2(direction.dot(forward), direction.dot(side)) * _noise.radius / direction.dot(center)
