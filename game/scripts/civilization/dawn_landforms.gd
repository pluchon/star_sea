class_name DawnLandforms
extends RefCounted

# 球面曲线和空间索引只在初始化时构建，工作线程仅查询不可变数据。
const INDEX_SIZE: int = 32
const RANGE_HALF_WIDTH: float = 9000.0
const CANYON_HALF_WIDTH: float = 1300.0
const CANYON_FLOOR_HALF_WIDTH: float = 110.0
const CANYON_LAYERS: int = 10
const STRATA_LEVELS: Array[float] = [0, 71, 167, 228, 338, 420, 512, 563, 679, 755, 860]
var radius: float = 40000.0
var metadata: Dictionary
var ridge: PackedVector3Array
var canyon: PackedVector3Array
var canyon_curve: PackedVector3Array
var ridge_lengths: PackedFloat32Array
var canyon_lengths: PackedFloat32Array
var _ridge_index: Dictionary = {}
var _canyon_index: Dictionary = {}
var _strata_noise: FastNoiseLite
var _heightfield: DawnHeightfield


func _init(data: Dictionary = {}, planet_radius: float = 40000.0, include_heightfield: bool = true) -> void:
	radius = planet_radius
	metadata = data
	if data.is_empty():
		return
	ridge = data["ridge"]
	canyon = data["canyon"]
	canyon_curve = _smooth_curve(canyon)
	if include_heightfield:
		_heightfield = DawnHeightfield.shared()
	ridge_lengths = _lengths(ridge)
	canyon_lengths = _lengths(canyon_curve)
	_index(ridge, RANGE_HALF_WIDTH + 3000.0, _ridge_index)
	_index(canyon_curve, CANYON_HALF_WIDTH + 3000.0, _canyon_index)
	_strata_noise = FastNoiseLite.new()
	_strata_noise.seed = 20261026
	_strata_noise.frequency = 1.0 / 190.0


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
	var points: PackedVector3Array = canyon_curve if is_canyon else ridge
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


# 山脉、火山和峡谷主体已经烘焙；这里只增加小于格距的岩层台阶。
func height(direction: Vector3, base: float) -> float:
	if metadata.is_empty() or direction.distance_squared_to(metadata["spawn"]) * radius * radius < 2000.0 * 2000.0:
		return base
	var near: Vector3 = nearest(direction, true)
	if near.x < CANYON_FLOOR_HALF_WIDTH + 40.0 or near.x > 1600.0:
		return base
	var t: float = near.y / canyon_lengths[-1]
	var strength: float = smoothstep(0.12, 0.20, t) * (1.0 - smoothstep(0.88, 0.94, t))
	if strength <= 0.0:
		return base
	var floor_level: float = float(metadata["canyon_source_level"]) * pow(1.0 - t, 5.0) - t * 2.0
	var above: float = base - floor_level
	var jitter: float = _strata_noise.get_noise_3dv(direction * (radius + above * 0.25)) * 16.0
	var warped: float = above - jitter
	var layer: int = clampi(STRATA_LEVELS.bsearch(warped) - 1, 0, STRATA_LEVELS.size() - 2)
	var low: float = STRATA_LEVELS[layer]
	var high: float = STRATA_LEVELS[layer + 1]
	var phase: float = clampf((warped - low) / (high - low), 0, 1)
	# 每级前段缓、后段陡，边缘扰动和坍塌减少完整等高轮廓。
	var ledge: float = phase * 0.07 + smoothstep(0.42, 1.0, phase) * 0.93
	var offset: float = low + (high - low) * ledge + jitter - above
	var collapse_value: float = _heightfield.collapse_at(direction) if _heightfield != null else 0.0
	strength *= (1.0 - smoothstep(1100.0, 1550.0, near.x)) * smoothstep(150.0, 240.0, near.x)
	strength *= smoothstep(20.0, 80.0, above) * (1.0 - smoothstep(820.0, 930.0, above))
	return base + clampf(offset, -45.0, 45.0) * strength * (1.0 - collapse_value)


static func _smooth_curve(points: PackedVector3Array) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for index: int in points.size() - 1:
		var a: Vector3 = points[maxi(0, index - 1)]
		var b: Vector3 = points[index]
		var c: Vector3 = points[index + 1]
		var d: Vector3 = points[mini(points.size() - 1, index + 2)]
		for sample: int in 6:
			var t: float = sample / 6.0
			result.append((b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)))).normalized())
	result.append(points[-1])
	return result


func surface_marks(direction: Vector3, elevation: float, slope: float) -> Color:
	if metadata.is_empty():
		return Color(0, 0, 0, 0)
	var near: Vector3 = nearest(direction, true)
	var wall: float = (1.0 - smoothstep(1100.0, CANYON_HALF_WIDTH, near.x)) * smoothstep(0.15, 0.5, slope)
	var glacier: float = smoothstep(2200.0, 2500.0, elevation) * (1.0 - smoothstep(0.15, 0.3, slope)) * (1.0 - smoothstep(5000.0, 7000.0, nearest(direction).x))
	var canyon_region: float = (1.0 - smoothstep(CANYON_HALF_WIDTH * 1.1, CANYON_HALF_WIDTH * 1.1 + 200, near.x)) * smoothstep(CANYON_FLOOR_HALF_WIDTH + 40, CANYON_FLOOR_HALF_WIDTH + 100, near.x)
	return Color(wall, glacier, canyon_region, 0)
