extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("烽火塔性能检查需要真实渲染器。")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	root.unfocusable = true
	root.mouse_passthrough = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("HUD") as CanvasLayer).visible = false
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	player.controls_enabled = false
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	ShotCatalog.place("s36_beacon_chain_night", player, planet, scene.get_node("SkyDirector") as SkyDirector)
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var details: SurfaceDetails = planet.get_node("SurfaceDetails") as SurfaceDetails
	var deadline: int = Time.get_ticks_msec() + 120000
	while not terrain.is_settled() or not details.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("烽火塔性能检查等待地形超时。")
			quit(1)
			return
	await create_timer(2).timeout
	var active: Dictionary = await _measure()
	(planet.get_node("BeaconTowers") as Node3D).visible = false
	await create_timer(2).timeout
	var hidden: Dictionary = await _measure()
	var extra: float = float(active["mean"]) - float(hidden["mean"])
	var report: Dictionary = {"passed": extra <= 1.0, "active_ms": active, "hidden_ms": hidden, "extra_ms": extra, "scope": "s36 同机位隔离塔身、火焰、点光源与光斑绘制；保留当前地形与运行时更新"}
	VerificationMetrics.write_json("res://../test-output/wanderer/beacon_performance_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if report["passed"] else 1)


func _measure() -> Dictionary:
	var values: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for frame: int in 240:
		await process_frame
		var now: int = Time.get_ticks_usec()
		values.append(float(now - previous) / 1000)
		previous = now
	return VerificationMetrics.summarize(values)
