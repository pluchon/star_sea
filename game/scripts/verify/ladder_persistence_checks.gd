class_name LadderPersistenceChecks
extends RefCounted


static func run(scene: Node) -> Dictionary:
	var ladder: SkyLadder = scene.get_node("Universe/PlanetDawn/SkyLadder") as SkyLadder
	var planet: Planet = ladder.get_parent() as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var original: String = "user://verify_lift_original.cfg"
	var path: String = "user://verify_lift.cfg"
	JourneyStore.save(scene, original)
	var state: Dictionary = {"top": false, "target_top": true, "elapsed": 20.0}
	ladder.restore_lift(state)
	var frame: Transform3D = LandingPads.frame(planet)
	player.place_at(planet.to_global(frame * (SkyLadder.LIFT_CENTER + Vector3.UP * 120.05)), -frame.basis.z, frame.basis.y)
	player.mode = StarSeaPlayer.Mode.WALK
	var expected: Vector3 = player.global_position
	var saved: Error = JourneyStore.save(scene, path)
	ladder.restore_lift({})
	player.global_position += frame.basis.y * 100
	var restored: Error = JourneyStore.restore(scene, path)
	var error: float = expected.distance_to(player.global_position)
	var roundtrip: bool = saved == OK and restored == OK and error < 0.01 and ladder.lift_state() == state
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	var invalid: Array = [0, [], {"top": false}, {"top": 0, "target_top": true, "elapsed": 2.0}, {"top": false, "target_top": true, "elapsed": NAN}, {"top": false, "target_top": true, "elapsed": -0.5}, {"top": false, "target_top": true, "elapsed": 41.0}, {"top": true, "target_top": true, "elapsed": 10.0}]
	var rejected: int = 0
	for value: Variant in invalid:
		config.set_value("journey", "ladder_lift", value)
		config.save(path)
		var before: Transform3D = player.global_transform
		var ship: Transform3D = player.ship.global_transform
		var before_state: Dictionary = ladder.lift_state()
		if JourneyStore.restore(scene, path) == ERR_INVALID_DATA and player.global_transform.is_equal_approx(before) and player.ship.global_transform.is_equal_approx(ship) and ladder.lift_state() == before_state:
			rejected += 1
	config.load(original)
	config.erase_section_key("journey", "ladder_lift")
	config.save(path)
	var legacy: bool = JourneyStore.restore(scene, path) == OK and not ladder.lift_top and ladder.lift_elapsed < 0
	JourneyStore.restore(scene, original)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(original))
	return {"passed": roundtrip and legacy and rejected == invalid.size(), "roundtrip": roundtrip, "position_error_m": error, "legacy": legacy, "invalid_rejected": rejected, "invalid_cases": invalid.size()}
