class_name ShotCatalog
extends RefCounted

const NAMES: Array[String] = ["s1_space", "s2_high", "s3_ground_day", "s4_ground_sunset", "s5_ground_night", "s6_shore", "s7_ember", "s8_frost"]


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	if name == "s7_ember" or name == "s8_frost":
		planet = planet.get_parent().get_node("PlanetEmber" if name == "s7_ember" else "PlanetFrost") as Planet
	var up: Vector3 = planet.site["direction"]
	var forward: Vector3 = planet.site["forward"]
	var height: float = planet.surface_radius(up)
	player.mode = StarSeaPlayer.Mode.FLY
	player.controls_enabled = false
	player.simulated_forward = false
	director.time_paused = true
	match name:
		"s7_ember", "s8_frost":
			player.place_at(planet.global_position + up * (height + 2.0), forward, up)
			director.set_sun_altitude(up, -forward, 25.0)
		"s1_space":
			var giant: Node3D = planet.get_parent().get_node("GasGiant") as Node3D
			var giant_direction: Vector3 = (giant.global_position - planet.global_position).normalized()
			up = (up - giant_direction * 0.6).normalized()
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * 160000.0, forward, up)
			var to_planet: Vector3 = player.camera.global_position.direction_to(planet.global_position)
			var to_giant: Vector3 = player.camera.global_position.direction_to(giant.global_position)
			player.camera.global_basis = Basis.looking_at((to_planet * 0.65 + to_giant * 0.35).normalized(), Vector3.UP)
			var side: Vector3 = up.cross(Vector3.UP).normalized()
			director.sun_direction = (up * 0.5 + side * sqrt(0.75)).normalized()
		"s2_high":
			player.place_at(planet.global_position + up * (height + 12000.0), forward, up)
			player.camera.rotation.x = deg_to_rad(-8.0)
			director.set_sun_altitude(up, -forward, 35.0)
		"s3_ground_day":
			player.place_at(planet.global_position + up * height, forward, up)
			director.set_sun_altitude(up, -forward, 40.0)
		"s4_ground_sunset":
			player.place_at(planet.global_position + up * height, forward, up)
			var right: Vector3 = forward.cross(up).normalized()
			director.set_sun_altitude(up, (-forward + right).normalized(), 3.0)
		"s5_ground_night":
			player.place_at(planet.global_position + up * height, forward, up)
			player.camera.rotation.x = deg_to_rad(35.0)
			director.set_sun_altitude(up, -forward, -30.0)
		"s6_shore":
			up = planet.site["shore_direction"]
			forward = planet.site["shore_forward"]
			player.place_at(planet.global_position + up * planet.surface_radius(up), forward, up)
			director.set_sun_altitude(up, -forward, 25.0)
