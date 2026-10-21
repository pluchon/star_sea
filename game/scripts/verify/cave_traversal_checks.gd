class_name CaveTraversalChecks
extends RefCounted


static func run(scene: Node3D) -> Dictionary:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var caves: CaveSystem = planet.get_node("CaveSystem") as CaveSystem
	var network: Dictionary = caves.data.networks[0]
	var frame: Transform3D = network["frame"]
	var hall: Vector3 = network["nodes"][4]["position"]
	player.controls_enabled = false
	player.mode = StarSeaPlayer.Mode.WALK
	player.place_at(planet.to_global(hall + frame.basis.y * 8), frame.basis.z, frame.basis.y)
	var deadline: int = Time.get_ticks_msec() + 30000
	while not caves.is_settled() and Time.get_ticks_msec() < deadline:
		await scene.get_tree().process_frame
	player._waiting_for_ground = false
	player.traversal.airborne_time = 1
	player.controls_enabled = true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position, player.global_position - frame.basis.y * 4, 3, [player.get_rid()])
	var clear_below: bool = player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	Input.action_press("jump_up")
	await scene.get_tree().physics_frame
	await scene.get_tree().process_frame
	Input.action_release("jump_up")
	await scene.get_tree().physics_frame
	await scene.get_tree().process_frame
	var cave: int = PlayerTraversal.cave_at(player)
	var blocked: bool = player.mode == StarSeaPlayer.Mode.WALK and cave == 0
	player.set_third_person(true)
	for i: int in 10:
		await scene.get_tree().process_frame
	var relative: Vector3 = planet.to_local(player.camera.global_position)
	var camera_below: bool = relative.length() < planet.surface_radius(relative.normalized()) - 5
	var ship_before: Transform3D = player.ship.global_transform
	player.call_ship()
	var call_rejected: bool = player.ship.global_transform.is_equal_approx(ship_before) and player._message == "洞穴内无法召唤飞船"
	var altitude_zero: bool = is_zero_approx(player.altitude)
	player.controls_enabled = false
	return {"passed": clear_below and blocked and camera_below and call_rejected and altitude_zero, "clear_below_4m": clear_below, "actual_jump_blocked": blocked, "camera_below_surface": camera_below, "air_call_rejected": call_rejected, "altitude_zero": altitude_zero}
