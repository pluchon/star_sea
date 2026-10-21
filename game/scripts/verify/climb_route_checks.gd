extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = player.current_planet()
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var zones: ClimbZones = planet.get_node("ClimbZones") as ClimbZones
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	player.controls_enabled = false
	Engine.time_scale = 6.0
	var reports: Array[Dictionary] = []
	for zone: Dictionary in zones.zones:
		if "--only=canyon" in OS.get_cmdline_user_args() and zone["kind"] != "climb_route":
			continue
		if "--only=boardwalk" in OS.get_cmdline_user_args() and not String(zone["id"]).begins_with("boardwalk"):
			continue
		if zone["id"] == "spawn_vines":
			continue
		var bottom: Vector3 = zone["bottom"]
		var normal: Vector3 = zone["normal"]
		var up: Vector3 = bottom.normalized()
		player.mode = StarSeaPlayer.Mode.WALK
		player.place_at(planet.to_global(bottom + normal * 0.48 + up * 0.05), -normal, up)
		player._waiting_for_ground = false
		player.controls_enabled = false
		# 等待真实地形和地标的碰撞，之后使用正常输入走完整段。
		for frame: int in 20:
			await process_frame
		var deadline: int = Time.get_ticks_msec() + 30000
		while not terrain.is_settled() and Time.get_ticks_msec() < deadline:
			await process_frame
		player.controls_enabled = true
		Input.action_press("move_forward")
		var elapsed: float = 0.0
		var entered: bool = false
		var events: Array[Dictionary] = []
		var previous_mode: int = int(player.mode)
		var limit: float = bottom.distance_to(zone["top"]) / 1.3 + 8.0
		while elapsed < limit:
			await physics_frame
			await process_frame
			elapsed += player.get_physics_process_delta_time()
			entered = entered or player.mode == StarSeaPlayer.Mode.CLIMB
			if previous_mode != int(player.mode):
				events.append({"time_s": elapsed, "mode": int(player.mode), "on_floor": player.is_on_floor(), "exit_error_m": planet.to_local(player.global_position).distance_to(zone["exit_top"])})
				previous_mode = int(player.mode)
			if entered and player.mode == StarSeaPlayer.Mode.WALK:
				Input.action_release("move_forward")
				for frame: int in 8:
					await physics_frame
					await process_frame
				break
		Input.action_release("move_forward")
		player.controls_enabled = false
		var error: float = planet.to_local(player.global_position).distance_to(zone["exit_top"])
		var passed: bool = entered and player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor() and error < 0.5
		if not passed:
			_failures.append(String(zone["id"]) + " 没有完整攀爬并站到出口。")
		var exit: Vector3 = zone["exit_top"]
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(planet.to_global(exit + exit.normalized()), planet.to_global(exit - exit.normalized()), 2)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		reports.append({"id": zone["id"], "passed": passed, "length_m": ClimbZones.length(zone), "duration_s": elapsed, "exit_error_m": error, "on_floor": player.is_on_floor(), "mode": int(player.mode), "mantle_time": player.traversal.mantle_time, "events": events, "exit_floor_hit": not hit.is_empty(), "exit_floor_gap_m": planet.to_local(hit["position"]).distance_to(exit) if not hit.is_empty() else -1.0})
		if not player.traversal.zone.is_empty():
			player.traversal.leave_climb(player)
		player.traversal._reattach_delay = 0.0
	var bypass: Dictionary = {}
	if not "--only=canyon" in OS.get_cmdline_user_args():
		bypass = await _boardwalk_bypass(player, planet, zones)
		if not bypass["passed"]:
			_failures.append("栈道断口无法连续完成下降、下层通行和上攀。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "routes": reports, "boardwalk_bypass": bypass}
	VerificationMetrics.write_json("res://../test-output/wanderer/climb_route_checks.json", report)
	print(JSON.stringify(report))
	Engine.time_scale = 1.0
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _boardwalk_bypass(player: StarSeaPlayer, planet: Planet, zones: ClimbZones) -> Dictionary:
	var ends: Array[Dictionary] = []
	for zone: Dictionary in zones.zones:
		if String(zone["id"]).begins_with("boardwalk"):
			ends.append(zone)
	var first: Dictionary = ends[0]
	var second: Dictionary = ends[1]
	var normal: Vector3 = first["normal"]
	var exit: Vector3 = first["exit_top"]
	player.place_at(planet.to_global(exit), normal, exit.normalized())
	player._waiting_for_ground = false
	player.traversal._reattach_delay = 0.0
	player.controls_enabled = true
	Input.action_press("move_back")
	var descending: bool = false
	var down_finished: bool = false
	for frame: int in 100:
		await physics_frame
		await process_frame
		descending = descending or player.mode == StarSeaPlayer.Mode.CLIMB
		if descending and player.mode == StarSeaPlayer.Mode.WALK:
			down_finished = true
			break
	Input.action_release("move_back")
	for frame: int in 8:
		await physics_frame
		await process_frame
	var destination: Vector3 = Vector3(second["bottom"]) + Vector3(second["normal"]) * 0.48
	var start: Vector3 = planet.to_local(player.global_position)
	var walked: bool = false
	Input.action_press("move_forward")
	for frame: int in 100:
		var here: Vector3 = planet.to_local(player.global_position)
		if here.distance_to(destination) < 0.55:
			walked = true
			break
		player.global_basis = Basis.looking_at(here.direction_to(destination).slide(here.normalized()).normalized(), here.normalized())
		await physics_frame
		await process_frame
	Input.action_release("move_forward")
	var walk_distance: float = start.distance_to(planet.to_local(player.global_position))
	player.global_basis = Basis.looking_at(-Vector3(second["normal"]), destination.normalized())
	Input.action_press("move_forward")
	var ascending: bool = false
	for frame: int in 100:
		await physics_frame
		await process_frame
		ascending = ascending or player.mode == StarSeaPlayer.Mode.CLIMB
		if ascending and player.mode == StarSeaPlayer.Mode.WALK:
			break
	Input.action_release("move_forward")
	for frame: int in 8:
		await physics_frame
		await process_frame
	var error: float = planet.to_local(player.global_position).distance_to(second["exit_top"])
	var passed: bool = down_finished and walked and ascending and player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor() and error < 0.5
	player.controls_enabled = false
	return {"passed": passed, "descended": down_finished, "crossed_lower_bridge": walked, "walk_distance_m": walk_distance, "ascended": ascending, "exit_error_m": error, "on_floor": player.is_on_floor()}
