extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://../test-output/wanderer/11/" + name + ".png")


func _begin() -> void:
	root.size = Vector2i(1920, 1080)
	root.unfocusable = true
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("HUD") as CanvasLayer).visible = false
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var ending: EndingDirector = planet.get_node("EndingDirector") as EndingDirector
	var sky: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	ShotCatalog.place("s61_light_path", player, planet, sky)
	await create_timer(4).timeout
	ending.set_process(false)
	ending.begin_credits()
	ending._process(7.9)
	await shot("ending_stars")
	ending._process(2)
	await shot("ending_title")
	ending._process(6)
	await shot("ending_maker")
	var menu: VoyageMenu = VoyageMenu.new()
	menu.name = "EndingMenuCheck"
	scene.add_child(menu)
	menu.initialize()
	menu._started = true
	menu.open()
	var disabled: bool = (menu._pages.get_node("SaveJourney") as Button).disabled
	await shot("ending_pause")
	menu.resume()
	var protected: bool = not player.controls_enabled
	ending._process(8)
	await shot("ending_restored")
	var flare: MeshInstance3D = ending._flares[-1]
	var distance: float = flare.global_position.distance_to(player.camera.global_position)
	var pixels: float = flare.scale.x / (distance * 2 * tan(deg_to_rad(player.camera.fov) * 0.5)) * root.size.y
	var report: Dictionary = {"passed": disabled and protected and ending.ending_seen and not ending.busy and pixels < 17, "pause_save_disabled": disabled, "pause_resume_controls_protected": protected, "ending_seen": ending.ending_seen, "returned_mode": player.mode, "nearest_flare_width_px": pixels}
	VerificationMetrics.write_json("res://../test-output/wanderer/ending_visual_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if report["passed"] else 1)
