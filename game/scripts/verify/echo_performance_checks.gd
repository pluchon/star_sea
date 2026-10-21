extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func measure() -> Dictionary:
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
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("HUD") as CanvasLayer).visible = false
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	ShotCatalog.place("s46b_echo_departure", scene.get_node("Player") as StarSeaPlayer, planet, scene.get_node("SkyDirector") as SkyDirector)
	(planet.get_node("EchoSystem") as EchoSystem).show_time(4.5)
	var deadline: int = Time.get_ticks_msec() + 120000
	while not (planet.get_node("Terrain") as PlanetTerrain).is_settled() or not (planet.get_node("SurfaceDetails") as SurfaceDetails).is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			quit(1)
			return
	await create_timer(3).timeout
	var active: Dictionary = await measure()
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	echoes.visible = false
	await create_timer(2).timeout
	var hidden: Dictionary = await measure()
	var extra: float = float(active["mean"]) - float(hidden["mean"])
	var report: Dictionary = {"passed": extra <= 1, "extra_ms": extra, "active": active, "hidden": hidden, "actors": 13, "scope": "主门十三个人影与粒子的同机位显示和隐藏比较；保留天梯、基座与地形"}
	VerificationMetrics.write_json("res://../test-output/wanderer/echo_performance_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if report["passed"] else 1)
