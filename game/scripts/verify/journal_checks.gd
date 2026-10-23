extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _begin() -> void:
	root.size = Vector2i(1920, 1080)
	root.unfocusable = true
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var journal: TravelJournal = planet.get_node("TravelJournal") as TravelJournal
	var sky: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var hud: CanvasLayer = scene.get_node("HUD") as CanvasLayer
	sky.time_paused = true
	player.controls_enabled = false
	journal.set_process(false)
	var menu: VoyageMenu = scene.get_node("VoyageMenu") as VoyageMenu
	menu.initialize()
	menu._started = true
	var sites_checked: int = 0
	for id: String in journal.sites:
		if id.begins_with("beacon_") or id == "temple":
			continue
		var frame: Transform3D = journal.sites[id]["frame"]
		var radius: float = journal.sites[id]["radius"]
		journal.discovered.clear()
		player.place_at(planet.to_global(frame.origin + frame.basis.y * (radius + 2)), -frame.basis.z, frame.basis.y)
		journal._process(0.3)
		check(not journal.discovered.has(id), "地点在触发范围外提前发现：" + id)
		player.place_at(planet.to_global(frame.origin), -frame.basis.z, frame.basis.y)
		journal._process(0.3)
		check(journal.discovered.has(id), "进入地点范围没有发现：" + id)
		sites_checked += 1
	journal.cancel_captures()
	journal.discovered.assign(["town", "temple_hall"])
	menu.open()
	menu._journal()
	await process_frame
	var page: JournalPage = menu._journal_page
	var cards: GridContainer = page.find_child("Cards", true, false) as GridContainer
	check(cards != null and cards.get_child_count() == 2, "手记未按已发现地点建立卡片。")
	if cards != null and cards.get_child_count() > 0:
		var card: Node = cards.get_child(0)
		(card.get_child(1) as Button).pressed.emit()
		await process_frame
		check((page._column.get_child(0) as Label).text == "河畔古城", "卡片未打开地点详情。")
		var map_button: Button = page._column.get_child(2) as Button
		map_button.pressed.emit()
		await process_frame
		var atlas: TerrainAtlas = hud.get_node("Layout/TerrainAtlas") as TerrainAtlas
		var expected: Vector2 = TerrainMapData.coordinates(Transform3D(journal.sites["town"]["frame"]).origin.normalized())
		check(atlas.is_open and atlas.global_view.center_uv.distance_to(expected) < 0.0001 and not paused, "详情未打开地图并定位地点。")
		atlas.set_open(false)
	if paused:
		menu.resume()
	player.controls_enabled = false
	hud.visible = true
	if DisplayServer.get_name() != "headless":
		await journal.capture("town")
		var image: Image = Image.load_from_file(journal.image_path("town"))
		check(image != null and image.get_size() == Vector2i(384, 216), "手记截图尺寸不正确。")
		var original: PackedByteArray = FileAccess.get_file_as_bytes(journal.image_path("town"))
		journal.capture("town")
		menu.open()
		await process_frame
		await RenderingServer.frame_post_draw
		check(menu._hud_was_visible and not hud.visible and not journal._capturing, "截图与暂停并发破坏了界面状态。")
		check(FileAccess.get_file_as_bytes(journal.image_path("town")) == original, "暂停菜单写入了地点截图。")
		menu.resume()
		player.controls_enabled = false
		check(hud.visible, "暂停恢复后 HUD 未恢复。")
		var path: String = "user://verify_journal.cfg"
		check(JourneyStore.save(scene, path) == OK, "无法建立临时旅程。")
		journal.capture("town")
		check(JourneyStore.restore(scene, path) == OK, "截图期间读取旅程失败。")
		await process_frame
		await RenderingServer.frame_post_draw
		check(not journal._capturing and journal._capture_queue.is_empty() and hud.visible, "读档没有清理旧截图队列或恢复 HUD。")
		check(FileAccess.get_file_as_bytes(journal.image_path("town")) == original, "读档后旧任务仍然写入截图。")
		DirAccess.remove_absolute(path)
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "sites_checked": sites_checked, "rendered_capture_checks": DisplayServer.get_name() != "headless"}
	VerificationMetrics.write_json("res://../test-output/wanderer/journal_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)
