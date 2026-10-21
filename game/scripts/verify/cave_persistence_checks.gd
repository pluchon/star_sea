class_name CavePersistenceChecks
extends RefCounted


static func run(scene: Node) -> Dictionary:
	var caves: CaveSystem = scene.get_node("Universe/PlanetDawn/CaveSystem") as CaveSystem
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = caves.get_parent() as Planet
	var original: Array[String] = caves.seen.duplicate()
	var original_position: Vector3 = player.global_position
	var original_mode: int = player.mode
	var hall: Vector3 = caves.data.networks[0]["nodes"][4]["position"]
	player.place_at(planet.to_global(hall + hall.normalized() * 0.2), SurfaceSites.tangent_forward(hall.normalized()), hall.normalized())
	player.mode = StarSeaPlayer.Mode.WALK
	caves.seen = ["0:gate", "0:hall"]
	var path: String = "user://verify_caves.cfg"
	var saved: Error = JourneyStore.save(scene, path)
	var expected: Vector3 = planet.to_local(player.global_position)
	caves.seen.clear()
	player.global_position += hall.normalized() * 100
	var restored: Error = JourneyStore.restore(scene, path)
	var error: float = expected.distance_to(planet.to_local(player.global_position))
	var roundtrip: bool = saved == OK and restored == OK and caves.seen == ["0:gate", "0:hall"] and error < 0.01
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	var invalid: Array = ["0:gate", [0], ["0:unknown"], ["9:gate"], ["0:gate", "0:gate"], [false]]
	var rejected: int = 0
	for value: Variant in invalid:
		config.set_value("journey", "caves_seen", value)
		config.save(path)
		var before: Transform3D = player.global_transform
		var ship: Transform3D = player.ship.global_transform
		var beacons: BeaconTowers = planet.get_node("BeaconTowers") as BeaconTowers
		var lit: Array[int] = beacons.lit.duplicate()
		var seen: Array[String] = caves.seen.duplicate()
		if JourneyStore.restore(scene, path) == ERR_INVALID_DATA and player.global_transform.is_equal_approx(before) and player.ship.global_transform.is_equal_approx(ship) and caves.seen == seen and beacons.lit == lit:
			rejected += 1
	config.erase_section_key("journey", "caves_seen")
	config.save(path)
	var legacy: bool = JourneyStore.restore(scene, path) == OK and caves.seen.is_empty()
	caves.seen = original
	player.global_position = original_position
	player.mode = original_mode as StarSeaPlayer.Mode
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"passed": roundtrip and legacy and rejected == invalid.size(), "roundtrip": roundtrip, "underground_position_error_m": error, "legacy": legacy, "invalid_rejected": rejected, "invalid_cases": invalid.size()}
