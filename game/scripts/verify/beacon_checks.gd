class_name BeaconChecks
extends RefCounted


static func run(tree: SceneTree, noise: TerrainNoise) -> Dictionary:
	var failures: Array[String] = []
	var towers: Array[Dictionary] = noise.features.civilization.data.beacons
	if towers.size() < 6 or towers.size() > 10:
		return {"passed": false, "failures": ["烽火塔数量不在六至十座之间。"]}
	var links: Array[Dictionary] = []
	var pass_count: int = 0
	var base_error: float = 0.0
	for index: int in towers.size():
		var tower: Dictionary = towers[index]
		for angle: int in 8:
			var point: Vector3 = SurfaceSites.offset_direction(tower["direction"], SurfaceSites.tangent_forward(tower["direction"]).rotated(tower["direction"], angle * TAU / 8), 6.0, noise.radius)
			base_error = maxf(base_error, absf(noise.height(point) - float(tower["height"])))
		pass_count += int(tower["mountain_pass"])
		if tower["id"] != index or int(tower["next"]) != (index + 1 if index + 1 < towers.size() else -1):
			failures.append("烽火塔编号或下一座连接不连续。")
		if index + 1 < towers.size():
			var a: Vector3 = tower["direction"]
			var b: Vector3 = towers[index + 1]["direction"]
			var distance: float = a.angle_to(b) * noise.radius
			var clear: bool = BeaconBake.visible(noise, a * (noise.radius + float(tower["height"]) + 20), b * (noise.radius + float(towers[index + 1]["height"]) + 20))
			links.append({"from": index, "to": index + 1, "distance_m": distance, "visible": clear})
			if not clear or distance < 1999 or distance > 6001:
				failures.append("相邻烽火塔距离或通视不满足要求。")
	if pass_count != 1:
		failures.append("塔链没有经过唯一的山口塔。")
	if base_error > 0.1:
		failures.append("烽火塔基六米范围没有保持平整，或后续道路改变了塔基高度。")
	var stair: Dictionary = await _stairs(tree, noise)
	if not stair["passed"]:
		failures.append("实际角色未能在山口塔完成登顶、断口跳跃和下行。")
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	tree.root.add_child(scene)
	tree.current_scene = scene
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var beacons: BeaconTowers = planet.get_node("BeaconTowers") as BeaconTowers
	(scene.get_node("SkyDirector") as SkyDirector).time_paused = true
	# controls_enabled=false 会暂停整段玩家物理；实际站立检查必须启用正常物理。
	tree.root.unfocusable = true
	player.controls_enabled = true
	var frame: Transform3D = BeaconTowers.tower_frame(towers[0], noise.radius)
	var foot: Vector3 = frame * Vector3(2.0, BeaconTowers.TOP + 0.05, 0)
	player.place_at(planet.to_global(foot), -frame.basis.z, frame.basis.y)
	await tree.create_timer(1.0).timeout
	# 首次接近先等实际碰撞建立，然后从平台重新站稳，验证真实脚底接触而非注入触发。
	beacons.set_lit([])
	player.place_at(planet.to_global(foot), -frame.basis.z, frame.basis.y)
	await tree.create_timer(1.6).timeout
	var ignited: bool = beacons.lit.has(0) and player.is_on_floor()
	var standing: Dictionary = {"on_floor": player.is_on_floor(), "waiting_for_ground": player._waiting_for_ground, "position_in_tower": str(frame.affine_inverse() * planet.to_local(player.global_position)), "mode": player.mode}
	await tree.create_timer(2.1).timeout
	var response: bool = beacons.responding(1)
	if not ignited or not response:
		failures.append("塔顶实际站立点亮或下一座延时回应失败。")
	var persistence_report: Dictionary = persistence(scene)
	if not persistence_report["passed"]:
		failures.append("烽火塔存档往返、旧存档或非法数据整体拒绝失败。")
	var fov: float = player.camera.fov
	var size_value: float = BeaconTowers.flare_size(5000, fov, 1080)
	var pixels: float = size_value / (10000.0 * tan(deg_to_rad(fov) * 0.5)) * 1080
	if pixels < 6 or pixels > 40:
		failures.append("五公里远景光斑尺寸不在六至四十像素之间。")
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/beacons/tower_far.json")) as Dictionary
	if int(model["triangles"]) > 200:
		failures.append("烽火塔远景超过两百个三角形。")
	scene.queue_free()
	for count: int in 6:
		await tree.process_frame
	return {"passed": failures.is_empty(), "failures": failures, "towers": towers.size(), "links": links, "base_error_m": base_error, "stairs": stair, "actual_standing_ignited": ignited, "standing": standing, "next_responded": response, "persistence": persistence_report, "flare_pixels_at_5km": pixels, "far_model": model}


static func persistence(scene: Node) -> Dictionary:
	var beacons: BeaconTowers = scene.get_node_or_null("Universe/PlanetDawn/BeaconTowers") as BeaconTowers
	if beacons == null or beacons.towers.size() < 3:
		return {"passed": false, "reason": "没有可测试的塔链。"}
	var original: Array[int] = beacons.lit.duplicate()
	var path: String = "user://verify_beacons.cfg"
	beacons.set_lit([0, 2])
	var saved: Error = JourneyStore.save(scene, path)
	beacons.set_lit([])
	var roundtrip: bool = saved == OK and JourneyStore.restore(scene, path) == OK and beacons.lit == [0, 2]
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var invalid: Array = ["0", [false], [0.0], [-1], [beacons.towers.size()], [0, 0], ["1"]]
	var rejected: int = 0
	for value: Variant in invalid:
		config.set_value("journey", "beacons_lit", value)
		config.save(path)
		beacons.set_lit([1])
		var before: Transform3D = player.global_transform
		var ship_before: Transform3D = player.ship.global_transform
		if JourneyStore.restore(scene, path) == ERR_INVALID_DATA and beacons.lit == [1] and player.global_transform.is_equal_approx(before) and player.ship.global_transform.is_equal_approx(ship_before):
			rejected += 1
	config.erase_section_key("journey", "beacons_lit")
	config.save(path)
	var legacy: bool = JourneyStore.restore(scene, path) == OK and beacons.lit.is_empty()
	beacons.set_lit(original)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"passed": roundtrip and legacy and rejected == invalid.size(), "roundtrip": roundtrip, "legacy": legacy, "invalid_rejected": rejected, "invalid_cases": invalid.size()}


static func _stairs(tree: SceneTree, noise: TerrainNoise) -> Dictionary:
	var scene: Node3D = Node3D.new()
	tree.root.add_child(scene)
	var body: StaticBody3D = StaticBody3D.new()
	var ground: CollisionShape3D = CollisionShape3D.new()
	var tower: Dictionary = {}
	for candidate: Dictionary in noise.features.civilization.data.beacons:
		if candidate["mountain_pass"]:
			tower = candidate
	var frame: Transform3D = BeaconTowers.tower_frame(tower, noise.radius)
	var inverse: Transform3D = frame.affine_inverse()
	# 在山口塔实际地面上建立碰撞，不能用平板代替重新选址后的塔基连接。
	var faces: PackedVector3Array = []
	for x: int in range(-8, 8):
		for z: int in range(-8, 8):
			var corners: PackedVector3Array = []
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var direction: Vector3 = (frame * Vector3((x + offset.x) * 4, 0, (z + offset.y) * 4)).normalized()
				corners.append(inverse * (direction * (noise.radius + noise.height(direction))))
			for index: int in [0, 2, 1, 0, 3, 2]:
				faces.append(corners[index])
	var terrain_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	terrain_shape.set_faces(faces)
	ground.shape = terrain_shape
	body.add_child(ground)
	for placement: Dictionary in BeaconTowers.pieces(tower, noise.radius):
		if not placement.get("collision", true):
			continue
		for record: Dictionary in RuinKit.collision_records(placement["piece"]):
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = record["shape"]
			collision.transform = inverse * Transform3D(placement["transform"]) * Transform3D(record["transform"])
			body.add_child(collision)
	scene.add_child(body)
	var actor: CharacterBody3D = CharacterBody3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.3
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.875
	actor.add_child(shape)
	actor.position = Vector3(3.9, 0.06, 0)
	actor.floor_snap_length = 0.3
	scene.add_child(actor)
	var progress: float = 0.0
	var jumped: bool = false
	var entry_jump: bool = false
	var reached: bool = false
	var maximum_height: float = 0
	var elapsed: float = 0
	for count: int in 2400:
		await tree.physics_frame
		var delta: float = actor.get_physics_process_delta_time()
		elapsed += delta
		var angle: float = atan2(-actor.position.z, actor.position.x)
		while angle < progress - PI:
			angle += TAU
		progress = maxf(progress, angle)
		var next: float = minf(progress + 0.09, 3 * PI)
		var target: Vector3 = Vector3(cos(next) * 3.9, 0, -sin(next) * 3.9)
		if progress >= 3 * PI - 0.0001:
			target = Vector3(-2.1, 0, 0)
		var direction: Vector3 = (target - actor.position).slide(Vector3.UP).normalized()
		actor.velocity.x = direction.x * 3.5
		actor.velocity.z = direction.z * 3.5
		if actor.is_on_floor() and not jumped and progress > deg_to_rad(196):
			actor.velocity.y = 5
			jumped = true
		elif actor.is_on_floor() and not entry_jump and progress > deg_to_rad(539.5):
			# 平台入口的短跳也使用真实起跳速度，覆盖凸碰撞边缘的实际通行。
			actor.velocity.y = 5
			entry_jump = true
		elif not actor.is_on_floor():
			actor.velocity.y -= 9.8 * delta
		else:
			actor.velocity.y = 0
		actor.move_and_slide()
		maximum_height = maxf(maximum_height, actor.position.y)
		if actor.position.y >= BeaconTowers.TOP - 0.1 and Vector2(actor.position.x, actor.position.z).length() < 3 and actor.is_on_floor():
			reached = true
			break
		if actor.position.y < -1:
			break
	var ascent_position: Vector3 = actor.position
	var descent_progress: float = 3 * PI
	var exited_crown: bool = false
	var descent_exit_jump: bool = false
	var descent_jump: bool = false
	var returned: bool = false
	if reached:
		for count: int in 2400:
			await tree.physics_frame
			var delta: float = actor.get_physics_process_delta_time()
			elapsed += delta
			var angle: float = atan2(-actor.position.z, actor.position.x)
			while angle < descent_progress - PI:
				angle += TAU
			while angle > descent_progress + PI:
				angle -= TAU
			if exited_crown:
				descent_progress = minf(descent_progress, angle)
			var next: float = maxf(descent_progress - 0.09, 0.0)
			var target: Vector3 = Vector3(cos(next) * 3.9, 0, -sin(next) * 3.9) if exited_crown else Vector3(-3.9, 0, 0)
			var direction: Vector3 = (target - actor.position).slide(Vector3.UP).normalized()
			actor.velocity.x = direction.x * 3.5
			actor.velocity.z = direction.z * 3.5
			if actor.is_on_floor() and not exited_crown and not descent_exit_jump and Vector2(actor.position.x, actor.position.z).length() > 2.6:
				# 塔冠入口与上行共用同一碰撞薄边，返回时也以正常短跳通过。
				actor.velocity.y = 5
				descent_exit_jump = true
			elif actor.is_on_floor() and exited_crown and not descent_jump and descent_progress < deg_to_rad(225):
				actor.velocity.y = 5
				descent_jump = true
			elif not actor.is_on_floor():
				actor.velocity.y -= 9.8 * delta
			else:
				actor.velocity.y = 0
			actor.move_and_slide()
			exited_crown = exited_crown or Vector2(actor.position.x, actor.position.z).length() >= 3.85
			if descent_progress <= 0.02 and actor.position.y < 0.35 and actor.is_on_floor():
				returned = true
				break
			if actor.position.y < -1:
				break
	var result: Dictionary = {"passed": jumped and reached and descent_jump and returned, "mountain_pass_tower": tower["id"], "jumped_gap": jumped, "reached_crown": reached, "descent_exit_jump": descent_exit_jump, "descent_jumped_gap": descent_jump, "returned_to_ground": returned, "maximum_height_m": maximum_height, "duration_s": elapsed, "ascent_position": str(ascent_position), "final_position": str(actor.position), "angle_degrees": rad_to_deg(progress), "descent_degrees": rad_to_deg(descent_progress), "gap_m": 3.9 * PI / 12.0, "maximum_centerline_height_step_m": 0.5 * 3 / (3.9 * PI / 2)}
	scene.queue_free()
	for count: int in 3:
		await tree.process_frame
	return result
