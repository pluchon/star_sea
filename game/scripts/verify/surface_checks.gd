extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var universe: Node3D = scene.get_node("Universe") as Node3D
	director.time_paused = true
	player.controls_enabled = false
	var reports: Array[Dictionary] = []
	var passed: bool = true
	for node: Node in get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
		var up: Vector3 = planet.site["direction"]
		player.mode = StarSeaPlayer.Mode.FLY
		player.simulated_forward = false
		player.place_at(planet.global_position + up * (planet.surface_radius(up) + 0.1), planet.site["forward"], up)
		director.set_sun_altitude(up, -planet.site["forward"], 35.0)
		var deadline: int = Time.get_ticks_msec() + 120000
		for warmup: int in 30:
			await process_frame
		while not terrain.is_settled():
			await process_frame
			if Time.get_ticks_msec() > deadline:
				push_error(planet.planet_name + "的地形生成超时。")
				quit(1)
				return
		player.mode = StarSeaPlayer.Mode.WALK
		player.simulated_forward = true
		var start: Vector3 = player.global_position - universe.global_position
		var minimum: float = INF
		var grounded: int = 0
		for step: int in 480:
			await physics_frame
			var offset: Vector3 = player.global_position - planet.global_position
			minimum = minf(minimum, offset.length() - planet.surface_radius(offset.normalized()))
			if player.is_on_floor():
				grounded += 1
		var distance: float = (player.global_position - universe.global_position).distance_to(start)
		var planet_passed: bool = distance > 25.0 and minimum > -0.3 and grounded > 400
		player.simulated_forward = false
		player.controls_enabled = true
		Input.action_press("jump_up")
		var jump_peak: float = 0.0
		# 初速度为 5 m/s；低重力星球需要更长时间才能完成起跳和落地。
		var jump_frames: int = ceili(10.0 / planet.gravity * 60.0) + 30
		for step: int in jump_frames:
			await physics_frame
			if step == 2:
				Input.action_release("jump_up")
			var offset: Vector3 = player.global_position - planet.global_position
			jump_peak = maxf(jump_peak, offset.length() - planet.surface_radius(offset.normalized()))
		planet_passed = planet_passed and jump_peak > 0.6 and player.is_on_floor()
		player.controls_enabled = false
		passed = passed and planet_passed
		reports.append({"planet": planet.planet_name, "passed": planet_passed, "distance_m": distance, "minimum_altitude_m": minimum, "grounded_frames": grounded, "physics_frames": 480, "jump_peak_m": jump_peak})
	player.simulated_forward = false
	var report: Dictionary = {"passed": passed, "planets": reports}
	VerificationMetrics.write_json("res://../test-output/p2/surface_checks.json", report)
	print(JSON.stringify(report))
	# 无界面固定步长执行很快，退出前留出主循环以回收音频和线程任务。
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)
