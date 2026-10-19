class_name ShotCatalog
extends RefCounted

const NAMES: Array[String] = ["s1_space", "s2_high", "s3_ground_day", "s4_ground_sunset", "s5_ground_night", "s6_shore", "s7_ember", "s8_frost", "s9_woodland", "s10_highland", "s11_orbit", "s12_ruin", "s13_tree_detail"]


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
		"s12_ruin":
			var ruin_up: Vector3 = SurfaceSites.ruin_direction(planet.site, planet.radius)
			var ruin_position: Vector3 = planet.global_position + ruin_up * (planet.surface_radius(ruin_up) - 0.3)
			var eye_up: Vector3 = SurfaceSites.offset_direction(ruin_up, forward, 9.0, planet.radius)
			var eye: Vector3 = planet.global_position + eye_up * (planet.surface_radius(eye_up) + 1.0)
			player.place_at(eye, -forward, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(ruin_position + ruin_up * 2.6), eye_up)
			director.set_sun_altitude(ruin_up, (forward + forward.cross(ruin_up)).normalized(), 35.0)
		"s13_tree_detail":
			var cells: Array[Vector3i] = SurfaceGrid.nearby(up, planet.radius, 200.0, SurfaceDetails.FOREST_DIVISIONS)
			var target: Vector3 = Vector3.ZERO
			var closest: float = INF
			var origin: Vector3 = up * planet.surface_radius(up)
			for cell: Vector3i in cells:
				var generated: Dictionary = SurfaceDetails.generate(planet.noise, Vector4i(SurfaceDetails.FOREST_DIVISIONS, cell.x, cell.y, cell.z), planet.planet_seed, up, SurfaceSites.ruin_direction(planet.site, planet.radius))
				for transform: Transform3D in generated["broadleaf"]:
					var position: Vector3 = (generated["center"] as Vector3) + transform.origin
					if position.distance_to(origin) < closest:
						closest = position.distance_to(origin)
						target = position
			assert(target != Vector3.ZERO, "树木近景机位缺少阔叶树。")
			up = target.normalized()
			var eye_up: Vector3 = SurfaceSites.offset_direction(up, forward, 11.0, planet.radius)
			player.place_at(planet.global_position + eye_up * (planet.surface_radius(eye_up) + 1.0), -forward, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.global_position + target + up * 4.5), eye_up)
			director.set_sun_altitude(up, (forward + forward.cross(up)).normalized(), 38.0)
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
		"s9_woodland":
			up = SurfaceSites.find_woodland(planet.noise, up)
			forward = SurfaceSites.tangent_forward(up)
			var best_height: float = -INF
			var reference: Vector3 = forward
			for heading: int in 16:
				var tangent: Vector3 = reference.rotated(up, heading * TAU / 16.0)
				var inland_height: float = planet.noise.height(SurfaceSites.offset_direction(up, tangent, 150.0, planet.radius))
				if inland_height > best_height:
					best_height = inland_height
					forward = tangent
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 1.0), forward, up)
			director.set_sun_altitude(up, (-forward + forward.cross(up)).normalized(), 28.0)
		"s10_highland":
			up = planet.site["mountain_direction"]
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 180.0), forward, up)
			player.camera.rotation.x = deg_to_rad(-18.0)
			director.set_sun_altitude(up, forward.cross(up).normalized(), 22.0)
		"s11_orbit":
			up = -up
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * (planet.radius + 80000.0), forward, up)
			player.camera.global_basis = Basis.looking_at(-up, forward)
			director.set_sun_altitude(up, forward, 12.0)
		"s6_shore":
			up = planet.site["shore_direction"]
			forward = planet.site["shore_forward"]
			player.place_at(planet.global_position + up * planet.surface_radius(up), forward, up)
			director.set_sun_altitude(up, -forward, 25.0)
