extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.unfocusable = true
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	player.controls_enabled = false
	var planet: Planet = player.current_planet()
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	var ship: StarSeaShip = player.ship
	var parked: Transform3D = ship.transform
	_check(ship.state == StarSeaShip.State.PARKED and ship.get_parent() == planet, "新旅程飞船没有停在星球上。")
	_check(StarSeaShip.can_land(planet, parked.origin.normalized()).is_empty(), "开局飞船停放点不符合降落条件。")
	var up: Vector3 = parked.origin.normalized()
	player.place_at(planet.to_global(parked.origin - parked.basis.x * 4.0), -parked.basis.z, up)
	player.mode = StarSeaPlayer.Mode.WALK
	player.controls_enabled = true
	await _wait_for_floor(player)
	_key(player, true)
	for frame: int in 4:
		await physics_frame
	_key(player, false)
	await create_timer(1.2).timeout
	player.controls_enabled = false
	_check(player.mode == StarSeaPlayer.Mode.FLY and ship.state == StarSeaShip.State.CARRIED and ship.get_parent() == player, "登船状态或父节点不正确。")
	player.place_at(planet.to_global(up * (planet.surface_radius(up) + 12.0)), -parked.basis.z, up)
	var landing_forward: Vector3 = -parked.basis.z
	player.velocity = landing_forward * 6.0
	await physics_frame
	var landing_start: Vector3 = player.global_position
	player.land()
	await physics_frame
	paused = true
	var paused_position: Vector3 = player.global_position
	await create_timer(0.2, true).timeout
	_check(player.global_position == paused_position and player.transition_busy, "暂停期间降落仍在移动。")
	paused = false
	var previous_progress: float = 0.0
	while player.transition_busy:
		await physics_frame
		var forward_progress: float = (player.global_position - landing_start).dot(landing_forward)
		_check(forward_progress >= previous_progress - 0.04, "减速降落过程中发生反向回退。")
		previous_progress = forward_progress
	await physics_frame
	_check(player.mode == StarSeaPlayer.Mode.WALK and ship.state == StarSeaShip.State.PARKED, "降落没有完成。")
	var exit_distance: float = player.global_position.distance_to(ship.global_position)
	_check(exit_distance >= 3.0 and exit_distance <= 6.0, "下船位置不在舱门外 3～6 米。")
	_check(not (ship.body.get_child(0) as CollisionShape3D).disabled, "停放飞船缺少有效碰撞。")
	var water_rejections: int = 0
	var slope_rejections: int = 0
	for index: int in 500:
		var direction: Vector3 = Vector3(sin(index * 2.39996), cos(index * 1.31), sin(index * 0.71)).normalized()
		var ground: float = planet.noise.height(direction)
		if ground < 0.0 and not StarSeaShip.can_land(planet, direction).is_empty():
			water_rejections += 1
		if ground > 1.0 and planet.noise.slope(direction, ground) > 0.9 and not StarSeaShip.can_land(planet, direction).is_empty():
			slope_rejections += 1
	_check(water_rejections > 10 and slope_rejections > 0, "水面或陡坡拒绝检查没有覆盖有效样本。")
	var path: String = "user://verify_ship.cfg"
	var roundtrips: int = 0
	for riding: bool in [false, true]:
		if riding:
			player.mode = StarSeaPlayer.Mode.FLY
		else:
			player.mode = StarSeaPlayer.Mode.WALK
			ship.park(planet, parked)
		var saved: Error = JourneyStore.save(scene, path)
		var restored: Error = JourneyStore.restore(scene, path)
		if saved == OK and restored == OK and (player.mode == StarSeaPlayer.Mode.FLY) == riding:
			roundtrips += 1
	_check(roundtrips == 2, "驾驶或停放存档往返失败。")
	player.mode = StarSeaPlayer.Mode.WALK
	ship.park(planet, parked)
	var destination: Transform3D = Transform3D(Basis.IDENTITY, Vector3.INF)
	for angle: int in 24:
		var direction: Vector3 = SurfaceSites.offset_direction(up, SurfaceSites.tangent_forward(up).rotated(up, angle * TAU / 24.0), 3000.0, planet.radius)
		destination = StarSeaShip.find_landing(planet, direction, SurfaceSites.tangent_forward(direction))
		if destination.origin.is_finite():
			break
	_check(destination.origin.is_finite(), "3 公里召唤测试找不到落点。")
	var summon_elapsed: float = 0.0
	if destination.origin.is_finite():
		var destination_up: Vector3 = destination.origin.normalized()
		player.place_at(planet.to_global(destination_up * (planet.surface_radius(destination_up) + 0.05)), SurfaceSites.tangent_forward(destination_up), destination_up)
		player.controls_enabled = true
		await _wait_for_floor(player)
		_key(player, true)
		player._process(0.8)
		_check(ship.state == StarSeaShip.State.PARKED, "召唤在长按阈值之前触发。")
		player._process(0.41)
		_key(player, false)
		player.controls_enabled = false
		_check(ship.state == StarSeaShip.State.CALLED, "召唤未能进入飞行状态。")
		ship.set_process(false)
		JourneyStore.save(scene, path)
		while ship.state == StarSeaShip.State.CALLED and summon_elapsed < 40.0:
			ship._process(1.0 / 60.0)
			summon_elapsed += 1.0 / 60.0
		_check(summon_elapsed >= 19.0 and summon_elapsed <= 29.0, "3 公里召唤耗时超出预期。")
		var summon_gap: float = ship.global_position.distance_to(player.global_position)
		_check(summon_gap >= 14.0 and summon_gap <= 41.0, "召唤落点距离不符合要求。")
		_check(JourneyStore.restore(scene, path) == OK and ship.state == StarSeaShip.State.PARKED, "召唤途中存档没有按已到达目标点恢复。")
	var config: ConfigFile = ConfigFile.new()
	JourneyStore.save(scene, path)
	config.load(path)
	var invalid_rejected: int = 0
	for record: Array in [["boarded", 1], ["ship_planet_seed", -99], ["ship_position", Vector3.INF], ["ship_forward", Vector3.ZERO], ["ship_up", "bad"]]:
		var original: Variant = config.get_value("journey", record[0])
		config.set_value("journey", record[0], record[1])
		config.save(path)
		var before: Transform3D = player.global_transform
		var ship_before: Transform3D = ship.transform
		if JourneyStore.restore(scene, path) == ERR_INVALID_DATA and before == player.global_transform and ship_before == ship.transform:
			invalid_rejected += 1
		config.set_value("journey", record[0], original)
	_check(invalid_rejected == 5, "非法飞船字段未能完整拒绝或修改了世界状态。")
	for field: String in ["boarded", "ship_planet_seed", "ship_position", "ship_up", "ship_forward"]:
		config.erase_section_key("journey", field)
	config.save(path)
	_check(JourneyStore.restore(scene, path) == OK and ship.state == StarSeaShip.State.PARKED, "旧步行存档没有补建飞船。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DisplayServer.get_name() != "headless":
		await _record_audio(scene, player)
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "exit_distance_m": exit_distance, "water_rejections": water_rejections, "slope_rejections": slope_rejections, "roundtrips": roundtrips, "invalid_rejected": invalid_rejected, "summon_duration_s": summon_elapsed}
	VerificationMetrics.write_json("res://../test-output/wanderer/ship_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _wait_for_floor(player: StarSeaPlayer) -> void:
	var deadline: int = Time.get_ticks_msec() + 30000
	while not player.is_on_floor() and Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
	_check(player.is_on_floor(), "登船或地面召唤前没有等到实际站立。")


func _key(player: StarSeaPlayer, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = pressed
	player._unhandled_input(event)


func _record_audio(scene: Node3D, player: StarSeaPlayer) -> void:
	var sound: Soundscape = scene.get_node("Soundscape") as Soundscape
	sound.set_process(false)
	for node: Node in sound.get_children():
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
	var waters: InlandWaters = scene.get_node("Universe/PlanetDawn/InlandWaters") as InlandWaters
	waters.set_process(false)
	for node: Node in scene.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	var effect: AudioEffectRecord = AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, effect)
	var directory: String = ProjectSettings.globalize_path("res://../test-output/wanderer/audio")
	DirAccess.make_dir_recursive_absolute(directory)
	for kind: String in ["engine", "ship_land", "ship_hatch"]:
		player.mode = StarSeaPlayer.Mode.FLY
		player.ship.engine.stop()
		player.ship.effect.stop()
		await create_timer(0.15).timeout
		effect.set_recording_active(true)
		if kind == "engine":
			player.ship.engine.play()
		else:
			player.ship.play_effect(kind)
		await create_timer(2.0).timeout
		if kind == "engine":
			_check(player.ship.engine.playing and player.ship.engine.get_playback_position() > 0.1, "引擎播放器没有实际推进音频。")
		effect.set_recording_active(false)
		player.ship.engine.stop()
		var recording: AudioStreamWAV = effect.get_recording()
		_check(recording.save_to_wav(directory.path_join(kind + ".wav")) == OK and recording.get_length() > 1.8, kind + " 实际混音录制失败。")
	AudioServer.remove_bus_effect(0, effect_index)
