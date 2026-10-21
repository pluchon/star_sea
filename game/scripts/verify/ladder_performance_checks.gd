extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _measure() -> Dictionary:
	var values: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for i: int in 240:
		await process_frame
		var now: int = Time.get_ticks_usec()
		values.append(float(now - previous) / 1000)
		previous = now
	return VerificationMetrics.summarize(values)


func _begin() -> void:
	root.size = Vector2i(1920, 1080)
	root.unfocusable = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("HUD") as CanvasLayer).visible = false
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	player.controls_enabled = false
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	ShotCatalog.place("s43_ladder_base", player, planet, scene.get_node("SkyDirector") as SkyDirector)
	var deadline: int = Time.get_ticks_msec() + 120000
	while not (planet.get_node("Terrain") as PlanetTerrain).is_settled() or not (planet.get_node("SurfaceDetails") as SurfaceDetails).is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("天梯性能检查等待地形超时。")
			quit(1)
			return
	await create_timer(3).timeout
	var active: Dictionary = await _measure()
	var ladder: SkyLadder = planet.get_node("SkyLadder") as SkyLadder
	ladder.visible = false
	if ladder._near != null:
		(ladder._near.get_meta("builder") as Node3D).visible = false
	await create_timer(2).timeout
	var hidden: Dictionary = await _measure()
	var extra: float = float(active["mean"]) - float(hidden["mean"])
	var report: Dictionary = {"passed": extra <= 1.0, "active_ms": active, "hidden_ms": hidden, "extra_ms": extra, "scope": "s43 同机位隔离天梯近远景及基座构件绘制，保留当前地形与更新"}
	VerificationMetrics.write_json("res://../test-output/wanderer/ladder_performance_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for i: int in 8:
		await process_frame
	quit(0 if report["passed"] else 1)
