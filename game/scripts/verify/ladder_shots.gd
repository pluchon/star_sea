class_name LadderShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	player.mode = StarSeaPlayer.Mode.FLY
	player.controls_enabled = false
	player.simulated_forward = false
	player.set_third_person(false)
	director.time_paused = true
	var frame: Transform3D = LandingPads.frame(planet)
	var up: Vector3 = frame.basis.y
	var eye: Vector3
	var target: Vector3
	match name:
		"s41_ladder_from_spawn", "s42_ladder_night":
			var direction: Vector3 = planet.site["direction"]
			eye = direction * (planet.surface_radius(direction) + 1.7)
			target = frame * Vector3(0, 3100, 0)
			up = direction
		"s43_ladder_base":
			eye = frame * Vector3(30, 1.7, -120)
			target = frame * Vector3(0, 70, 0)
		"s44_ladder_balcony":
			var town: Vector3 = planet.noise.features.civilization.data.town["direction"]
			target = town * (planet.radius + planet.noise.height(town))
			var local_town: Vector3 = frame.affine_inverse() * target
			eye = frame * (Vector3(local_town.x, 0, local_town.z).normalized() * 59.0 + Vector3.UP * (LandingPads.balcony_height(planet) + 1.62))
		"s45_ladder_from_orbit":
			eye = frame * Vector3(9000, 18000, -15000)
			target = frame * Vector3(0, 2800, 0)
		"s60b_ladder_view":
			# 停泊台加宽后移到实际外缘，避免俯视机位只拍到脚下石板。
			eye = frame * Vector3(0, LandingPads.HEIGHT + 1.7, -LandingPads.DOCK_OFFSET - 20)
			target = frame * Vector3(0, 0, -4500)
		_:
			var bridge: Vector3 = (planet.get_node("SkyLadder") as SkyLadder).bridge_direction
			eye = frame * (bridge.rotated(Vector3.UP, PI / 2) * 85 - bridge * 8 + Vector3.UP * (LandingPads.HEIGHT + 12))
			target = frame * (bridge * LandingPads.DOCK_OFFSET + Vector3.UP * (LandingPads.HEIGHT + 8))
	player.place_at(planet.to_global(eye - up * 1.62), frame.basis.z, up)
	player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), up)
	director.set_sun_altitude(up, SurfaceSites.tangent_forward(up), -18 if name == "s42_ladder_night" else (12 if name in ["s43_ladder_base", "s60_ladder_break"] else 40))
