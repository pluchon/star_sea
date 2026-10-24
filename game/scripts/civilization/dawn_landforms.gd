class_name DawnLandforms
extends RefCounted

# 球面曲线和空间索引只在初始化时构建，工作线程仅查询不可变数据。
const INDEX_SIZE: int = 32
const RANGE_HALF_WIDTH: float = 9000.0
const CANYON_HALF_WIDTH: float = 1300.0
const CANYON_FLOOR_HALF_WIDTH: float = 110.0
const CANYON_LAYERS: int = 11
var radius: float = 40000.0
var metadata: Dictionary
var ridge: PackedVector3Array
var canyon: PackedVector3Array
var ridge_lengths: PackedFloat32Array
var canyon_lengths: PackedFloat32Array
var _ridge_index: Dictionary = {}
var _canyon_index: Dictionary = {}
var _ridge_noise: FastNoiseLite
var _geology: FastNoiseLite


func _init(data: Dictionary = {}, planet_radius: float = 40000.0) -> void:
	radius = planet_radius
	metadata = data
	if data.is_empty():
		return
	ridge = data["ridge"]
	canyon = data["canyon"]
	ridge_lengths = _lengths(ridge)
	canyon_lengths = _lengths(canyon)
	_index(ridge, RANGE_HALF_WIDTH + 3000.0, _ridge_index)
	_index(canyon, CANYON_HALF_WIDTH + 3000.0, _canyon_index)
	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = 20261021
	_ridge_noise.frequency = 1.0 / 2600.0
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_geology = FastNoiseLite.new()
	_geology.seed = 20261026
	_geology.frequency = 1.0 / 4800.0


func _lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = [0.0]
	for index: int in points.size() - 1:
		result.append(result[-1] + points[index].angle_to(points[index + 1]) * radius)
	return result


func _index(points: PackedVector3Array, reach: float, buckets: Dictionary) -> void:
	for cell: int in 6 * INDEX_SIZE * INDEX_SIZE:
		var point: Vector3 = HydrologyData.direction_at(cell, INDEX_SIZE) * radius
		var entries: PackedInt32Array = []
		for segment: int in points.size() - 1:
			var closest: Vector3 = Geometry3D.get_closest_point_to_segment(point, points[segment] * radius, points[segment + 1] * radius)
			if point.distance_to(closest) < reach:
				entries.append(segment)
		if not entries.is_empty():
			buckets[cell] = entries


func nearest(direction: Vector3, is_canyon: bool = false) -> Vector3:
	var entries: PackedInt32Array = (_canyon_index if is_canyon else _ridge_index).get(HydrologyData.cell_at(direction, INDEX_SIZE), PackedInt32Array())
	var points: PackedVector3Array = canyon if is_canyon else ridge
	var lengths: PackedFloat32Array = canyon_lengths if is_canyon else ridge_lengths
	var best: Vector3 = Vector3(INF, 0, -1)
	var point: Vector3 = direction * radius
	for index: int in entries:
		var start: Vector3 = points[index] * radius
		var line: Vector3 = (points[index + 1] - points[index]) * radius
		var weight: float = clampf((point - start).dot(line) / line.length_squared(), 0.0, 1.0)
		var distance: float = point.distance_to((start + line * weight).normalized() * radius)
		if distance < best.x:
			best = Vector3(distance, lerpf(lengths[index], lengths[index + 1], weight), index)
	return best


func height(direction: Vector3, base: float) -> float:
	if metadata.is_empty() or direction.distance_squared_to(metadata["spawn"]) * radius * radius < 2000.0 * 2000.0:
		return base
	var point: Vector3 = direction * radius
	var near: Vector3 = nearest(direction)
	var result: float = base
	if near.x < RANGE_HALF_WIDTH:
		var envelope: float = pow(1.0 - smoothstep(0.0, RANGE_HALF_WIDTH, near.x), 1.6)
		var increase: float = 1750.0 + sin(near.y / 13000.0) * 250.0
		for pass_site: Dictionary in metadata["passes"]:
			increase = lerpf(increase, 500.0, 1.0 - smoothstep(500.0, 1800.0, absf(near.y - float(pass_site["distance"]))))
		var detail: float = (_ridge_noise.get_noise_3dv(point) * 0.5 + 0.5) * 0.22
		var rise: float = increase * envelope * (0.86 + detail)
		if base + rise > 900.0 and _geology.get_noise_3dv(point) > 0.24:
			var tier: float = rise / 90.0
			rise = (floorf(tier) + smoothstep(0.83, 1.0, fposmod(tier, 1.0))) * 90.0
		result = minf(base + rise, 4090.0)
		for peak: Dictionary in metadata["peaks"]:
			var delta: Vector3 = (direction - Vector3(peak["direction"])) * radius
			var distance: float = delta.length()
			var shape: String = peak["shape"]
			var target: float = float(peak["height"])
			if shape == "horn":
				distance = maxf(absf(delta.dot(peak["right"])), absf(delta.dot(peak["forward"])))
			elif shape == "twins":
				var side: float = delta.dot(peak["right"])
				distance = minf((delta - Vector3(peak["right"]) * 450.0).length(), (delta + Vector3(peak["right"]) * 450.0).length())
				target -= 400.0 * (1.0 - smoothstep(0.0, 280.0, absf(side)))
			elif shape == "mesa":
				distance = maxf(0.0, distance - 300.0) * 3.0
			result = lerpf(result, target - distance * 0.55, 1.0 - smoothstep(0.0, 1600.0, distance))
		for pass_site: Dictionary in metadata["passes"]:
			var delta: Vector3 = (direction - Vector3(pass_site["direction"])) * radius
			var along: float = absf(delta.dot(pass_site["along"]))
			var across: float = absf(delta.dot(pass_site["across"]))
			if along < 1100.0 and across < RANGE_HALF_WIDTH:
				var grade: float = float(pass_site["ground"]) + 500.0 * (1.0 - smoothstep(0.0, RANGE_HALF_WIDTH, across))
				result = lerpf(result, grade, (1.0 - smoothstep(500.0, 1100.0, along)) * (1.0 - smoothstep(8500.0, 9000.0, across)))
	near = nearest(direction, true)
	if near.x < CANYON_HALF_WIDTH * 1.1 + 900.0:
		var t: float = near.y / canyon_lengths[-1]
		var floor_level: float = float(metadata["canyon_source_level"]) * pow(1.0 - t, 5.0) - t * 2.0
		var depth: float = (760.0 + 120.0 * sin(t * PI)) * smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.94, 1.0, t))
		var segment: int = int(near.z)
		var signed: float = direction.dot(canyon[segment].cross(canyon[segment + 1]))
		var half_width: float = CANYON_HALF_WIDTH * (0.85 if signed > 0.0 else 1.1)
		var across: float = clampf((near.x - CANYON_FLOOR_HALF_WIDTH) / (half_width - CANYON_FLOOR_HALF_WIDTH), 0.0, 1.0)
		var tier: float = across * CANYON_LAYERS
		# 十一级大台阶；每级陡坡占横向间距一半，最窄约 45 米，避免远景采样形成针状锯齿。
		var phase: float = fposmod(tier, 1.0)
		var wall: float = (floorf(tier) + phase * 0.04 + smoothstep(0.50, 1.0, phase) * 0.96) / CANYON_LAYERS
		var carved: float = floor_level + depth * wall
		# 谷底始终保持出水坡度，最外侧平滑接回原高原。
		result = lerpf(carved, result, smoothstep(half_width, half_width + 900.0, near.x))
	# 保护区外渐入山体，不能在两公里边界突然增加几百米高度。
	var spawn_distance: float = direction.distance_to(metadata["spawn"]) * radius
	return lerpf(base, result, smoothstep(2000.0, 4500.0, spawn_distance))


func surface_marks(direction: Vector3, elevation: float, slope: float) -> Color:
	if metadata.is_empty():
		return Color(0, 0, 0, 0)
	var near: Vector3 = nearest(direction, true)
	var wall: float = (1.0 - smoothstep(1100.0, CANYON_HALF_WIDTH, near.x)) * smoothstep(0.15, 0.5, slope)
	var glacier: float = smoothstep(2200.0, 2500.0, elevation) * (1.0 - smoothstep(0.15, 0.3, slope)) * (1.0 - smoothstep(5000.0, 7000.0, nearest(direction).x))
	var canyon_region: float = (1.0 - smoothstep(CANYON_HALF_WIDTH * 1.1, CANYON_HALF_WIDTH * 1.1 + 200, near.x)) * smoothstep(CANYON_FLOOR_HALF_WIDTH + 40, CANYON_FLOOR_HALF_WIDTH + 100, near.x)
	return Color(wall, glacier, canyon_region, 0)
