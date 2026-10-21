class_name TraversalShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var forms: DawnLandforms = planet.noise.features.landforms
	var up: Vector3
	var forward: Vector3
	if name == "s56b_boardwalk":
		var zones: ClimbZones = planet.get_node("ClimbZones") as ClimbZones
		var ends: Array[Dictionary] = []
		for zone: Dictionary in zones.zones:
			if String(zone["id"]).begins_with("boardwalk"):
				ends.append(zone)
		var center: Vector3 = (Vector3(ends[0]["top"]) + Vector3(ends[1]["top"])) * 0.5
		up = center.normalized()
		var normal: Vector3 = ends[0]["normal"]
		var side: Vector3 = Vector3(ends[0]["top"]).direction_to(ends[1]["top"])
		var target: Vector3 = center - up * 2.5
		var eye: Vector3 = target + normal * 16.0 + side * 14.0 + up * 7.0
		player.place_at(planet.to_global(eye), -normal, up)
		player.set_third_person(false)
		player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), up)
		director.set_sun_altitude(up, normal, 35.0)
		return
	if name in ["s54_glide_canyon", "s54b_glide_first_person"]:
		up = (planet.get_node("CanyonLandmarks") as CanyonLandmarks).overlook
		var center: Vector3 = forms.canyon[6].slerp(forms.canyon[7], 0.5).normalized()
		forward = up.direction_to(center).slide(up).normalized()
		player.place_at(planet.to_global(up * (planet.surface_radius(up) + 35.0)), forward, up)
		player.mode = StarSeaPlayer.Mode.GLIDE
		player.set_head_pitch(-0.18)
		director.set_sun_altitude(up, forward, 35.0)
	elif name == "s55_glide_range":
		up = forms.ridge[5].slerp(forms.ridge[6], 0.2).normalized()
		forward = up.direction_to(forms.ridge[5]).slide(up).normalized()
		player.place_at(planet.to_global(up * (planet.surface_radius(up) + 90.0)), forward, up)
		player.mode = StarSeaPlayer.Mode.GLIDE
		player.set_head_pitch(-0.05)
		director.set_sun_altitude(up, forward, 5.0)
	else:
		var zones: ClimbZones = planet.get_node("ClimbZones") as ClimbZones
		for zone: Dictionary in zones.zones:
			if zone["id"] != "canyon_route_0":
				continue
			var position: Vector3 = Vector3(zone["bottom"]).lerp(zone["top"], 0.55) + Vector3(zone["normal"]) * 0.45
			up = position.normalized()
			forward = -Vector3(zone["normal"])
			player.place_at(planet.to_global(position), forward, up)
			player.mode = StarSeaPlayer.Mode.CLIMB
			player.traversal.zone = zone
			zone["occupied"] = true
			player.set_head_pitch(0.12)
			director.set_sun_altitude(up, SurfaceSites.tangent_forward(up), 35.0)
			break
	player.set_third_person(name != "s54b_glide_first_person")
