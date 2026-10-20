class_name GlobalHydrology
extends RefCounted

var data: HydrologyData
var radius: float
var _lake_levels: Dictionary = {}
var _positions: PackedVector3Array
var _vectors: PackedVector3Array
var _inverse_lengths: PackedFloat32Array


func _init(value: HydrologyData, planet_radius: float) -> void:
	data = value
	radius = planet_radius
	_positions.resize(data.river_points.size())
	_vectors.resize(data.river_points.size())
	_inverse_lengths.resize(data.river_points.size())
	var coverage: Dictionary = data.lake_coverage()
	for cell: int in coverage:
		_lake_levels[cell] = data.lake_levels[int(coverage[cell])]
	for river: int in data.river_starts.size() - 1:
		for index: int in range(data.river_starts[river], data.river_starts[river + 1]):
			_positions[index] = data.river_points[index] * radius
			if index + 1 < data.river_starts[river + 1]:
				_vectors[index] = (data.river_points[index + 1] - data.river_points[index]) * radius
				_inverse_lengths[index] = 1.0 / maxf(_vectors[index].length_squared(), 0.0001)


func nearest(direction: Vector3, carving: bool = false) -> Vector4:
	var fine: bool = carving and not data.carve_offsets.is_empty()
	var bucket: int = HydrologyData.cell_at(direction, HydrologyData.CARVE_GRID if fine else HydrologyData.BUCKET_GRID)
	var offsets: PackedInt32Array = data.carve_offsets if fine else data.bucket_offsets
	var segments: PackedInt32Array = data.carve_segments if fine else data.bucket_segments
	var point: Vector3 = direction * radius
	var minimum: float = INF
	var best: int = -1
	var weight: float = 0.0
	for cursor: int in range(offsets[bucket], offsets[bucket + 1]):
		var index: int = segments[cursor]
		var offset: Vector3 = point - _positions[index]
		var along: Vector3 = _vectors[index]
		var t: float = clampf(offset.dot(along) * _inverse_lengths[index], 0.0, 1.0)
		var distance: float = (offset - along * t).length_squared()
		if distance < minimum:
			minimum = distance
			best = index
			weight = t
	if best < 0:
		return Vector4(INF, 0, 0, -1)
	if data.river_flags[best] & 1:
		weight = smoothstep(0.38, 0.62, weight)
	return Vector4(sqrt(minimum), lerpf(data.river_levels[best], data.river_levels[best + 1], weight), lerpf(data.river_widths[best], data.river_widths[best + 1], weight), best)


func lake_surface(direction: Vector3) -> float:
	return float(_lake_levels.get(HydrologyData.cell_at(direction), -INF))


func carve(direction: Vector3, height: float) -> float:
	var nearest_value: Vector4 = nearest(direction, true)
	if nearest_value.w < 0.0:
		return height
	var distance: float = nearest_value.x
	var level: float = nearest_value.y
	var half_width: float = nearest_value.z
	var flags: int = data.river_flags[int(nearest_value.w)]
	var bank: float = half_width * 2.5 + 25.0
	var steepness: float = 0.35
	if flags & 2:
		bank = half_width * 4.0 + 60.0
		steepness = 0.9
	if distance >= half_width + bank:
		return height
	if distance < half_width:
		var depth: float = 0.8 + half_width * 0.12 + (3.0 if flags & 1 else 0.0)
		return level - depth * (1.0 - pow(distance / half_width, 2.0))
	var shaped: float = minf(maxf(height, level + 0.15), level + 0.2 + (distance - half_width) * steepness)
	return lerpf(height, shaped, 1.0 - smoothstep(half_width, half_width + bank, distance))


func water_surface(direction: Vector3) -> float:
	var nearest_value: Vector4 = nearest(direction)
	if nearest_value.w >= 0.0 and nearest_value.x < nearest_value.z * 1.05:
		return maxf(nearest_value.y, lake_surface(direction))
	return lake_surface(direction)


func water_body(direction: Vector3) -> String:
	if lake_surface(direction) > -INF:
		return "湖泊"
	var nearest_value: Vector4 = nearest(direction)
	if nearest_value.w >= 0.0 and nearest_value.x < nearest_value.z * 1.05:
		return "瀑布" if data.river_flags[int(nearest_value.w)] & 1 else "河流"
	return ""
