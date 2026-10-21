class_name EndingChecks
extends RefCounted


static func run(tree: SceneTree, scene: Node) -> Dictionary:
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var ending: EndingDirector = planet.get_node("EndingDirector") as EndingDirector
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var sky: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var failures: Array[String] = []
	echoes.restore_seen(EchoScripts.IDS)
	sky.time_paused = false
	ending._process(5.1)
	if not ending.awakened:
		failures.append("四段回声没有唤醒断口。")
	sky.time_paused = true
	var frame: Transform3D = echoes.anchors["dawn_ending"]
	player.place_at(planet.to_global(frame * Vector3(0, 0.12, 18)), -frame.basis.z, frame.basis.y)
	player.mode = StarSeaPlayer.Mode.WALK
	player.controls_enabled = true
	var deadline: int = Time.get_ticks_msec() + 15000
	while not player.is_on_floor() and Time.get_ticks_msec() < deadline:
		await tree.physics_frame
	var standing: bool = player.is_on_floor()
	var walked: float = 0
	Input.action_press("move_forward")
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await tree.physics_frame
		var at: Vector3 = frame.affine_inverse() * planet.to_local(player.global_position)
		walked = 18 - at.z
		if at.z < 3:
			break
		if absf(at.y) > 1:
			break
	Input.action_release("move_forward")
	for i: int in 30:
		await tree.physics_frame
	var at: Vector3 = frame.affine_inverse() * planet.to_local(player.global_position)
	var bridge_walk: bool = standing and walked >= 15 and player.is_on_floor() and absf(at.y) < 0.3
	if not bridge_walk:
		failures.append("无法实际沿桥面走到终章圆台。")
	sky.time_paused = false
	deadline = Time.get_ticks_msec() + 5000
	while echoes.active != "dawn_ending" and Time.get_ticks_msec() < deadline:
		await tree.physics_frame
	var triggered: bool = echoes.active == "dawn_ending"
	if not triggered:
		failures.append("圆台静止没有触发终章。")
	echoes.frozen = true
	if triggered:
		echoes.show_time(28)
		echoes.finish()
	if ending.points.size() != 40:
		failures.append("终章没有保留四十个光点。")
	player.controls_enabled = false
	player.mode = StarSeaPlayer.Mode.FLY
	var origin: Vector3 = frame.origin
	player.place_at(planet.to_global(origin + ending.light_path * 5000), ending.light_path, origin.normalized())
	player.velocity = ending.light_path * 50
	ending.advance_flight(60.1)
	var began: bool = ending.busy
	var save_blocked: bool = JourneyStore.save(scene, "user://verify_ending_busy.cfg") == ERR_BUSY
	if not began or not save_blocked:
		failures.append("光之路计时或结尾禁止存档失败。")
	ending.finish_credits()
	var resumed: bool = ending.ending_seen and player.mode == StarSeaPlayer.Mode.FLY and not ending.busy
	player.velocity = ending.light_path * 50
	ending.advance_flight(61)
	var once: bool = not ending.busy
	if not resumed or not once:
		failures.append("结尾恢复或单次播放失败。")
	sky.time_paused = true
	return {"passed": failures.is_empty(), "failures": failures, "bridge_walk_m": walked, "bridge_walk": bridge_walk, "end_local": str(at), "triggered": triggered, "points": ending.points.size(), "credits_began": began, "save_blocked": save_blocked, "resumed": resumed, "played_once": once}
