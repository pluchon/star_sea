class_name CivilizationBuildings
extends RefCounted

var _noise: TerrainNoise
var _data: CivilizationData
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _terrain: CivilizationTerrain


func _init(noise: TerrainNoise, data: CivilizationData) -> void:
	_noise = noise
	_data = data
	_terrain = CivilizationTerrain.new(data, noise.radius)
	_rng.seed = CivilizationBake.TOWN_SEED


func build() -> void:
	_plaza()
	_houses()
	_graves()
	_bridge()
	_aqueduct()
	_roads()
	_fields()
	_retaining_walls()


func _add(piece: String, direction: Vector3, forward: Vector3, offset: float = 0.0, scale_value: Vector3 = Vector3.ONE, group: String = "town") -> void:
	var sink: float = _rng.randf_range(0.0, 0.15) if offset == 0.0 else 0.0
	var transform_value: Transform3D = Transform3D(Basis.looking_at(forward.slide(direction).normalized(), direction).scaled(scale_value), direction * (_noise.radius + _noise.height(direction) + offset - sink))
	_data.placements.append({"piece": piece, "transform": transform_value, "moss": _rng.randf_range(0.15, 0.6), "sand": _rng.randf_range(0.05, 0.25), "group": group, "foundation": offset == 0.0, "sink": sink, "offset": offset})


func _point(center: Vector3, x: Vector3, y: Vector3, a: float, b: float) -> Vector3:
	return (center * _noise.radius + x * a + y * b).normalized()


func _plaza() -> void:
	var center: Vector3 = _data.town["direction"]
	var toward: Vector3 = center.direction_to(_data.ladder["direction"]).slide(center).normalized()
	var right: Vector3 = toward.cross(center).normalized()
	_add("plaza_ring", center, toward)
	_add("ring_monument", center, toward, 0.5, Vector3.ONE, "monument")
	# 少量生活遗迹按固定种子错落分布，避免环形阵列。
	for record: Array in [["column_fallen", -12, 7, 0.7], ["column_fallen", 14, -5, -0.4], ["column_fallen", 5, -17, 1.9], ["rubble_1", -16, -5, 0.2], ["rubble_2", 17, 11, -1.0], ["stele", -8, 16, -0.3], ["stele", 15, 3, 0.8], ["sand_drift", -16, -13, 1.3]]:
		var direction: Vector3 = _point(center, right, toward, record[1], record[2])
		_add(record[0], direction, toward.rotated(direction, record[3]))
	_data.trees.append(_point(center, right, toward, -13, -10))
	for index: int in 5:
		_add("wall_low_broken" if index == 3 else "wall_low", _point(center, right, toward, 19, -4 + index * 2), right)
	_add("steps", _point(center, right, toward, 21, 5), right)
	for x: int in range(-22, 23, 2):
		for y: int in range(-22, 23, 2):
			var distance: float = Vector2(x, y).length()
			if distance > 22 + _rng.randf_range(-2, 1) or distance < 4:
				continue
			if _rng.randf() < (smoothstep(16, 24, distance) * 0.55 + 0.025):
				continue
			var direction: Vector3 = _point(center, right, toward, x, y)
			var piece: String = "floor_slab_broken" if _rng.randf() < 0.12 else "floor_slab"
			_add(piece, direction, toward.rotated(direction, _rng.randf_range(-0.025, 0.025) + (PI / 2 if _rng.randf() < 0.5 else 0)), -0.35 + _rng.randf_range(-0.015, 0.015), Vector3(_rng.randf_range(0.93, 0.98), 1, _rng.randf_range(0.93, 0.98)))
	var well: Vector3 = _point(center, right, toward, 20, 10)
	for index: int in 8:
		var angle: float = index * TAU / 8
		_add("wall_low", _point(well, right, toward, cos(angle), sin(angle)), right * -sin(angle) + toward * cos(angle), 0, Vector3(0.4, 0.8, 0.6))
	_add("floor_slab_broken", well, toward, 0.8)


func _houses() -> void:
	var center: Vector3 = _data.town["direction"]
	var along: Vector3 = _data.town["along"]
	var bank: Vector3 = _data.town["bank"]
	var houses: Array[Dictionary] = []
	var serial: int = 0
	for sector: Dictionary in _data.sectors:
		var radius: float = float(sector["inner"]) + (2.0 if int(sector["ring"]) == 0 else 12.0)
		var count: int = 2 if int(sector["ring"]) > 0 and int(sector["index"]) % 2 == 0 else 1
		for index: int in count:
			var angle: float = (float(sector["index"]) + (0.35 + index * 0.3 if count == 2 else 0.5)) * TAU / 12
			var direction: Vector3 = SurfaceSites.offset_direction(center, along * cos(angle) + bank * sin(angle), radius, _noise.radius)
			var forward: Vector3 = direction.direction_to(center).slide(direction).normalized()
			var style: int = serial % 3
			var state: float = 0.85 if serial < 2 else _rng.randf()
			var root: Dictionary = {"direction": direction, "style": style, "state": state}
			houses.append(root)
			if style == 0:
				_round_house(direction, forward, 5.0, state)
			elif style == 1:
				_long_house(direction, forward, state)
			else:
				_courtyard(direction, forward, state)
			if serial % 10 == 3:
				_data.trees.append(direction)
			if serial < 2:
				var normal: Vector3 = forward.cross(direction).normalized() * (1.0 if style == 0 else -1.0)
				var wall: Vector3 = direction * (_noise.radius + _noise.height(direction)) + normal * (5.0 if style == 0 else 3.0)
				var up: Vector3 = direction
				var bottom: Vector3 = wall + normal * 0.35
				var exit: Vector3 = wall + normal * 1.0 + up.cross(normal) * 1.4 + up * 3.65
				_data.climbs.append(ClimbLayout.record("town_vines_" + str(serial), "vine_wall", bottom, bottom + up * 3.6, 2.0, normal, exit))
				_add("floor_slab", exit.normalized(), forward, exit.length() - _noise.radius - _noise.height(exit.normalized()) - 0.4)
			serial += 1
	_data.town["houses"] = houses


func _round_house(center: Vector3, forward: Vector3, radius: float, state: float) -> void:
	var right: Vector3 = forward.cross(center).normalized()
	for index: int in 12:
		var angle: float = index * TAU / 12
		var heading: Vector3 = forward * cos(angle) + right * sin(angle)
		var direction: Vector3 = SurfaceSites.offset_direction(center, heading, radius, _noise.radius)
		var piece: String = "door" if index == 0 else ("wall_window" if index in [4, 8] else "wall_arc")
		if state < 0.2 or (_rng.randf() < 0.3 and not (index == 3 and state >= 0.7)):
			piece += "_broken"
		var scale_value: Vector3 = Vector3.ONE * (radius / 5.0)
		if state < 0.2:
			scale_value.y *= 0.25
		_add(piece, direction, heading, 0, scale_value)
	if state >= 0.7:
		_add("dome_broken", center, forward, 3.55 * radius / 5.0, Vector3.ONE * (radius / 3.0))
	if state < 0.7:
		_add("rubble", SurfaceSites.offset_direction(center, right, radius + 1.0, _noise.radius), forward)
		_add("vines", SurfaceSites.offset_direction(center, -right, radius, _noise.radius), -right)


func _long_house(center: Vector3, forward: Vector3, state: float) -> void:
	var right: Vector3 = forward.cross(center).normalized()
	for sign_value: float in [-1.0, 1.0]:
		for index: int in 5:
			var direction: Vector3 = _point(center, right, forward, sign_value * 3, (index - 2) * 2)
			var piece: String = "door" if sign_value > 0 and index == 2 else "wall"
			if state < 0.2 or (_rng.randf() < 0.3 and not (sign_value < 0 and index == 2 and state >= 0.7)):
				piece += "_broken"
			_add(piece, direction, right * sign_value, 0, Vector3(1, 0.25 if state < 0.2 else 1.0, 1))
		for index: int in 3:
			_add("wall_broken" if state < 0.7 else "wall", _point(center, right, forward, (index - 1) * 2, sign_value * 5), forward * sign_value, 0, Vector3(1, 0.25 if state < 0.2 else 1.0, 1))
	if state >= 0.7:
		for x: int in 3:
			for y: int in 5:
				if _rng.randf() < 0.12:
					continue
				_add("floor_slab", _point(center, right, forward, (x - 1) * 2, (y - 2) * 2), forward, 3.6)
	else:
		_add("rubble_1", _point(center, right, forward, 2, 0), forward)


func _courtyard(center: Vector3, forward: Vector3, state: float) -> void:
	var right: Vector3 = forward.cross(center).normalized()
	for side: int in 4:
		var heading: Vector3 = forward.rotated(center, side * TAU / 4)
		var lateral: Vector3 = heading.cross(center)
		for index: int in 6:
			if side == 0 and index in [2, 3]:
				continue
			_add("wall_low_broken" if _rng.randf() < 0.25 else "wall_low", _point(center, lateral, heading, (index - 2.5) * 2, 6), heading)
	for sign_value: float in [-1.0, 1.0]:
		_add("column", _point(center, right, forward, sign_value * 2.5, 6), forward)
	_round_house(SurfaceSites.offset_direction(center, -forward, 1.5, _noise.radius), forward, 3.5, state)


func _graves() -> void:
	var center: Vector3 = _data.cemetery["direction"]
	var forward: Vector3 = _data.cemetery["forward"]
	var right: Vector3 = forward.cross(center)
	for row: int in 3:
		for index: int in 15:
			var angle: float = (index / 14.0 - 0.5) * PI * 0.8
			var direction: Vector3 = _point(center, right, forward, sin(angle) * (10 + row * 4), cos(angle) * (10 + row * 4))
			_add("standing_stone", direction, direction.direction_to(_data.ladder["direction"]))
			var placement: Dictionary = _data.placements[-1]
			var transform_value: Transform3D = placement["transform"]
			if index % 10 == 0:
				transform_value.basis = transform_value.basis.rotated(transform_value.basis.x.normalized(), PI * 0.5)
			elif index % 3 == 0:
				transform_value.basis = transform_value.basis.rotated(transform_value.basis.z.normalized(), deg_to_rad(_rng.randf_range(5, 15)))
			placement["transform"] = transform_value
	_add("stele", center, forward)
	for sign_value: float in [-1.0, 1.0]:
		_add("lamp_post", _point(center, right, forward, sign_value * 3, 0), forward)


func _bridge() -> void:
	for bridge: Dictionary in _data.bridges:
		_bridge_parts(bridge)


func _bridge_parts(bridge: Dictionary) -> void:
	var first_placement: int = _data.placements.size()
	var center: Vector3 = bridge["direction"]
	var across: Vector3 = bridge["across"]
	var length: float = Vector3(bridge["a"]).distance_to(bridge["b"]) * _noise.radius
	var count: int = ceili(length / 12.0)
	if count % 2 == 0:
		count += 1
	bridge["span_count"] = count
	bridge["length"] = count * 12.0
	for index: int in count:
		var direction: Vector3 = SurfaceSites.offset_direction(center, across, (index - count / 2) * 12.0, _noise.radius)
		var offset: float = float(bridge["level"]) - _noise.height(direction) - 6.0
		_add("bridge_span_gap" if index == count / 2 and float(bridge["gap"]) > 0 else "bridge_span", direction, -across.cross(direction), offset, Vector3.ONE, "road")
		if index > 0:
			var foot: Vector3 = SurfaceSites.offset_direction(direction, across, -6.0, _noise.radius)
			var height: float = float(bridge["level"]) - _noise.height(foot)
			_add("bridge_pier", foot, across, 0, Vector3(1, maxf(height - 0.4, 0.1) / 6.0, 1))
	for index: int in range(first_placement, _data.placements.size()):
		_data.placements[index]["bridge_direction"] = center


func _aqueduct() -> void:
	var points: PackedVector3Array = _data.aqueduct["points"]
	var levels: Vector2 = _data.aqueduct["levels"]
	for index: int in points.size() - 1:
		if index % 10 == 7:
			continue
		var direction: Vector3 = points[index].slerp(points[index + 1], 0.5).normalized()
		var across: Vector3 = points[index].direction_to(points[index + 1]).slide(direction).normalized()
		var heading: Vector3 = -across.cross(direction)
		var level: float = lerpf(levels.x, levels.y, (index + 0.5) / (points.size() - 1))
		var ground: float = _noise.height(direction)
		_add("aqueduct_channel", direction, heading, level - ground)
		if level - ground > 14.0:
			# 高架段扩大为十六米拱跨，拱顶精确接住渠底，不能按近似比例留下悬空间隙。
			if index % 2 != 0 or index % 20 == 6:
				continue
			var a: Vector3 = SurfaceSites.offset_direction(direction, across, -8.0, _noise.radius)
			var b: Vector3 = SurfaceSites.offset_direction(direction, across, 8.0, _noise.radius)
			var base: float = minf(_noise.height(a), _noise.height(b))
			var height: float = level - base
			var size: Vector3 = RuinKit.mesh("arch").get_aabb().size
			_add("arch", direction, heading, base - ground + 0.0001, Vector3(16.0 / size.x, height / size.y, minf(1.0 + height / 20.0, 4.0)))
		elif level - ground > 1.2:
			for course: int in ceili((level - ground) / 4.0):
				_add("aqueduct_pier", direction, heading, course * 4.0 - 0.2, Vector3(1, minf(4.0, level - ground - course * 4.0) / 4.0, 1))


func _roads() -> void:
	for road: Dictionary in _data.roads:
		var points: PackedVector3Array = road["points"]
		for index: int in range(0, points.size() - 1):
			if index % 5 not in [0, 2]:
				continue
			if _rng.randf() < 0.3 or (road["name"] == "old_road" and index > points.size() - 80 and _rng.randf() < (index - points.size() + 80) / 80.0):
				continue
			var heading: Vector3 = points[index].direction_to(points[index + 1]).slide(points[index]).normalized()
			var side: Vector3 = heading.cross(points[index]).normalized()
			var stone: Vector3 = SurfaceSites.offset_direction(points[index], side, 3.0 * (-1 if index % 2 == 0 else 1), _noise.radius)
			if _noise.water_surface(stone) == -INF:
				_add("road_stone", stone, heading, 0, Vector3.ONE, "road")
			if index % 6 == 0 and points[index].distance_to(_data.town["direction"]) * _noise.radius < 300:
				_add("lamp_post_broken" if index % 12 == 0 else "lamp_post", SurfaceSites.offset_direction(points[index], side, -4.0, _noise.radius), heading)
		if road["name"] == "old_road":
			var direction: Vector3 = points[-1]
			_add("lamp_post_broken", direction, SurfaceSites.tangent_forward(direction), 0, Vector3.ONE, "road")


func _fields() -> void:
	for field: Dictionary in _data.terraces:
		var center: Vector3 = field["direction"]
		var along: Vector3 = field["along"]
		var across: Vector3 = field["across"]
		for y: int in range(-30, 31, 2):
			var at: Vector3 = SurfaceSites.offset_direction(center, across, y, _noise.radius)
			var height: float = _noise.height(at)
			var next: Vector3 = SurfaceSites.offset_direction(center, across, y + 2, _noise.radius)
			if floorf(height / 2) == floorf(_noise.height(next) / 2):
				continue
			for x: int in range(-40, 41, 2):
				if _rng.randf() < 0.1:
					continue
				var foot: Vector3 = _point(center, along, across, x, y)
				if not _blocks_road(foot):
					_add("wall_low", foot, across)


func _blocks_road(direction: Vector3) -> bool:
	# 为整块墙体和角色胶囊预留道路缺口，视觉模型与碰撞同时移除。
	var road: Vector4 = _terrain.road_at(direction)
	return road.x < road.z * 0.5 + 1.5


func _retaining_walls() -> void:
	var center: Vector3 = _data.town["direction"]
	var along: Vector3 = _data.town["along"]
	var bank: Vector3 = _data.town["bank"]
	for sector: Dictionary in _data.sectors:
		var radius: float = float(sector["outer"])
		var count: int = ceili(radius * TAU / 12 / 2.0)
		for index: int in count:
			var angle: float = (float(sector["index"]) + (index + 0.5) / count) * TAU / 12
			var heading: Vector3 = along * cos(angle) + bank * sin(angle)
			var foot: Vector3 = SurfaceSites.offset_direction(center, heading, radius - 1.0, _noise.radius)
			var height: float = float(sector["level"]) - _noise.height(foot)
			if height > 0.6 and not _blocks_road(foot):
				_add("wall_low_broken" if _rng.randf() < 0.1 else "wall_low", foot, heading, 0, Vector3(1, height, 1))
		for neighbor: Dictionary in _data.sectors:
			if neighbor["ring"] != sector["ring"] or int(neighbor["index"]) != (int(sector["index"]) + 1) % 12 or float(sector["level"]) - float(neighbor["level"]) <= 0.6:
				continue
			var angle: float = (float(sector["index"]) + 1.0) * TAU / 12
			var heading: Vector3 = along * cos(angle) + bank * sin(angle)
			for radius_value: int in range(int(sector["inner"]) + 4, int(sector["outer"]) - 3, 2):
				var foot: Vector3 = SurfaceSites.offset_direction(center, heading, radius_value, _noise.radius)
				var height: float = float(sector["level"]) - _noise.height(foot)
				if height > 0.6 and not _blocks_road(foot):
					_add("wall_low", foot, heading.cross(foot).normalized(), 0, Vector3(1, height, 1))
