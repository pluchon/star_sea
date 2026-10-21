class_name CaveShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var network: Dictionary = planet.noise.features.caves.networks[0]
	var frame: Transform3D = network["frame"]
	var eye: Vector3
	var target: Vector3
	if name == "s37_temple_gate":
		var direction: Vector3 = (frame * Vector3(5, 0, -7)).normalized()
		eye = direction * (planet.surface_radius(direction) + 1.7)
		target = frame * Vector3(0, 4, 0)
	else:
		var hall: Vector3 = network["nodes"][4]["local"]
		eye = frame * (hall + Vector3(8, 1.7, -8))
		target = frame * (hall + Vector3(0, 6, 5))
	player.place_at(planet.to_global(eye - frame.basis.y * 1.62), frame.basis.z, frame.basis.y)
	player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), frame.basis.y)
	director.set_sun_altitude(frame.basis.y, -frame.basis.z, 35 if name == "s37_temple_gate" else 75)
