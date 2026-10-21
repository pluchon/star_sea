extends SceneTree

const REPORT: String = "res://../test-output/wanderer/traversal_checks.json"
var _failures: Array[String] = []
var _scene: Node3D
var _player: StarSeaPlayer
var _planet: Planet
var _records: Dictionary = {}


func _initialize() -> void:
	_begin.call_deferred()


func _check(condition: bool, text: String) -> void:
	if not condition:
		_failures.append(text)


func _tick() -> float:
	await physics_frame
	await process_frame
	return _player.get_physics_process_delta_time()


func _step(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += await _tick()


func _jump() -> void:
	Input.action_press("jump_up")
	await _tick()
	Input.action_release("jump_up")
	await _tick()


func _place(position: Vector3, forward: Vector3, up: Vector3) -> void:
	_player.mode = StarSeaPlayer.Mode.WALK
	_player.place_at(_planet.to_global(position), forward, up)
	_player._waiting_for_ground = false


func _floor(position: Vector3, up: Vector3, size: float) -> StaticBody3D:
	var floor: StaticBody3D = StaticBody3D.new()
	floor.collision_layer = 1
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size, 0.5, size)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	floor.add_child(shape)
	floor.transform = Transform3D(Basis.looking_at(SurfaceSites.tangent_forward(up), up), position - up * 0.25)
	_planet.add_child(floor)
	return floor


func _until_floor(limit: float) -> float:
	var elapsed: float = 0.0
	while elapsed < limit:
		elapsed += await _tick()
		if _player.is_on_floor():
			return elapsed
	return -1.0


func _begin() -> void:
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	_player = _scene.get_node("Player") as StarSeaPlayer
	_planet = _player.current_planet()
	if "--only=cave" in OS.get_cmdline_user_args():
		var cave: Dictionary = await CaveTraversalChecks.run(_scene)
		var result: Dictionary = {"passed": cave["passed"], "checks": {"cave": cave}}
		VerificationMetrics.write_json(REPORT, result)
		print(JSON.stringify(result))
		_scene.queue_free()
		for i: int in 6:
			await process_frame
		quit(0 if result["passed"] else 1)
		return
	_player.controls_enabled = true
	(_scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	# 物理检查使用真实碰撞和 CharacterBody3D；大平面只隔离随机地形对滑翔比的影响。
	for name: String in ["Terrain", "SurfaceDetails", "Wildlife", "CanyonLandmarks", "UpdraftVisuals"]:
		_planet.get_node(name).process_mode = Node.PROCESS_MODE_DISABLED
	(_scene.get_node("HUD") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 6.0
	var up: Vector3 = _planet.site["direction"]
	var forward: Vector3 = _planet.site["forward"]
	var ground: Vector3 = up * (_planet.surface_radius(up) + 500.0)
	var fixture: StaticBody3D = _floor(ground, up, 4000.0)
	_place(ground + up * 0.05, forward, up)
	await _until_floor(2.0)
	await _jump()
	await _jump()
	var ground_jump_rejected: bool = _player.mode == StarSeaPlayer.Mode.WALK
	_check(ground_jump_rejected, "普通起跳后立即再按跳跃错误地展开了软翼。")
	_place(ground + up * 30.0, forward, up)
	await _step(0.5)
	await _jump()
	_check(_player.mode == StarSeaPlayer.Mode.GLIDE, "从三十米高处下落后没有展开软翼。")
	_records["opening"] = {"ground_jump_rejected": ground_jump_rejected, "high_drop_opened": _player.mode == StarSeaPlayer.Mode.GLIDE}
	_place(ground + up * 300.0, forward, up)
	await _step(0.5)
	await _jump()
	var start: Vector3 = _planet.to_local(_player.global_position)
	Input.action_press("move_forward")
	var glide_seconds: float = await _until_floor(160.0)
	Input.action_release("move_forward")
	var finish: Vector3 = _planet.to_local(_player.global_position)
	var distance: float = (finish - start).slide(up).length()
	_check(glide_seconds > 0.0 and distance >= 900.0 and distance <= 1200.0, "三百米滑翔距离未达到九百至一千二百米。")
	_records["glide"] = {"duration_s": glide_seconds, "horizontal_m": distance, "ratio": distance / 300.0, "landed": _player.is_on_floor()}
	fixture.queue_free()
	await _step(0.3)
	var terrain: PlanetTerrain = _planet.get_node("Terrain") as PlanetTerrain
	terrain.process_mode = Node.PROCESS_MODE_INHERIT
	var actual_ground: Vector3 = up * _planet.surface_radius(up)
	_place(actual_ground + up * 0.05, forward, up)
	_player._waiting_for_ground = true
	await _step(2.0)
	var ready_time: float = 0.0
	while (_player._waiting_for_ground or not _player.is_on_floor()) and ready_time < 30.0:
		ready_time += await _tick()
	_check(_player.is_on_floor(), "二百米下落前没有准备好真实地形碰撞。")
	# 保留已就绪的碰撞；禁用整个分支会让 CollisionObject3D 退出物理世界。
	terrain.set_process(false)
	_place(actual_ground + up * 200.0, forward, up)
	await _step(0.3)
	var fall_seconds: float = 0.0
	var fall_samples: Array[Dictionary] = []
	while fall_seconds < 10.0 and not _player.is_on_floor():
		fall_seconds += await _tick()
		if fall_samples.is_empty() or fall_seconds >= fall_samples.size():
			fall_samples.append({"time_s": fall_seconds, "height_m": (_planet.to_local(_player.global_position) - actual_ground).dot(up), "vertical_m_s": _player.velocity.dot(up), "mode": int(_player.mode), "waiting": _player._waiting_for_ground})
	_check(fall_seconds > 0 and _player.mode == StarSeaPlayer.Mode.WALK and _player.traversal.stumble_left > 0, "二百米下落没有触发步行踉跄。")
	await _step(0.6)
	_check(_player.traversal.stumble_left <= 0, "落地踉跄没有在四百毫秒后结束。")
	_records["fall"] = {"duration_s": fall_seconds, "stumble_finished": _player.traversal.stumble_left <= 0, "samples": fall_samples}
	# 在真实平顶峰上空查询山脊气流，避免坡度变化干扰高度上限检查。
	var ridge: Vector3 = _planet.noise.features.landforms.ridge[8]
	_place(ridge * (_planet.surface_radius(ridge) + 50.0), SurfaceSites.tangent_forward(ridge), ridge)
	await _step(0.5)
	await _jump()
	var maximum: float = 0.0
	var elapsed: float = 0.0
	Input.action_press("move_forward")
	while elapsed < 20.0:
		elapsed += await _tick()
		maximum = maxf(maximum, _player.altitude)
	Input.action_release("move_forward")
	_check(maximum <= 150.0 and _player.mode == StarSeaPlayer.Mode.GLIDE, "山脊气流将玩家送过高度上限，或提前退出滑翔。")
	var outside: Vector3 = _planet.site["direction"]
	_player.place_at(_planet.to_global(outside * (_planet.surface_radius(outside) + 800.0)), forward, outside)
	await _step(1.0)
	_check(_player.velocity.dot(outside) < -2.0, "离开气流后没有恢复下落。")
	_records["updraft"] = {"maximum_altitude_m": maximum, "outside_vertical_m_s": _player.velocity.dot(outside)}
	await _step(0.3)
	var zones: ClimbZones = _planet.get_node("ClimbZones") as ClimbZones
	var vine: Dictionary = {}
	var cliff: Dictionary = {}
	var route_length: float = 0.0
	for zone: Dictionary in zones.zones:
		if zone["id"] == "spawn_vines":
			vine = zone
		if zone["id"] == "canyon_route_0":
			cliff = zone
		if String(zone["id"]).begins_with("canyon_route_"):
			route_length += Vector3(zone["bottom"]).distance_to(zone["top"])
	_check(zones.zones.size() >= 7 and route_length >= 120 and route_length <= 205, "攀爬区数量或峡谷路线长度不符合范围。")
	var normal: Vector3 = vine["normal"]
	var bottom: Vector3 = vine["bottom"]
	var floor: StaticBody3D = _floor(bottom - normal * 0.45, bottom.normalized(), 18.0)
	_place(bottom + normal * 0.5 + bottom.normalized() * 0.05, -normal, bottom.normalized())
	await _step(0.5)
	Input.action_press("move_forward")
	elapsed = 0.0
	var climbed: bool = false
	while elapsed < 12.0:
		elapsed += await _tick()
		climbed = climbed or _player.mode == StarSeaPlayer.Mode.CLIMB
		if climbed and _player.mode == StarSeaPlayer.Mode.WALK and _player.is_on_floor():
			break
	Input.action_release("move_forward")
	var gap: float = _planet.to_local(_player.global_position).distance_to(vine["exit_top"])
	_check(climbed and gap < 0.5 and _player.is_on_floor(), "藤蔓墙翻越后没有站到顶端出口。")
	_records["climb"] = {"entered": climbed, "duration_s": elapsed, "exit_error_m": gap, "on_floor": _player.is_on_floor(), "canyon_route_m": route_length}
	_player.traversal.record_ground(_player)
	var saved_ground: Vector3 = _player.traversal.last_grounded
	var cliff_mid: Vector3 = Vector3(cliff["bottom"]).lerp(cliff["top"], 0.5)
	_place(cliff_mid + Vector3(cliff["normal"]) * 0.45, -Vector3(cliff["normal"]), cliff_mid.normalized())
	_player.mode = StarSeaPlayer.Mode.CLIMB
	_player.traversal.zone = cliff
	cliff["occupied"] = true
	await _jump()
	_check(_player.mode == StarSeaPlayer.Mode.WALK and _player.velocity.dot(cliff["normal"]) > 0.1, "攀爬跳离没有朝外弹开。")
	await _step(0.5)
	await _jump()
	_check(_player.mode == StarSeaPlayer.Mode.GLIDE, "从高处跳离攀爬面后不能展开软翼。")
	var path: String = "user://verify_traversal_journey.cfg"
	var saved: Error = JourneyStore.save(_scene, path)
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	var restored: Error = JourneyStore.restore(_scene, path)
	var saved_position: Vector3 = config.get_value("journey", "position", Vector3.ZERO)
	_check(saved == OK and restored == OK and _player.mode == StarSeaPlayer.Mode.WALK and saved_position.distance_to(saved_ground) < 0.01, "空中存档没有写入最近一次站立的位置。")
	_records["save"] = {"saved": saved == OK, "restored": restored == OK, "ground_error_m": saved_position.distance_to(saved_ground), "mode": int(_player.mode)}
	for invalid: int in [2, 3]:
		config.set_value("journey", "mode", invalid)
		config.save(path)
		var before: Vector3 = _player.global_position
		_check(JourneyStore.restore(_scene, path) == ERR_INVALID_DATA and _player.global_position == before, "非法攀爬或滑翔存档没有整体拒绝。")
	floor.queue_free()
	# 空中召船覆盖真实等待和父节点重挂接，不能只检查计时公式。
	_place(up * (_planet.surface_radius(up) + 5000.0), forward, up)
	await _step(0.5)
	var hold: InputEventAction = InputEventAction.new()
	hold.action = "toggle_fly"
	hold.pressed = true
	_player._unhandled_input(hold)
	await _step(1.3)
	hold.pressed = false
	_player._unhandled_input(hold)
	elapsed = 1.3
	while elapsed < 10.0 and _player.mode != StarSeaPlayer.Mode.FLY:
		elapsed += await _tick()
	_check(_player.mode == StarSeaPlayer.Mode.FLY and _player.ship.get_parent() == _player and elapsed <= 10.0, "空中召船没有在十秒内进入驾驶。")
	_records["air_catch"] = {"duration_s": elapsed, "boarded": _player.mode == StarSeaPlayer.Mode.FLY}
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/explorer/model.json")) as Dictionary
	_check(int(model["triangles"]) <= 8000 and _player.explorer.skeleton.get_bone_count() >= 27, "探索者骨架或三角面预算不符合约定。")
	for name: String in model["animations"]:
		_check(_player.explorer.animation_player.has_animation(name), "探索者缺少动画：" + name)
	_records["cave"] = await CaveTraversalChecks.run(_scene)
	_check(_records["cave"]["passed"], "洞内实际展开限制、相机、海拔或召唤飞船检查失败。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "checks": _records}
	VerificationMetrics.write_json(REPORT, report)
	print(JSON.stringify(report))
	Engine.time_scale = 1.0
	_scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)
