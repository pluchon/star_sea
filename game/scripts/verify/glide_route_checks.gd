extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = player.current_planet()
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var forms: DawnLandforms = planet.noise.features.landforms
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	(scene.get_node("HUD") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 6.0
	var canyon: Vector3 = (planet.get_node("CanyonLandmarks") as CanyonLandmarks).overlook
	var middle: Vector3 = forms.canyon[6].slerp(forms.canyon[7], 0.5).normalized()
	var pass_site: Dictionary = forms.metadata["passes"][1]
	var launches: Array[Dictionary] = [
		{"name": "峡谷观景台上方", "up": canyon, "forward": canyon.direction_to(middle).slide(canyon).normalized(), "height": 35.0},
		{"name": "山口上方", "up": pass_site["direction"], "forward": pass_site["across"], "height": 300.0},
	]
	var results: Array[Dictionary] = []
	var failures: Array[String] = []
	for launch: Dictionary in launches:
		player.controls_enabled = false
		player.mode = StarSeaPlayer.Mode.FLY
		var up: Vector3 = launch["up"]
		player.place_at(planet.to_global(up * (planet.surface_radius(up) + float(launch["height"]))), launch["forward"], up)
		for frame: int in 30:
			await process_frame
		var deadline: int = Time.get_ticks_msec() + 30000
		while not terrain.is_settled() and Time.get_ticks_msec() < deadline:
			await process_frame
		player.traversal.start_glide(player, up)
		player.controls_enabled = true
		player._waiting_for_ground = false
		Input.action_press("move_forward")
		var previous: Vector3 = planet.to_local(player.global_position)
		var elapsed: float = 0.0
		var distance: float = 0.0
		var minimum: float = INF
		while elapsed < 600.0 and player.mode == StarSeaPlayer.Mode.GLIDE:
			await physics_frame
			await process_frame
			elapsed += player.get_physics_process_delta_time()
			var location: Vector3 = planet.to_local(player.global_position)
			distance += (location - previous).slide(previous.normalized()).length()
			minimum = minf(minimum, location.length() - planet.surface_radius(location.normalized()))
			previous = location
		Input.action_release("move_forward")
		player.controls_enabled = false
		var ended: bool = player.mode == StarSeaPlayer.Mode.WALK
		if not ended or distance < 10.0 or minimum < -0.5:
			failures.append(String(launch["name"]) + "的实际滑翔没有正常结束，或穿过地表。")
		results.append({"name": launch["name"], "launch_above_ground_m": launch["height"], "horizontal_m": distance, "duration_s": elapsed, "ended": ended, "on_floor": player.is_on_floor(), "minimum_clearance_m": minimum})
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "routes": results}
	VerificationMetrics.write_json("res://../test-output/wanderer/glide_route_checks.json", report)
	print(JSON.stringify(report))
	Engine.time_scale = 1.0
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if failures.is_empty() else 1)
