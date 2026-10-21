class_name CivilizationTerrain
extends RefCounted

const ROAD_CELL: float = 64.0 # 道路和明渠的不可变索引格，米。
var data: CivilizationData
var radius: float
var _road_index: Dictionary = {}
var _trench_index: Dictionary = {}
var _bounds: AABB


func _init(value: CivilizationData, planet_radius: float) -> void:
	data = value
	radius = planet_radius
	if data == null:
		return
	# 全球绝大多数查询不经过文明区，先用包围盒排除道路和明渠索引查询。
	_bounds = AABB(Vector3(data.town["direction"]) * radius - Vector3.ONE * 700.0, Vector3.ONE * 1400.0)
	for road: Dictionary in data.roads:
		for point: Vector3 in road["points"]:
			_bounds = _bounds.expand(point * radius - Vector3.ONE * 8.0).expand(point * radius + Vector3.ONE * 8.0)
	for point: Vector3 in data.aqueduct.get("points", PackedVector3Array()):
		_bounds = _bounds.expand(point * radius - Vector3.ONE * 8.0).expand(point * radius + Vector3.ONE * 8.0)
	for road: Dictionary in data.roads:
		var points: PackedVector3Array = road["points"]
		for index: int in points.size() - 1:
			var a: Vector3 = points[index] * radius
			var b: Vector3 = points[index + 1] * radius
			var low: Vector3i = Vector3i(((a.min(b) - Vector3.ONE * 7.0) / ROAD_CELL).floor())
			var high: Vector3i = Vector3i(((a.max(b) + Vector3.ONE * 7.0) / ROAD_CELL).floor())
			var segment: Dictionary = {"a": a, "b": b, "h0": road["levels"][index], "h1": road["levels"][index + 1], "width": road["width"], "wear0": road["wear"][index], "wear1": road["wear"][index + 1]}
			for x: int in range(low.x, high.x + 1):
				for y: int in range(low.y, high.y + 1):
					for z: int in range(low.z, high.z + 1):
						var key: Vector3i = Vector3i(x, y, z)
						if not _road_index.has(key):
							_road_index[key] = []
						_road_index[key].append(segment)
	if not data.aqueduct.is_empty():
		var points: PackedVector3Array = data.aqueduct["points"]
		for index: int in data.aqueduct.get("trenches", PackedInt32Array()):
			var a: Vector3 = points[index] * radius
			var b: Vector3 = points[index + 1] * radius
			var low: Vector3i = Vector3i(((a.min(b) - Vector3.ONE * 2.0) / ROAD_CELL).floor())
			var high: Vector3i = Vector3i(((a.max(b) + Vector3.ONE * 2.0) / ROAD_CELL).floor())
			for x: int in range(low.x, high.x + 1):
				for y: int in range(low.y, high.y + 1):
					for z: int in range(low.z, high.z + 1):
						var key: Vector3i = Vector3i(x, y, z)
						if not _trench_index.has(key):
							_trench_index[key] = []
						_trench_index[key].append({"a": a, "b": b})


func apply(direction: Vector3, base: float, hydro: GlobalHydrology) -> float:
	if not _bounds.has_point(direction * radius):
		return base
	if direction.distance_to(data.town["direction"]) * radius < 32.0:
		return data.town["level"]
	var height: float = regions(direction, base)
	var road: Vector4 = road_at(direction)
	if road.x < 6.0:
		var river: Vector4 = hydro.nearest(direction, true)
		if river.w < 0.0 or river.x > river.z + 15.0:
			height = lerpf(height, clampf(road.y, height - 1.5, height + 1.5), 1.0 - smoothstep(2.5, 6.0, road.x))
	if not data.aqueduct.is_empty():
		# 明渠只在触及山坡的短段雕刻；架空段不改变地表。
		var point: Vector3 = direction * radius
		var entries: Array = _trench_index.get(Vector3i((point / ROAD_CELL).floor()), [])
		var carve: float = 0.0
		for segment: Dictionary in entries:
			var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(point, segment["a"], segment["b"])
			var distance: float = point.distance_to(nearest)
			if distance < 1.7:
				carve = maxf(carve, 1.2 * (1.0 - smoothstep(0.7, 1.7, distance)))
		height -= carve
	return height


func regions(direction: Vector3, base: float) -> float:
	var center: Vector3 = data.town["direction"]
	var distance: float = direction.distance_to(center) * radius
	var height: float = base
	if distance < 44.0:
		height = lerpf(base, data.town["level"], 1.0 - smoothstep(32.0, 44.0, distance))
	elif distance < 128.0:
		var point: Vector2 = town_point(direction)
		var angle: float = fposmod(atan2(point.y, point.x), TAU)
		for sector: Dictionary in data.sectors:
			if distance < sector["inner"] or distance > sector["outer"] or int(sector["index"]) != int(angle / (TAU / 12.0)):
				continue
			var radial_weight: float = smoothstep(0.0, 6.0, minf(distance - float(sector["inner"]), float(sector["outer"]) - distance))
			var angular_weight: float = smoothstep(0.0, 6.0, minf(fposmod(angle, TAU / 12.0), TAU / 12.0 - fposmod(angle, TAU / 12.0)) * distance)
			height = lerpf(height, sector["level"], radial_weight * angular_weight)
	if distance < 650.0:
		var field: Dictionary = terrace_at(direction)
		if not field.is_empty():
			var p: Vector2 = field_point(field, direction)
			var edge: float = minf(50.0 - absf(p.x), 40.0 - absf(p.y))
			var fraction: float = fposmod(height, 2.0)
			var target: float = floorf(height / 2.0) * 2.0 + smoothstep(0.8, 2.0, fraction) * 2.0
			height = lerpf(height, target, smoothstep(0.0, 10.0, edge))
	return height


func road_at(direction: Vector3) -> Vector4:
	var point: Vector3 = direction * radius
	var best: Vector4 = Vector4(INF, 0, 0, 1)
	var entries: Array = _road_index.get(Vector3i((point / ROAD_CELL).floor()), [])
	for segment: Dictionary in entries:
		var a: Vector3 = segment["a"]
		var delta: Vector3 = Vector3(segment["b"]) - a
		var weight: float = clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.001), 0, 1)
		var distance: float = point.distance_to(a + delta * weight)
		if distance < best.x:
			best = Vector4(distance, lerpf(segment["h0"], segment["h1"], weight), segment["width"], lerpf(segment["wear0"], segment["wear1"], weight))
	return best


func in_clearing(direction: Vector3) -> bool:
	var distance: float = direction.distance_to(data.town["direction"]) * radius
	if distance < 32.0:
		for gap: Vector3 in data.town.get("paving_gaps", PackedVector3Array()):
			if direction.distance_to(gap) * radius < 0.9:
				return false
		return true
	if road_at(direction).x < 3.0:
		return true
	if distance < 150.0:
		for house: Dictionary in data.town.get("houses", []):
			if direction.distance_to(house["direction"]) * radius < 10.0:
				return true
	return false


func terrace_at(direction: Vector3) -> Dictionary:
	if direction.dot(data.town["direction"]) < cos(650.0 / radius):
		return {}
	for field: Dictionary in data.terraces:
		var point: Vector2 = field_point(field, direction)
		if absf(point.x) < 50.0 and absf(point.y) < 40.0:
			return field
	return {}


func field_point(field: Dictionary, direction: Vector3) -> Vector2:
	var delta: Vector3 = (direction - Vector3(field["direction"])) * radius
	return Vector2(delta.dot(field["along"]), delta.dot(field["across"]))


func town_point(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(data.town["along"]), direction.dot(data.town["bank"])) * radius
