class_name SpawnWaterBake
extends RefCounted

# 保护区边缘还包含河岸雕刻宽度；保留相连河段，避免在两公里边界截断河口。
const PATH: String = "res://data/dawn_spawn_water.res"
const MARGIN: float = 2300.0


static func merge(data: HydrologyData, source: HydrologyData, spawn: Vector3, radius: float) -> void:
	var removed: Dictionary = {}
	for river: int in data.river_starts.size() - 1:
		for index: int in range(data.river_starts[river], data.river_starts[river + 1]):
			if spawn.angle_to(data.river_points[index]) * radius < MARGIN:
				removed[river] = true
				break
	# 上游支流不能指向已经移除的河段；这些支流随受保护的汇水区一起替换。
	var changed: bool = true
	while changed:
		changed = false
		for river: int in data.river_starts.size() - 1:
			if removed.has(river) or data.river_joins[river] < 0:
				continue
			for target: int in removed.keys():
				if data.river_joins[river] >= data.river_starts[target] and data.river_joins[river] < data.river_starts[target + 1]:
					removed[river] = true
					changed = true
					break
	var result: HydrologyData = HydrologyData.new()
	result.river_starts.append(0)
	_append_rivers(result, data, removed)
	_append_rivers(result, source, {})
	for property: String in ["river_points", "river_levels", "river_widths", "river_flags", "river_starts", "river_ends", "river_joins"]:
		data.set(property, result.get(property))
	result.lake_starts.append(0)
	for lake: int in data.lake_levels.size():
		var near: bool = false
		for cursor: int in range(data.lake_starts[lake], data.lake_starts[lake + 1]):
			near = near or spawn.angle_to(HydrologyData.direction_at(data.lake_cells[cursor])) * radius < MARGIN
		if not near:
			_append_lake(result, data, lake)
	for lake: int in source.lake_levels.size():
		_append_lake(result, source, lake)
	for property: String in ["lake_levels", "lake_cells", "lake_starts"]:
		data.set(property, result.get(property))
	data.statistics["protected_rivers"] = source.river_starts.size() - 1
	data.statistics["replaced_rivers"] = removed.size()
	# 总长度和瀑布数量从最终数据重新计数，不能沿用替换前的累计值。
	var length_value: float = 0.0
	var waterfalls: int = 0
	for river: int in data.river_starts.size() - 1:
		for index: int in range(data.river_starts[river], data.river_starts[river + 1] - 1):
			length_value += data.river_points[index].distance_to(data.river_points[index + 1]) * radius
			waterfalls += int(data.river_flags[index] & 1 != 0)
	data.statistics["river_km"] = length_value / 1000.0
	data.statistics["waterfalls"] = waterfalls
	var area: float = 0.0
	for cell: int in data.lake_cells:
		var u: float = (float(cell % HydrologyData.GRID) + 0.5) * 2.0 / HydrologyData.GRID - 1.0
		var v: float = (float((cell / HydrologyData.GRID) % HydrologyData.GRID) + 0.5) * 2.0 / HydrologyData.GRID - 1.0
		area += 4.0 * radius * radius / (HydrologyData.GRID * HydrologyData.GRID * pow(1.0 + u * u + v * v, 1.5))
	data.statistics["lake_area_km2"] = area / 1e6


static func _append_rivers(target: HydrologyData, source: HydrologyData, excluded: Dictionary) -> void:
	var remap: Dictionary = {}
	var first_river: int = target.river_joins.size()
	for river: int in source.river_starts.size() - 1:
		if excluded.has(river):
			continue
		var first: int = source.river_starts[river]
		var last: int = source.river_starts[river + 1]
		for index: int in range(first, last):
			remap[index] = target.river_points.size()
			target.river_points.append(source.river_points[index])
			target.river_levels.append(source.river_levels[index])
			target.river_widths.append(source.river_widths[index])
			target.river_flags.append(source.river_flags[index])
		target.river_starts.append(target.river_points.size())
		target.river_ends.append(HydrologyData.cell_at(source.river_points[last - 1]))
		target.river_joins.append(source.river_joins[river])
	for river: int in range(first_river, target.river_joins.size()):
		target.river_joins[river] = int(remap.get(target.river_joins[river], -1))


static func _append_lake(target: HydrologyData, source: HydrologyData, lake: int) -> void:
	target.lake_levels.append(source.lake_levels[lake])
	target.lake_cells.append_array(source.lake_cells.slice(source.lake_starts[lake], source.lake_starts[lake + 1]))
	target.lake_starts.append(target.lake_cells.size())
