extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	root.unfocusable = true
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	player.controls_enabled = false
	var sky: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	sky.time_paused = true
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	var journal: TravelJournal = planet.get_node("TravelJournal") as TravelJournal
	var ending: EndingDirector = planet.get_node("EndingDirector") as EndingDirector
	var persistence: Dictionary = EchoPersistenceChecks.run(scene)
	check(persistence["passed"], "新增存档字段校验或往返失败。")
	var animation_records: Array[Dictionary] = []
	for child: bool in [false, true]:
		var figure: EchoFigure = EchoFigure.new()
		planet.add_child(figure)
		figure.build(child)
		var missing: Array[String] = []
		for pose: String in ["stand", "walk", "kneel", "sit", "raise", "carry", "paint", "child_run", "old_walk", "place"]:
			figure.set_pose(pose, 1)
			if figure.pose != pose:
				missing.append(pose)
		animation_records.append({"child": child, "missing": missing, "clips": figure.animation.get_animation_list() if figure.animation != null else []})
		check(missing.is_empty(), "蒙皮模型缺少动作。")
		figure.queue_free()
	var max_distance: float = 0
	var script_records: Array[Dictionary] = []
	for id: String in EchoScripts.IDS + ["dawn_ending"]:
		var script: Dictionary = EchoScripts.script_for(id)
		var timing_valid: bool = true
		var distance: float = 0
		for actor: Dictionary in script["actors"]:
			timing_valid = timing_valid and float(actor["start"]) >= 0 and float(actor["end"]) <= float(script["duration"])
			for at: Vector3 in actor["path"]:
				distance = maxf(distance, at.length())
		max_distance = maxf(max_distance, distance)
		# 终章包含走入六米触发圆台之前的一段桥面。
		check(timing_valid and distance <= (18 if id == "dawn_ending" else float(script["radius"])), "回声脚本超出时间或站位边界：" + id)
		script_records.append({"id": id, "duration_s": script["duration"], "actors": script["actors"].size(), "maximum_path_distance_m": distance})
	# 实际地面碰撞和静止触发，禁止通过手工设置 is_on_floor 伪造条件。
	var frame: Transform3D = echoes.anchors["dawn_daily"]
	player.place_at(planet.to_global(frame * Vector3(5, 0.2, 5)), -frame.basis.z, frame.basis.y)
	player.mode = StarSeaPlayer.Mode.WALK
	player.controls_enabled = true
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 120000 and not player.is_on_floor():
		await physics_frame
	var grounded: bool = player.is_on_floor()
	check(grounded, "广场真实地面未就绪。")
	sky.time_paused = false
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000 and echoes.active.is_empty():
		await physics_frame
	var triggered: bool = echoes.active == "dawn_daily"
	check(triggered, "静止两秒未触发广场回声。")
	if triggered:
		echoes.frozen = true
		echoes.show_time(11)
		echoes.finish()
	check(echoes.seen.has("dawn_daily"), "回声结束后未记录。")
	var towers: BeaconTowers = planet.get_node("BeaconTowers") as BeaconTowers
	towers.set_lit([])
	check(not echoes.eligible("dawn_watcher"), "未点亮末塔时守望者可以触发。")
	towers.set_lit([towers.towers.size() - 1])
	check(echoes.eligible("dawn_watcher"), "点亮末塔后守望者不能触发。")
	echoes.frozen = false
	player.place_at(planet.to_global(frame * Vector3(20, 0.2, 0)), -frame.basis.z, frame.basis.y)
	await create_timer(3.2).timeout
	player.place_at(planet.to_global(frame * Vector3(5, 0.2, 5)), -frame.basis.z, frame.basis.y)
	await create_timer(2.5).timeout
	var before_repeat: bool = echoes.active.is_empty()
	await create_timer(1.0).timeout
	var repeated: bool = echoes.active == "dawn_daily"
	check(before_repeat and repeated, "重看没有遵守离开后返回静止三秒。")
	player.place_at(planet.to_global(frame * Vector3(35, 0.2, 0)), -frame.basis.z, frame.basis.y)
	await create_timer(2.3).timeout
	var early_finished: bool = echoes.active.is_empty() and echoes.seen.has("dawn_daily")
	check(early_finished, "提前离开没有淡出并记录回声。")
	player.controls_enabled = false
	sky.time_paused = true
	journal.discover("town", false)
	check(journal.discovered.has("town"), "地点未发现。")
	if DisplayServer.get_name() != "headless":
		await journal.capture("town")
		var image: Image = Image.load_from_file("user://journal/town.png")
		check(image != null and image.get_size() == Vector2i(384, 216), "旅行截图未生成。")
	for missing: String in EchoScripts.IDS:
		echoes.seen.assign(EchoScripts.IDS)
		echoes.seen.erase(missing)
		check(not ending.all_seen(), "缺少回声仍满足结局。")
	echoes.seen.assign(EchoScripts.IDS)
	sky.time_paused = false
	ending._process(5.1)
	sky.time_paused = true
	check(ending.awakened, "四个回声完成后断口未唤醒。")
	echoes.frozen = true
	echoes.begin("dawn_ending")
	echoes.show_time(23)
	echoes.finish()
	check(ending.points.size() == 40 and ending.light_path.length() > 0.99, "终章未建立光之路。")
	if ending.points.is_empty():
		var failed: Dictionary = {"passed": false, "failures": _failures}
		VerificationMetrics.write_json("res://../test-output/wanderer/echo_checks.json", failed)
		print(JSON.stringify(failed))
		quit(1)
		return
	check(ending.points[-1].length() - planet.radius >= planet.atmosphere_height + 28000, "光之路未伸出大气层约三十公里。")
	var origin: Vector3 = Transform3D(echoes.anchors["dawn_ending"]).origin
	player.place_at(planet.to_global(origin + ending.light_path * 5000), ending.light_path, origin.normalized())
	player.mode = StarSeaPlayer.Mode.FLY
	player.velocity = ending.light_path * 50
	for i: int in 600:
		ending.advance_flight(0.1)
	ending.advance_flight(0.1)
	check(ending.busy, "沿光之路累计六十秒未开始结尾。")
	check(JourneyStore.save(scene, "user://verify_busy.cfg") == ERR_BUSY, "结尾期间允许存档。")
	ending.finish_credits()
	check(ending.ending_seen and player.mode == StarSeaPlayer.Mode.FLY and not ending.busy, "字幕后未恢复驾驶。")
	player.velocity = ending.light_path * 50
	ending.advance_flight(61)
	check(not ending.busy, "结局重复触发。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "persistence": persistence, "animations": animation_records, "scripts": script_records, "grounded": grounded, "triggered": triggered, "repeat_three_seconds": before_repeat and repeated, "early_fade_finished": early_finished, "path_points": ending.points.size(), "last_altitude_m": ending.points[-1].length() - planet.radius, "path_direction": str(ending.light_path)}
	VerificationMetrics.write_json("res://../test-output/wanderer/echo_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)


func check(passed: bool, message: String) -> void:
	if not passed:
		_failures.append(message)
