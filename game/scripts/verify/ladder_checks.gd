class_name LadderChecks
extends RefCounted


static func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	tree.root.add_child(scene)
	tree.current_scene = scene
	tree.root.unfocusable = true
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var ladder: SkyLadder = planet.get_node("SkyLadder") as SkyLadder
	var frame: Transform3D = LandingPads.frame(planet)
	var data: CivilizationData = planet.noise.features.civilization.data
	var up: Vector3 = frame.basis.y
	player.controls_enabled = false
	player.set_third_person(false)
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	var distance: float = Vector3(planet.site["direction"]).angle_to(up) * planet.radius
	var spawn: Vector3 = planet.site["direction"]
	var town: Vector3 = data.town["direction"]
	# 四十公里半径下，现有选址的曲率与山体遮挡下半段；保留已交付文明区，记录调整后的可见高度。
	var spawn_visible: bool = BeaconBake.visible(planet.noise, spawn * (planet.surface_radius(spawn) + 1.7), frame * Vector3(0, 2200, 0))
	var town_visible: bool = BeaconBake.visible(planet.noise, town * (planet.surface_radius(town) + 1.7), frame * Vector3(0, 2400, 0))
	var base_error: float = 0
	for ring: int in 3:
		for angle: int in 16:
			var radius: float = [150.0, 100.0, 40.0][ring]
			var direction: Vector3 = (frame * Vector3(sin(angle * TAU / 16) * radius, -18, cos(angle * TAU / 16) * radius)).normalized()
			base_error = maxf(base_error, absf(planet.noise.height(direction) - float(data.ladder["height"]) - (ring + 1) * 6))
	var nearest_beacon: float = INF
	for beacon: Dictionary in data.beacons:
		nearest_beacon = minf(nearest_beacon, up.distance_to(beacon["direction"]) * planet.radius)
	if distance < 12000 or distance > 25000 or not spawn_visible or not town_visible:
		failures.append("天梯距离或出发地、古城视线检查失败。")
	if base_error > 0.2 or nearest_beacon < 350:
		failures.append("天梯台地高度不一致或与末塔重叠。")
	if ladder.far_triangles > 3000:
		failures.append("天梯远景超过三千三角形。")
	var flight: Dictionary = FlightSafety.sweep(tree, planet.to_global(frame * Vector3(200, 1000, 0)), planet.to_global(frame * Vector3(-200, 1000, 0)))
	var flight_blocked: bool = flight.get("tower", false) and Vector2((frame.affine_inverse() * planet.to_local(flight["position"])).x, (frame.affine_inverse() * planet.to_local(flight["position"])).z).length() >= 36.95
	if not flight_blocked:
		failures.append("飞船穿过天梯主体。")
	player.place_at(planet.to_global(frame * Vector3(200, 1000, 0)), -frame.basis.x, up)
	player.mode = StarSeaPlayer.Mode.FLY
	player.advance_flight(-frame.basis.x * 1000, 1)
	var stopped: bool = player.velocity.length() < 0.1 and Vector2(ladder.to_local(player.global_position).x, ladder.to_local(player.global_position).z).length() >= 36.95
	if not stopped:
		failures.append("实际飞行撞塔后没有停止向塔内的速度。")
	player.mode = StarSeaPlayer.Mode.WALK
	player.place_at(planet.to_global(frame * (SkyLadder.LIFT_CENTER + Vector3.UP * 0.08)), -frame.basis.z, up)
	var deadline: int = Time.get_ticks_msec() + 60000
	while ladder.lift == null or not (planet.get_node("Terrain") as PlanetTerrain).is_settled():
		await tree.process_frame
		if Time.get_ticks_msec() > deadline:
			failures.append("天梯近景加载超时。")
			break
	player.controls_enabled = true
	Engine.time_scale = 4
	var floor_frames: int = 0
	var total_frames: int = 0
	var trips: int = 0
	var previous_top: bool = false
	var elapsed: float = 0
	var maximum_rider_gap: float = 0
	var walk_phase: int = 0
	var walk_time: float = 0
	var balcony_exit: bool = false
	var walk_events: Array[Dictionary] = []
	while elapsed < 110 and trips < 2:
		await tree.physics_frame
		elapsed += player.get_physics_process_delta_time()
		if ladder.lift_elapsed >= 0:
			total_frames += 1
			var rider_gap: float = absf(ladder.to_local(player.global_position).y - ladder.lift.position.y)
			maximum_rider_gap = maxf(maximum_rider_gap, rider_gap)
			floor_frames += int(player.is_on_floor() and rider_gap < 1)
		if ladder.lift_top != previous_top:
			trips += 1
			previous_top = ladder.lift_top
			if trips == 1:
				walk_phase = 1
				walk_time = 0
				Input.action_press("move_forward")
		if walk_phase > 0:
			walk_time += player.get_physics_process_delta_time()
			if walk_phase == 1 and ladder.to_local(player.global_position).z <= -35:
				balcony_exit = ladder.to_local(player.global_position).z < -32 and absf(ladder.to_local(player.global_position).y - 240) < 0.3 and player.is_on_floor()
				walk_events.append({"phase": "exit", "position": str(ladder.to_local(player.global_position)), "on_floor": player.is_on_floor()})
				Input.action_release("move_forward")
				Input.action_press("move_back")
				walk_phase = 2
				walk_time = 0
			elif walk_phase == 2 and ladder.to_local(player.global_position).z >= -22:
				Input.action_release("move_back")
				walk_events.append({"phase": "return", "position": str(ladder.to_local(player.global_position)), "on_floor": player.is_on_floor()})
				walk_phase = 0
	var floor_ratio: float = float(floor_frames) / maxi(1, total_frames)
	Input.action_release("move_forward")
	Input.action_release("move_back")
	if trips != 2 or floor_ratio < 0.95 or not balcony_exit:
		failures.append("升降台上下行未完成或角色站立比例不足百分之九十五。")
	Engine.time_scale = 1
	player.controls_enabled = false
	var persistence: Dictionary = LadderPersistenceChecks.run(scene)
	if not persistence["passed"]:
		failures.append("升降台行程存档未能往返或非法值没有整体拒绝。")
	var pad_center: Vector3 = frame * Vector3(0, LandingPads.HEIGHT, -54)
	player.place_at(planet.to_global(pad_center + up * 30), -frame.basis.z, up)
	player.mode = StarSeaPlayer.Mode.FLY
	player.ship.attach_to(player)
	for i: int in 30:
		await tree.process_frame
	await player.land()
	player.controls_enabled = true
	for i: int in 40:
		await tree.physics_frame
		await tree.process_frame
	var pad_error: float = planet.to_local(player.ship.global_position).distance_to(pad_center + up * StarSeaShip.FOOT_HEIGHT)
	var pad_standing: bool = player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor()
	if pad_error > 0.2 or not pad_standing:
		failures.append("断口平台降落或下船站立失败。")
	player.place_at(planet.to_global(frame * Vector3(0, 5000, -100)), -frame.basis.z, up)
	player.mode = StarSeaPlayer.Mode.WALK
	player._waiting_for_ground = false
	player.velocity = -up * 10
	player.altitude = 5000
	player.traversal.airborne_time = 2
	# place_at 不清除上一物理帧的地面状态，必须先真实下落再调用空中召唤。
	for i: int in 3:
		await tree.physics_frame
		await tree.process_frame
	player.call_ship()
	var catch_time: float = 0
	while player.mode != StarSeaPlayer.Mode.FLY and catch_time < 10:
		await tree.physics_frame
		await tree.process_frame
		catch_time += player.get_physics_process_delta_time()
	var caught: bool = player.mode == StarSeaPlayer.Mode.FLY
	if not caught:
		failures.append("断口下方空中召唤未在十秒内进入驾驶。")
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "spawn_distance_m": distance, "spawn_visible": spawn_visible, "town_visible": town_visible, "base_error_m": base_error, "nearest_beacon_m": nearest_beacon, "far_triangles": ladder.far_triangles, "flight_blocked": flight_blocked, "lift_trips": trips, "lift_floor_ratio": floor_ratio, "lift_elapsed_s": elapsed, "pad_ship_error_m": pad_error, "pad_standing": pad_standing, "air_caught": caught, "air_catch_s": catch_time}
	report["spawn_visible_height_m"] = 2200
	report["town_visible_height_m"] = 2400
	report["balcony_walk_exit"] = balcony_exit
	report["actual_flight_stopped"] = stopped
	report["balcony_walk_events"] = walk_events
	report["persistence"] = persistence
	report["maximum_rider_gap_m"] = maximum_rider_gap
	var ending: Dictionary = await EndingChecks.run(tree, scene)
	report["ending"] = ending
	if not ending["passed"]:
		failures.append_array(ending["failures"])
	report["passed"] = failures.is_empty()
	scene.queue_free()
	for i: int in 8:
		await tree.process_frame
	return report
