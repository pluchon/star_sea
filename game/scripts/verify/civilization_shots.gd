class_name CivilizationShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var data: CivilizationData = planet.noise.features.civilization.data
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
