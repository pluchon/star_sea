class_name CivilizationShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var data: CivilizationData = planet.noise.features.civilization.data
	if name.begins_with("s35_") or name.begins_with("s36_"):
		beacon_shot(name, player, planet, director, data)
		return
	var center: Vector3 = data.town["direction"]
	var heading: Vector3 = center.direction_to(data.ladder["direction"]).slide(center).normalized()
	var eye: Vector3
	var target: Vector3
	var sun: float = 30.0
	match name:
		"s30_town_plaza":
			var direction: Vector3 = SurfaceSites.offset_direction(center, -heading, 29.0, planet.radius)
			eye = direction * (planet.surface_radius(direction) + 1.7)
			target = center * (planet.surface_radius(center) + 3.0)
			sun = 5.0
		"s31_town_overview":
			eye = center * (planet.surface_radius(center) + 120.0) - heading * 300.0
			target = center * (planet.surface_radius(center) + 5.0)
		"s32_terraces":
			var field: Dictionary = data.terraces[0]
			center = field["direction"]
			heading = field["across"]
			# 从梯田上缘斜看，避免下缘挡土墙遮住全部台阶。
			var direction: Vector3 = SurfaceSites.offset_direction(center, heading, 45.0, planet.radius)
			eye = direction * (planet.surface_radius(direction) + 3.0)
			heading = -heading
			target = center * (planet.surface_radius(center) + 0.5)
		"s33_cemetery":
			center = data.cemetery["direction"]
			heading = data.cemetery["forward"]
			var direction: Vector3 = SurfaceSites.offset_direction(center, -heading, 16.0, planet.radius)
			eye = direction * (planet.surface_radius(direction) + 1.7)
			target = center * (planet.surface_radius(center) + 2.0) + heading * 40.0
			sun = 18.0
		"s34_old_road":
			var road: Dictionary = data.roads[0]
			var points: PackedVector3Array = road["points"]
			var index: int = maxi(points.size() - 45, 1)
			center = points[index]
			heading = center.direction_to(points[index - 1]).slide(center).normalized()
			eye = center * (planet.surface_radius(center) + 1.7)
			target = center * (planet.surface_radius(center) + 1.3) + heading * 50.0
	# place_at 设置脚底，固定机位指定的眼高需要扣除现有头部高度。
	player.place_at(planet.to_global(eye - eye.normalized() * 1.62), heading, eye.normalized())
	player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), eye.normalized())
	director.set_sun_altitude(center, -heading, sun)


static func beacon_shot(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector, data: CivilizationData) -> void:
	var first: Dictionary = data.beacons[0]
	var up: Vector3 = first["direction"]
	var frame: Transform3D = BeaconTowers.tower_frame(first, planet.radius)
	var target: Vector3 = BeaconTowers.tower_frame(data.beacons[1], planet.radius) * Vector3(0, BeaconTowers.TOP + 1, 0)
	var eye: Vector3 = frame * Vector3(2.4, BeaconTowers.TOP + 1.7, 0)
	var heading: Vector3 = up.direction_to(data.beacons[1]["direction"]).slide(up).normalized()
	eye = frame.origin + up * (BeaconTowers.TOP + 1.7) - heading * 2.6 + heading.cross(up) * 0.8
	if name.begins_with("s36_"):
		up = data.town["direction"]
		heading = up.direction_to(first["direction"]).slide(up).normalized()
		target = frame * Vector3(0, BeaconTowers.TOP + 1, 0)
		eye = _beacon_city_eye(planet, data, heading, target)
	player.place_at(planet.to_global(eye - up * 1.62), heading, up)
	player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), up)
	director.set_sun_altitude(up, -heading, -18.0 if name.begins_with("s36_") else 6.0)
	var towers: BeaconTowers = planet.get_node("BeaconTowers") as BeaconTowers
	var values: Array[int] = [0]
	if name.begins_with("s36_"):
		values = [0, 1, 2]
	towers.set_lit(values)


static func _beacon_city_eye(planet: Planet, data: CivilizationData, heading: Vector3, target: Vector3) -> Vector3:
	# 仅为固定自查机位选取真实无遮挡的城边位置，不改变游戏里的深度测试。
	var center: Vector3 = data.town["direction"]
	var blockers: Array[Dictionary] = []
	for placement: Dictionary in data.placements:
		if placement.get("group", "town") in ["road", "monument"]:
			continue
		blockers.append({"inverse": Transform3D(placement["transform"]).affine_inverse(), "bounds": RuinKit.mesh(placement["piece"]).get_aabb()})
	for cell: Vector3i in SurfaceGrid.nearby(center, planet.radius, 900, SurfaceDetails.FOREST_DIVISIONS):
		var generated: Dictionary = SurfaceDetails.generate(planet.noise, Vector4i(SurfaceDetails.FOREST_DIVISIONS, cell.x, cell.y, cell.z), planet.planet_seed, planet.site["direction"])
		for kind: String in ["pine", "broadleaf"]:
			var bounds: AABB = SurfaceDetails.mesh_for_kind(kind).get_aabb()
			for transform_value: Transform3D in generated[kind]:
				transform_value.origin += Vector3(generated["center"])
				blockers.append({"inverse": transform_value.affine_inverse(), "bounds": bounds})
	for radius: float in [80.0, 110.0, 140.0, 180.0, 220.0]:
		for degrees: int in range(-90, 91, 15):
			var direction: Vector3 = SurfaceSites.offset_direction(center, heading.rotated(center, deg_to_rad(degrees)), radius, planet.radius)
			var eye: Vector3 = direction * (planet.surface_radius(direction) + 1.7)
			if not _clear_beacon_ray(planet.noise, eye, target):
				continue
			var blocked: bool = false
			for blocker: Dictionary in blockers:
				var inverse: Transform3D = blocker["inverse"]
				var bounds: AABB = blocker["bounds"]
				if bounds.intersects_segment(inverse * eye, inverse * target) != null:
					blocked = true
					break
			if not blocked:
				return eye
	assert(false, "古城夜景机位没有无遮挡的首塔视线。")
	return center * (planet.surface_radius(center) + 1.7)


static func _clear_beacon_ray(noise: TerrainNoise, eye: Vector3, target: Vector3) -> bool:
	# 城边台地过渡仅数米宽，固定机位必须加密采样，不能沿用塔间五十米采样。
	var steps: int = ceili(eye.distance_to(target) / 2.0)
	for index: int in range(1, steps):
		var point: Vector3 = eye.lerp(target, index / float(steps))
		if point.length() - noise.radius - noise.height(point.normalized()) < 1.0:
			return false
	return true
