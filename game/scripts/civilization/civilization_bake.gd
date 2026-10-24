class_name CivilizationBake
extends RefCounted

const TOWN_SEED: int = 20261027
const INTAKE_LIMIT: float = 8000.0 # 河岸高于河面约八十米，保留重力流向时允许沿既有河道上溯八公里。
const MAX_OLD_ROAD: float = 12000.0 # 古道超过十二公里时重新选择河段，避免步行主线绕行数小时。
var _noise: TerrainNoise
var _data: CivilizationData
var _hydro: HydrologyData
var _channel_error: Dictionary = {}


func generate(noise: TerrainNoise, hydro: HydrologyData, small_river: bool = false) -> CivilizationData:
	_noise = noise
	_hydro = hydro
	_noise.features.civilization = null
	_data = CivilizationData.new()
	_data.ladder = CivilizationSiting.ladder(noise)
	if _data.ladder.is_empty():
		return null
	_data.town = CivilizationSiting.town(noise, hydro, _data.ladder, small_river)
	if _data.town.is_empty():
		return generate(noise, hydro, true) if not small_river else null
	print("文明烘焙：台地、梯田和墓园")
	_regions()
	_noise.features.civilization = CivilizationTerrain.new(_data, noise.radius)
	_cemetery()
	_bridge()
	print("文明烘焙：出发地古道与墓园道路")
	var center: Vector3 = _data.town["direction"]
	var spawn: Vector3 = noise.features.site["direction"]
	var end: Vector3 = _road_end(spawn, center)
	var crossings: Array[Dictionary] = [_data.bridge]
	var path: PackedVector3Array = CivilizationPaths.find(noise, center, end, crossings)
	if path.is_empty():
		return null
	var road_length: float = 0.0
	for index: int in path.size() - 1:
		road_length += path[index].distance_to(path[index + 1]) * noise.radius
	if road_length > MAX_OLD_ROAD:
		if not small_river:
			print("文明烘焙：大河选址古道过长，改为带可用取水口的近处小河段")
			return generate(noise, hydro, true)
		push_error("文明烘焙失败：小河段方案的古道仍超过十二公里。")
		return null
	_data.roads.append(CivilizationPaths.road(noise, path, 4.0, "old_road"))
	path = CivilizationPaths.find(noise, center, _data.cemetery["direction"])
	if path.is_empty():
		return null
	_data.roads.append(CivilizationPaths.road(noise, path, 3.0, "cemetery"))
	_road_bridges()
	_noise.features.civilization = CivilizationTerrain.new(_data, noise.radius)
	print("文明烘焙：上游取水口与水渠")
	if not _aqueduct():
		return null
	_noise.features.civilization = CivilizationTerrain.new(_data, noise.radius)
	print("文明烘焙：古城与道路构件")
	var buildings: CivilizationBuildings = CivilizationBuildings.new(noise, _data)
	buildings.build()
	_data.sites = {"town": center, "plaza": center, "cemetery": _data.cemetery["direction"], "bridge": _data.bridge["direction"], "intake": _data.aqueduct["points"][0], "ladder": _data.ladder["direction"]}
	return _data


func _road_end(spawn: Vector3, town: Vector3) -> Vector3:
	var heading: Vector3 = spawn.direction_to(town).slide(spawn).normalized()
	for degrees: int in range(0, 181, 5):
		for sign_value: float in [-1.0, 1.0]:
			var forward: Vector3 = heading.rotated(spawn, deg_to_rad(degrees * sign_value))
			var clear: bool = true
			for distance: int in range(5, 256, 5):
				var point: Vector3 = SurfaceSites.offset_direction(spawn, forward, distance, _noise.radius)
				var height: float = _noise.height(point)
				if height < 3.0 or _noise.water_surface(point, height) > -INF or _noise.slope(point, height) > 0.65:
					clear = false
					break
			if clear:
				return SurfaceSites.offset_direction(spawn, forward, 250.0, _noise.radius)
	assert(false, "出发地二百五十米处没有连续干燥的古道终点。")
	return spawn


func _regions() -> void:
	var center: Vector3 = _data.town["direction"]
	var along: Vector3 = _data.town["along"]
	var bank: Vector3 = _data.town["bank"]
	for ring: int in 3:
		var inner: float = 44.0 + ring * 28.0
		for index: int in 12:
			var heights: Array[float] = []
			var allowed: bool = true
			for sample: int in 5:
				var angle: float = (index + 0.2 + sample * 0.15) * TAU / 12
				var direction: Vector3 = SurfaceSites.offset_direction(center, along * cos(angle) + bank * sin(angle), inner + 12, _noise.radius)
				var height: float = _noise.height(direction)
				var river: Vector4 = _noise.features.hydrology.nearest(direction)
				if (river.w >= 0 and river.x < river.z * 2.5 + 25.0) or _noise.slope(direction, height) > 0.25:
					allowed = false
				heights.append(height)
			if allowed:
				heights.sort()
				_data.sectors.append({"ring": ring, "index": index, "inner": inner, "outer": inner + 24.0, "level": snappedf(heights[2], 0.5)})
	for distance: float in range(150, 501, 25):
		for index: int in 72:
			var heading: Vector3 = along.rotated(center, index * TAU / 72)
			var direction: Vector3 = SurfaceSites.offset_direction(center, heading, distance, _noise.radius)
			var height: float = _noise.height(direction)
			var slope: float = _noise.slope(direction, height)
			if slope < 0.08 or slope > 0.30 or _noise.river_distance(direction) < 80.0:
				continue
			var crowded: bool = false
			for field: Dictionary in _data.terraces:
				crowded = crowded or direction.distance_to(field["direction"]) * _noise.radius < 120.0
			if crowded:
				continue
			var gradient: Vector3 = _gradient(direction)
			_data.terraces.append({"direction": direction, "along": gradient.cross(direction).normalized(), "across": gradient, "source_slope": slope})
			if _data.terraces.size() >= 3:
				return


func _gradient(direction: Vector3) -> Vector3:
	var forward: Vector3 = SurfaceSites.tangent_forward(direction)
	var right: Vector3 = forward.cross(direction)
	var height: float = _noise.height(direction)
	return (forward * (_noise.height(SurfaceSites.offset_direction(direction, forward, 4, _noise.radius)) - height) + right * (_noise.height(SurfaceSites.offset_direction(direction, right, 4, _noise.radius)) - height)).normalized()


func _cemetery() -> void:
	var center: Vector3 = _data.town["direction"]
	var best_height: float = -INF
	for distance: int in range(500, 1501, 100):
		for index: int in 48:
			var heading: Vector3 = Vector3(_data.town["along"]).rotated(center, index * TAU / 48)
			var direction: Vector3 = SurfaceSites.offset_direction(center, heading, distance, _noise.radius)
			var height: float = _noise.height(direction)
			if height <= best_height or _noise.slope(direction, height) > 0.25 or _noise.river_distance(direction) < 50.0:
				continue
			var top: Vector3 = Vector3(_data.ladder["direction"]) * (_noise.radius + float(_data.ladder["height"]) + 6200.0)
			if not CivilizationSiting.visible(_noise, direction * (_noise.radius + height + 1.7), top):
				continue
			best_height = height
			_data.cemetery = {"direction": direction, "height": height, "forward": direction.direction_to(_data.ladder["direction"]).slide(direction).normalized()}
	assert(not _data.cemetery.is_empty(), "没有找到能望向天梯的墓园山地。")


func _bridge() -> void:
	var index: int = _data.town["river_index"]
	var best: int = index
	var width: float = _hydro.river_widths[index]
	for sample: int in range(maxi(index - 20, _hydro.river_starts[_data.town["river"]]), mini(index + 21, _hydro.river_starts[_data.town["river"] + 1] - 1)):
		if _hydro.river_widths[sample] < width:
			best = sample
			width = _hydro.river_widths[sample]
	var direction: Vector3 = _hydro.river_points[best]
	var across: Vector3 = Vector3(_data.town["bank"]).slide(direction).normalized()
	var a: Vector3 = SurfaceSites.offset_direction(direction, across, width + 6.0, _noise.radius)
	var b: Vector3 = SurfaceSites.offset_direction(direction, across, -width - 6.0, _noise.radius)
	_data.bridge = {"direction": direction, "a": a, "b": b, "across": across, "level": maxf(_noise.height(a), _noise.height(b)) + 0.3, "river_index": best, "gap": 1.6}


func _aqueduct() -> bool:
	var town_index: int = _data.town["river_index"]
	var first: int = _hydro.river_starts[_data.town["river"]]
	var travelled: float = 0.0
	var intake: int = -1
	for index: int in range(town_index - 1, first - 1, -1):
		travelled += _hydro.river_points[index].distance_to(_hydro.river_points[index + 1]) * _noise.radius
		if travelled >= 800.0 and travelled <= INTAKE_LIMIT and _hydro.river_levels[index] >= float(_data.town["level"]) + 12.0:
			intake = index
			break
	if intake < 0:
		push_error("文明烘焙失败：同一条河上溯八公里仍没有高出广场十二米的取水口。")
		return false
	var end: Vector3 = SurfaceSites.offset_direction(_data.town["direction"], -Vector3(_data.town["bank"]), 32.0, _noise.radius)
	var levels: Vector2 = Vector2(_hydro.river_levels[intake] - 0.3, float(_data.town["level"]) + 4.0)
	var corridor: PackedVector3Array = []
	for index: int in range(intake, town_index + 1):
		var direction: Vector3 = _hydro.river_points[index]
		var heading: Vector3 = _hydro.river_points[maxi(index - 1, first)].direction_to(_hydro.river_points[mini(index + 1, town_index)]).slide(direction).normalized()
		var side: Vector3 = heading.cross(direction).normalized()
		if side.dot(_data.town["bank"]) < 0:
			side = -side
		corridor.append(SurfaceSites.offset_direction(direction, side, _hydro.river_widths[index] + 1.5, _noise.radius))
	corridor.append(end)
	var start: Vector3 = corridor[0]
	var shortcut: PackedVector3Array = [start]
	var cursor: int = 0
	while cursor < corridor.size() - 1:
		var next: int = cursor + 1
		for candidate: int in range(mini(cursor + 100, corridor.size() - 1), cursor, -5):
			var distance: float = corridor[cursor].distance_to(corridor[candidate]) * _noise.radius
			var clear: bool = true
			var count: int = maxi(1, ceili(distance / 4.0))
			for sample: int in count + 1:
				var weight: float = sample / float(count)
				var direction: Vector3 = corridor[cursor].slerp(corridor[candidate], weight).normalized()
				var level: float = lerpf(levels.x, levels.y, lerpf(cursor, candidate, weight) / (corridor.size() - 1))
				if _noise.height(direction) > level + 1.2:
					clear = false
					break
			if clear:
				next = candidate
				break
		shortcut.append(corridor[next])
		cursor = next
	var path: PackedVector3Array = CivilizationPaths.resample(shortcut, _noise.radius, 8.0)
	if not _channel_clear(path, levels):
		path = CivilizationPaths.resample(corridor, _noise.radius, 8.0)
	if not _channel_clear(path, levels):
		push_error("文明烘焙失败：沿河谷的渠道仍有超过可开挖深度的山坡：" + JSON.stringify(_channel_error))
		return false
	var trenches: PackedInt32Array = []
	for index: int in path.size() - 1:
		if _noise.height(path[index]) > lerpf(levels.x, levels.y, index / float(path.size() - 1)):
			trenches.append(index)
	_data.aqueduct = {"points": path, "levels": levels, "trenches": trenches, "intake_distance": travelled}
	return true


func _channel_clear(path: PackedVector3Array, levels: Vector2) -> bool:
	for index: int in path.size():
		var height: float = _noise.height(path[index])
		var level: float = lerpf(levels.x, levels.y, index / float(path.size() - 1))
		if height > level + 1.2:
			_channel_error = {"index": index, "ground": height, "channel": level}
			return false
	return true


func _road_bridges() -> void:
	_data.bridges.append(_data.bridge)
	for road: Dictionary in _data.roads:
		for direction: Vector3 in road["points"]:
			var river: Vector4 = _noise.features.hydrology.nearest(direction)
			if river.w < 0 or river.x > river.z * 1.2:
				continue
			var index: int = int(river.w)
			var center: Vector3 = _hydro.river_points[index]
			var duplicate: bool = false
			for bridge: Dictionary in _data.bridges:
				duplicate = duplicate or center.distance_to(bridge["direction"]) * _noise.radius < 150.0
			if duplicate:
				continue
			var along: Vector3 = _hydro.river_points[index].direction_to(_hydro.river_points[index + 1]).slide(center).normalized()
			var across: Vector3 = along.cross(center).normalized()
			var a: Vector3 = SurfaceSites.offset_direction(center, across, river.z + 6.0, _noise.radius)
			var b: Vector3 = SurfaceSites.offset_direction(center, across, -river.z - 6.0, _noise.radius)
			_data.bridges.append({"direction": center, "a": a, "b": b, "across": across, "level": maxf(_noise.height(a), _noise.height(b)) + 0.3, "river_index": index, "gap": 0.0})
