extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("文明绘制开销需要真实渲染器。")
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
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	ShotCatalog.place("s30_town_plaza", player, planet, scene.get_node("SkyDirector") as SkyDirector)
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var details: SurfaceDetails = planet.get_node("SurfaceDetails") as SurfaceDetails
	var deadline: int = Time.get_ticks_msec() + 120000
	while not terrain.is_settled() or not details.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("文明绘制开销等待地形超时。")
			quit(1)
			return
	for frame: int in 120:
		await process_frame
	var fields: Array[MultiMeshInstance3D] = []
	var field_count: int = 0
	for node: Node in details.find_children("*", "MultiMeshInstance3D", true, false):
		var instance: MultiMeshInstance3D = node as MultiMeshInstance3D
		if instance.multimesh.mesh == details._meshes["field_stalks"] and instance.is_visible_in_tree():
			fields.append(instance)
			field_count += instance.multimesh.instance_count
	var city: Node3D = planet.get_node("CivilizationSites") as Node3D
	var climbs: Node3D = planet.get_node("ClimbZones") as Node3D
	var active: Dictionary = await _measure("active")
	for instance: MultiMeshInstance3D in fields:
		instance.visible = false
	var without_fields: Dictionary = await _measure("without_fields")
	city.visible = false
	climbs.visible = false
	var without_both: Dictionary = await _measure("without_both")
	for instance: MultiMeshInstance3D in fields:
		instance.visible = true
	var without_city: Dictionary = await _measure("without_city")
	city.visible = true
	climbs.visible = true
	var extra: float = float(active["frame_ms"]["mean"]) - float(without_both["frame_ms"]["mean"])
	var report: Dictionary = {"passed": extra <= 1.0, "scope": "同一机位隔离文明构件、路面、攀爬外形和稻秆的绘制开销；保留当前地形与清理区", "active": active, "without_fields": without_fields, "without_city": without_city, "without_both": without_both, "render_extra_ms": extra, "field_instances": field_count}
	VerificationMetrics.write_json("res://../test-output/wanderer/civilization_performance_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if report["passed"] else 1)


func _measure(name: String) -> Dictionary:
	await create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../test-output/wanderer/7/profile-" + name + ".png")
	var times: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for frame: int in 240:
		await process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	return {"frame_ms": VerificationMetrics.summarize(times), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
