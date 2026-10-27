class_name MainlineBot
extends RefCounted

var context: VersionContext
var segments: Array[Dictionary] = []
var failure: Dictionary = {}
var _last_progress_ms: int = 0


static func run(owner: VersionContext) -> Dictionary:
	var bot: MainlineBot = MainlineBot.new()
	bot.context = owner
	return await bot._run()


func _run() -> Dictionary:
	context.director.time_paused = false
	context.player.controls_enabled = false
	if not await context.settle():
		return {"passed": false, "error": "新旅程加载超时"}
	context.player.controls_enabled = true
	for tick: int in 30:
		await context.tree.physics_frame
	var data: CivilizationData = context.planet.noise.features.civilization.data
	_progress("new_journey", context.local_position(), 0)
	var ship: StarSeaShip = context.player.ship
	# 新实例本身就是新旅程。之后不调用 place_at、不设置进度字段。
	if not await _move("walk_to_ship", context.planet.to_local(ship.global_position), StarSeaShip.BOARD_RANGE - 0.7):
		return await _report()
	if not await _toggle("board", true):
		return await _report()
	if not await _fly_land("town", data.echo_anchors["dawn_daily"].origin):
		return await _report()
	if not await _echo("dawn_daily", data.echo_anchors["dawn_daily"].origin):
		return await _report()
	var cave: Dictionary = context.planet.noise.features.caves.networks[0]
	var temple_road: Dictionary = {}
	var closest: float = INF
	for road: Dictionary in data.roads:
		var points: PackedVector3Array = road["points"]
		var gap: float = VersionContext.surface(context.planet.noise, points[-1]).distance_to(Transform3D(cave["frame"]).origin)
		if gap < closest:
			closest = gap
			temple_road = road
	if not temple_road.is_empty():
		for index: int in (temple_road["points"] as PackedVector3Array).size():
			if not await _move("temple_road_%d" % index, VersionContext.surface(context.planet.noise, temple_road["points"][index]), 2):
				return await _report()
	if not await _move("walk_to_temple", Transform3D(cave["frame"]).origin, 2):
		return await _report()
	for edge: Dictionary in cave["edges"]:
		if int(edge["a"]) > 3 or int(edge["b"]) > 4:
			continue
		for point: Dictionary in edge["map_points"]:
			if not await _move("cave_" + str(point["id"]), point["position"], 1.0):
				return await _report()
	if not await _echo("dawn_faith", data.echo_anchors["dawn_faith"].origin):
		return await _report()
	for edge_index: int in range(3, -1, -1):
		var points: Array = cave["edges"][edge_index]["map_points"].duplicate()
		points.reverse()
		for point: Dictionary in points:
			if not await _move("return_" + str(point["id"]), point["position"], 1.0):
				return await _report()
	for tower: Dictionary in data.beacons:
		var frame: Transform3D = BeaconTowers.tower_frame(tower, context.planet.radius)
		if not await _fly_land("beacon_%d" % tower["id"], frame * Vector3(0, 0, -9)):
			return await _report()
		# 塔阶由六段旋转四分之一圈的构件组成，目标沿实际阶面布置。
		for step: int in 73:
			var angle: float = float(step) / 12 * PI / 2
			var at: Vector3 = Vector3(cos(angle) * 3.9, float(step) / 4, -sin(angle) * 3.9)
			if step in [27, 72] and context.player.is_on_floor():
				Input.action_press("jump_up")
				for tick: int in 2:
					await context.tree.physics_frame
				Input.action_release("jump_up")
			if not await _move("tower_stair_%d_%d" % [tower["id"], step], frame * at, 0.7):
				return await _report()
		if not await _move("tower_top_%d" % tower["id"], frame * Vector3(0, BeaconTowers.TOP, 0), 1.5):
			return await _report()
		await context.tree.create_timer(3).timeout
	if not await _echo("dawn_watcher", data.echo_anchors["dawn_watcher"].origin):
		return await _report()
	if not await _fly_land("ladder", data.echo_anchors["dawn_departure"].origin):
		return await _report()
	if not await _echo("dawn_departure", data.echo_anchors["dawn_departure"].origin):
		return await _report()
	var frame: Transform3D = LandingPads.frame(context.planet)
	if not await _move("lift_board", frame * SkyLadder.LIFT_CENTER, 2):
		return await _report()
	var ladder: SkyLadder = context.planet.get_node("SkyLadder") as SkyLadder
	var lift_start: int = Time.get_ticks_msec()
	while not ladder.lift_top and Time.get_ticks_msec() - lift_start < 90000:
		await context.tree.physics_frame
	if not ladder.lift_top:
		failure = {"segment": "lift", "reason": "升降台 90 秒内未到达"}
		return await _report()
	segments.append({"name": "lift", "duration_s": float(Time.get_ticks_msec() - lift_start) / 1000, "passed": true})
	if not await _move("ring", frame * Vector3(0, LandingPads.balcony_height(context.planet), -55), 2):
		return await _report()
	if not await _fly_land("break", frame * Vector3(0, LandingPads.HEIGHT, -LandingPads.DOCK_OFFSET)):
		return await _report()
	if not await _echo("dawn_ending", data.echo_anchors["dawn_ending"].origin):
		return await _report()
	if not await _board_nearby():
		return await _report()
	var ending: EndingDirector = context.planet.get_node("EndingDirector") as EndingDirector
	for point: Vector3 in ending.points:
		if not await _move("light_path", point, 12):
			return await _report()
	var deadline: int = Time.get_ticks_msec() + 120000
	while not ending.ending_seen or ending.busy:
		await context.tree.process_frame
		if Time.get_ticks_msec() > deadline:
			failure = {"segment": "credits", "reason": "字幕结束或控制恢复超时"}
			break
	return await _report()


func _board_nearby() -> bool:
	if context.player.mode == StarSeaPlayer.Mode.FLY:
		return true
	var held: InputEventAction = InputEventAction.new()
	held.action = "toggle_fly"
	held.pressed = true
	context.player._unhandled_input(held)
	await context.tree.create_timer(StarSeaShip.HOLD_TIME + 0.3).timeout
	held.pressed = false
	context.player._unhandled_input(held)
	await context.tree.create_timer(4).timeout
	var ship: StarSeaShip = context.player.ship
	if not await _move("walk_to_called_ship", context.planet.to_local(ship.global_position), StarSeaShip.BOARD_RANGE - 0.7):
		return false
	return await _toggle("board", true)


func _fly_land(id: String, target: Vector3) -> bool:
	if not await _board_nearby():
		return false
	var landing_target: Vector3 = target
	var pad: Dictionary = LandingPads.near(context.planet, target)
	if pad.is_empty():
		var candidate: Transform3D = _landing_site(target)
		if not candidate.origin.is_finite():
			failure = {"segment": id + "_landing_site", "reason": "游戏自身的降落检查没有找到可用地点", "target": target}
			return false
		landing_target = candidate.origin
	else:
		landing_target = pad["center"]
	var at: Vector3 = context.local_position()
	if not await _move(id + "_ascend", at.normalized() * (at.length() + 500), 20):
		return false
	if not await _move(id + "_cruise", landing_target + landing_target.normalized() * 500, 30):
		return false
	if not await _move(id + "_approach", landing_target + landing_target.normalized() * 12, 3):
		return false
	await context.tree.create_timer(2).timeout
	return await _toggle(id + "_land", false)


func _landing_site(target: Vector3) -> Transform3D:
	var up: Vector3 = target.normalized()
	var forward: Vector3 = SurfaceSites.tangent_forward(up)
	for distance: float in [30.0, 45.0, 65.0, 90.0, 120.0]:
		for bearing: int in 24:
			var direction: Vector3 = SurfaceSites.offset_direction(up, forward.rotated(up, bearing * TAU / 24), distance, context.planet.radius)
			if not StarSeaShip.can_land(context.planet, direction).is_empty():
				continue
			var safe: bool = true
			for side: int in 8:
				var neighbor: Vector3 = SurfaceSites.offset_direction(direction, SurfaceSites.tangent_forward(direction).rotated(direction, side * TAU / 8), 5, context.planet.radius)
				safe = safe and StarSeaShip.can_land(context.planet, neighbor).is_empty()
			if safe:
				return StarSeaShip.landing_transform(context.planet, direction, forward)
	return Transform3D(Basis.IDENTITY, Vector3.INF)


func _toggle(id: String, flying: bool) -> bool:
	var start: int = Time.get_ticks_msec()
	var event: InputEventAction = InputEventAction.new()
	event.action = "toggle_fly"
	event.pressed = true
	context.player._unhandled_input(event)
	for tick: int in 4:
		await context.tree.physics_frame
	event.pressed = false
	context.player._unhandled_input(event)
	await context.tree.process_frame
	var message: String = context.player.interaction_hint()
	await context.tree.create_timer(4).timeout
	var passed: bool = (context.player.mode == StarSeaPlayer.Mode.FLY) == flying and not context.player.transition_busy
	segments.append({"name": id, "passed": passed, "duration_s": float(Time.get_ticks_msec() - start) / 1000})
	if not passed:
		failure = {"segment": id, "reason": "真实登船或降落输入未完成转换", "message": message, "position": context.local_position(), "altitude_m": context.player.altitude, "velocity_m_s": context.player.velocity.length()}
	return passed


func _move(id: String, target: Vector3, tolerance: float) -> bool:
	var start: int = Time.get_ticks_msec()
	var progress_at: int = start
	var best: float = INF
	while true:
		var at: Vector3 = context.local_position()
		var up: Vector3 = at.normalized()
		var offset: Vector3 = target - at
		var flying: bool = context.player.mode == StarSeaPlayer.Mode.FLY
		var gap: float = offset.length() if flying else offset.slide(up).length()
		var height_gap: float = absf(offset.dot(up))
		_progress(id, target, gap)
		# 登塔不能只在水平方向接近目标；必须实际走到对应阶面高度。
		if gap <= tolerance and (flying or height_gap <= maxf(tolerance, 1.2)):
			Input.action_release("move_forward")
			segments.append({"name": id, "passed": true, "duration_s": float(Time.get_ticks_msec() - start) / 1000, "finish": at})
			return true
		var progress_gap: float = offset.length()
		if progress_gap < best - 0.5:
			best = progress_gap
			progress_at = Time.get_ticks_msec()
		if Time.get_ticks_msec() - progress_at >= 10000 or Time.get_ticks_msec() - start >= 1800000:
			Input.action_release("move_forward")
			failure = {"segment": id, "reason": "10 秒没有向目标前进" if Time.get_ticks_msec() - progress_at >= 10000 else "段落总超时", "position": at, "target": target, "remaining_m": gap, "height_gap_m": height_gap}
			return false
		var heading: Vector3 = offset.normalized() if flying else offset.slide(up).normalized()
		if flying:
			var horizontal: Vector3 = heading.slide(up)
			if horizontal.length_squared() < 0.00001:
				horizontal = SurfaceSites.tangent_forward(up)
			context.player.global_basis = Basis.looking_at(horizontal.normalized(), up)
			context.player.set_head_pitch(asin(clampf(heading.dot(up), -0.999, 0.999)))
		else:
			heading = _steer(heading, up)
			context.player.global_basis = Basis.looking_at(heading, up)
			context.player.set_head_pitch(0)
		# 近目标采用短脉冲，避免高速飞行反复越过目标。
		if flying and gap < context.player.velocity.length() * 0.5:
			Input.action_release("move_forward")
		else:
			Input.action_press("move_forward")
		await context.tree.physics_frame
	return false


func _steer(heading: Vector3, up: Vector3) -> Vector3:
	var from: Vector3 = context.player.global_position + up * 0.8
	for angle: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var direction: Vector3 = heading.rotated(up, deg_to_rad(angle))
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + direction * 2, context.player.collision_mask, [context.player.get_rid()])
		if context.player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return direction
	return heading


func _echo(id: String, target: Vector3) -> bool:
	if not await _move(id, target, 1.5):
		return false
	var echoes: EchoSystem = context.planet.get_node("EchoSystem") as EchoSystem
	var start: int = Time.get_ticks_msec()
	var duration: float = float(EchoScripts.script_for(id)["duration"]) + 15
	while not echoes.seen.has(id) or not echoes.active.is_empty():
		await context.tree.process_frame
		if Time.get_ticks_msec() - start > duration * 1000:
			failure = {"segment": id, "reason": "回声未自然触发并播放完成"}
			return false
	segments.append({"name": id + "_watch", "passed": true, "duration_s": float(Time.get_ticks_msec() - start) / 1000})
	return true


func _report() -> Dictionary:
	Input.action_release("move_forward")
	var save_path: String = context.output.path_join("mainline-journey.cfg")
	var save_error: Error = JourneyStore.save(context.scene, save_path)
	var config: ConfigFile = ConfigFile.new()
	var loaded: bool = config.load(save_path) == OK
	var echoes: Array = config.get_value("journey", "echoes_seen", []) if loaded else []
	var beacons: Array = config.get_value("journey", "beacons_lit", []) if loaded else []
	var journal: Array = config.get_value("journey", "discovered", []) if loaded else []
	var ending: bool = config.get_value("journey", "ending_seen", false) if loaded else false
	var fields_passed: bool = EchoScripts.IDS.all(func(id: String) -> bool: return echoes.has(id)) and echoes.has("dawn_ending") and beacons.size() == context.planet.noise.features.civilization.data.beacons.size() and ["town", "temple_hall", "ladder_base", "ladder_balcony", "ladder_break"].all(func(id: String) -> bool: return journal.has(id)) and ending and context.player.controls_enabled
	if not failure.is_empty():
		failure["screenshot"] = await context.capture("mainline-failure")
	return {"passed": failure.is_empty() and save_error == OK and fields_passed, "single_process": true, "process_id": OS.get_process_id(), "direct_position_changes": 0, "segments": segments, "failure": failure, "save_error": save_error, "save_fields_passed": fields_passed, "echoes": echoes, "beacons": beacons, "journal": journal, "ending": ending}


func _progress(id: String, target: Vector3, gap: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_progress_ms < 2000:
		return
	_last_progress_ms = now
	VerificationMetrics.write_json(context.output.path_join("mainline-progress.json"), {"status": "running", "process_id": OS.get_process_id(), "segment": id, "position": context.local_position(), "target": target, "remaining_m": gap, "segments": segments, "updated_at": Time.get_datetime_string_from_system()})
