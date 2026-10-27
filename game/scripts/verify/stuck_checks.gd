class_name StuckChecks
extends RefCounted

const WALK_SPEED: float = 4.0 # 玩家普通步行速度，米每秒。
const WINDOW: float = 0.5 # 卡住判定窗口，秒。
const DISTANCE: float = 10.0 # 每个方向的试走距离，米。


const WORKERS: int = 32 # 共用已加载的静态场景；角色之间不发生碰撞。


static func run(context: VersionContext) -> Dictionary:
	var regions: Array[Dictionary] = VersionContext.regions(context.planet.noise)
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) == "town" and str(b["id"]) != "town")
	var signature: String = _signature()
	var checkpoint_path: String = context.output.path_join("stuck-checkpoint.json")
	var state: Dictionary = {"signature": signature, "region": 0, "point": 0, "direction": 0, "tested": 0, "blocked": [], "excluded": 0, "occupied_starts": 0, "unsupported": 0, "regions": [], "blocked_count": 0, "locations": {}, "finding_logs": []}
	if FileAccess.file_exists(checkpoint_path):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
		if previous is Dictionary and previous.get("signature", "") == signature:
			state = previous
	var case_limit: int = 0
	var failure_limit: int = 128
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--max-cases="):
			case_limit = int(argument.trim_prefix("--max-cases="))
		elif argument.begins_with("--stop-after-failures="):
			failure_limit = int(argument.trim_prefix("--stop-after-failures="))
	var tested_this_run: int = 0
	var manifest: Array[Dictionary] = []
	for region: Dictionary in regions:
		manifest.append({"id": region["id"], "points": VersionContext.points(region, context.planet.noise).size(), "directions": 8})
	VerificationMetrics.write_json(context.output.path_join("stuck-regions.json"), {"spacing_m": VersionContext.SPACING, "regions": manifest, "signature": signature})
	var pool: Array[StarSeaPlayer] = []
	for index: int in WORKERS:
		var template: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		var actor: StarSeaPlayer = template.get_node("Player") as StarSeaPlayer
		template.remove_child(actor)
		template.free()
		actor.name = "WalkProbe%d" % index
		context.scene.add_child(actor)
		actor.camera.current = false
		actor.controls_enabled = false
		actor.collision_layer = 0
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible = false
		actor.ship.body.collision_layer = 0
		actor.ship.visible = false
		# 保留控制器与物理形状，关闭展示动画，避免它们占用批量检查时间。
		actor.explorer.process_mode = Node.PROCESS_MODE_DISABLED
		pool.append(actor)
	context.player.camera.current = true
	context.player.controls_enabled = false
	var old_ticks: int = Engine.physics_ticks_per_second
	var old_scale: float = Engine.time_scale
	var old_maximum: int = Engine.max_physics_steps_per_frame
	# 静态步行检查在物理帧内逐步调用生产控制器。move_and_slide 仍求解真实碰撞，
	# 不等待每一模拟步对应的墙钟时间；移动平台的连续时间由通关检查另行验证。
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1
	var complete: bool = true
	for region_index: int in range(int(state["region"]), regions.size()):
		var region: Dictionary = regions[region_index]
		var points: Array[Vector3] = []
		points.assign(VersionContext.points(region, context.planet.noise))
		if region.has("center"):
			var center: Vector3 = region["center"]
			var basis_value: Basis = Basis.looking_at(SurfaceSites.tangent_forward(center.normalized()), center.normalized())
			points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
				var local_a: Vector3 = basis_value.inverse() * (a - center)
				var local_b: Vector3 = basis_value.inverse() * (b - center)
				var tile_a: Vector2i = Vector2i(floori((local_a.x + 16) / 32), floori((local_a.z + 16) / 32))
				var tile_b: Vector2i = Vector2i(floori((local_b.x + 16) / 32), floori((local_b.z + 16) / 32))
				if tile_a != tile_b:
					return tile_a.length_squared() < tile_b.length_squared() if tile_a.length_squared() != tile_b.length_squared() else tile_a < tile_b
				return local_a.length_squared() < local_b.length_squared() if absf(local_a.length_squared() - local_b.length_squared()) > 0.01 else local_a < local_b)
		var cursor: int = int(state["point"]) * 8 + int(state["direction"])
		while cursor < points.size() * 8:
			var batch: Array[Dictionary] = []
			var remaining: int = mini(WORKERS, points.size() * 8 - cursor)
			if case_limit > 0:
				remaining = mini(remaining, case_limit - tested_this_run)
			for index: int in remaining:
				var trial: int = cursor + index
				var point_index: int = trial / 8
				var direction_index: int = trial % 8
				var up: Vector3 = points[point_index].normalized()
				batch.append({"region": region["id"], "point": point_index, "direction": direction_index, "start": points[point_index], "forward": SurfaceSites.tangent_forward(up).rotated(up, direction_index * TAU / 8)})
			if not await _batch(context, pool, batch, state):
				if not state.has("error"):
					state["error"] = "等待场景碰撞超时"
				complete = false
				break
			cursor += batch.size()
			tested_this_run += batch.size()
			state["tested"] = int(state["tested"]) + batch.size()
			state["region"] = region_index
			state["point"] = cursor / 8
			state["direction"] = cursor % 8
			if VerificationMetrics.write_json(checkpoint_path + ".tmp", state) != OK or DirAccess.rename_absolute(checkpoint_path + ".tmp", checkpoint_path) != OK:
				state["error"] = "断点保存失败"
				complete = false
				break
			print("STUCK_PROGRESS " + JSON.stringify({"region": region["id"], "tested": state["tested"], "blocked": state["blocked_count"], "cursor": cursor, "region_cases": points.size() * 8}))
			if case_limit > 0 and tested_this_run >= case_limit:
				complete = false
				break
			if failure_limit > 0 and int(state["blocked_count"]) >= failure_limit:
				state["termination"] = "已确认大量失败，停止收集重复阻塞；修复后继续断点，完整无故障检查不会提前通过"
				complete = false
				break
		if not complete:
			break
		state["point"] = 0
		state["direction"] = 0
		state["region"] = region_index + 1
	Engine.physics_ticks_per_second = old_ticks
	Engine.time_scale = old_scale
	Engine.max_physics_steps_per_frame = old_maximum
	for actor: StarSeaPlayer in pool:
		actor.ship.queue_free()
		actor.queue_free()
	context.player.camera.current = true
	context.player.collision_layer = 1
	await context.tree.process_frame
	return await _evidence(context, state, manifest, complete)


static func _batch(context: VersionContext, pool: Array[StarSeaPlayer], batch: Array[Dictionary], state: Dictionary) -> bool:
	var first: Vector3 = batch[0]["start"]
	if not await context.place(first, batch[0]["forward"]):
		return false
	context.player.controls_enabled = false
	context.player.collision_layer = 0
	context.player.global_position += first.normalized() * 5
	await context.tree.physics_frame
	var space: PhysicsDirectSpaceState3D = context.player.get_world_3d().direct_space_state
	for index: int in batch.size():
		var item: Dictionary = batch[index]
		var point: Vector3 = item["start"]
		var up: Vector3 = point.normalized()
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(context.planet.to_global(point + up * 1.19), context.planet.to_global(point - up * 2), context.player.collision_mask)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or Vector3(hit["normal"]).dot(up) <= 0.7:
			item["done"] = true
			state["unsupported"] = int(state["unsupported"]) + 1
			continue
		var actor: StarSeaPlayer = pool[index]
		actor.place_at(Vector3(hit["position"]) + up * 0.05, item["forward"], up)
		var capsule: CollisionShape3D = actor.get_node("Collision") as CollisionShape3D
		var occupancy: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		occupancy.shape = capsule.shape
		occupancy.transform = actor.global_transform * capsule.transform
		occupancy.collision_mask = actor.collision_mask
		# 墙柱或雕像内部本来就不是行走面，不能从其内部开始试走再报告卡住。
		if not space.intersect_shape(occupancy, 1).is_empty():
			item["done"] = true
			state["occupied_starts"] = int(state["occupied_starts"]) + 1
			continue
		actor.controls_enabled = true
	await context.tree.physics_frame
	for tick: int in 12:
		for index: int in batch.size():
			if not batch[index].get("done", false):
				pool[index]._physics_process(1.0 / 60)
	for index: int in batch.size():
		batch[index]["window_start"] = pool[index].global_position - context.planet.global_position
		batch[index]["window_ticks"] = 0
	Input.action_press("move_forward")
	for tick: int in 150:
		if absf(pool[0].get_physics_process_delta_time() - 1.0 / 60) > 0.000001 or not Input.is_action_pressed("move_forward"):
			state["error"] = "检查输入或物理步长不符合约定"
			Input.action_release("move_forward")
			return false
		var remaining: int = 0
		for index: int in batch.size():
			var item: Dictionary = batch[index]
			if item.get("done", false):
				continue
			remaining += 1
			var moving_actor: StarSeaPlayer = pool[index]
			moving_actor._physics_process(1.0 / 60)
			for collision_index: int in moving_actor.get_slide_collision_count():
				var contact: KinematicCollision3D = moving_actor.get_slide_collision(collision_index)
				if contact.get_normal().dot(moving_actor.up_direction) < 0.999:
					item["blocker"] = contact.get_collider()
			item["window_ticks"] += 1
			if int(item["window_ticks"]) < 30:
				continue
			var actor: StarSeaPlayer = pool[index]
			var at: Vector3 = actor.global_position - context.planet.global_position
			var distance: float = (at - Vector3(item["window_start"])).slide(at.normalized()).length()
			if distance < WALK_SPEED * WINDOW * 0.2:
				var object_name: String = "没有取得阻挡碰撞体"
				var object_source: String = "unresolved"
				var height: float = 0
				var recent: Node = item.get("blocker", null) as Node
				if is_instance_valid(recent):
					object_name = _object_name(recent)
					height = _height(recent, actor.up_direction)
					object_source = "slide_collision"
				for collision_index: int in actor.get_slide_collision_count():
					var collision: KinematicCollision3D = actor.get_slide_collision(collision_index)
					if collision.get_normal().dot(actor.up_direction) >= 0.999:
						continue
					var collider: Node = collision.get_collider() as Node
					if collider != null:
						object_name = _object_name(collider)
						height = _height(collider, actor.up_direction)
						object_source = "slide_collision"
						break
				if object_source == "unresolved":
					var candidate: Node = _forward_blocker(actor, item["forward"])
					if candidate != null:
						object_name = _object_name(candidate)
						height = _height(candidate, actor.up_direction)
						object_source = "forward_probe_candidate"
				var tall: bool = false
				for kind: String in ["wall", "column", "door", "arch", "statue", "pillar", "monument", "stele", "lamp_post", "standing_stone", "brazier", "tree"]:
					tall = tall or object_name.to_lower().contains(kind)
				var excluded: bool = height > 1.2 and tall and object_source == "slide_collision"
				var finding: Dictionary = {"region": item["region"], "point": item["point"], "direction": item["direction"], "position": at, "forward": item["forward"], "distance_in_window_m": distance, "window_s": WINDOW, "object": object_name, "object_source": object_source, "blocker_height_m": height, "excluded": excluded, "grounded": actor.is_on_floor(), "waiting_for_ground": actor._waiting_for_ground}
				if excluded:
					state["excluded"] = int(state["excluded"]) + 1
				else:
					state["blocked_count"] = int(state["blocked_count"]) + 1
					if state["blocked"].size() < 2000:
						state["blocked"].append(finding)
					var log_path: String = context.output.path_join("stuck-findings.jsonl")
					if not state["finding_logs"].has(log_path):
						state["finding_logs"].append(log_path)
					var key: String = str(item["region"]) + "/" + object_name.get_file().get_slice("#", 0) + "/" + str(at.snapped(Vector3.ONE * 2))
					if not state["locations"].has(key):
						state["locations"][key] = {"count": 0, "finding": finding}
					state["locations"][key]["count"] += 1
					var file: FileAccess = FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
					file.seek_end()
					file.store_line(JSON.stringify(finding))
					file.close()
				item["done"] = true
				actor.controls_enabled = false
			item["window_ticks"] = 0
			item["window_start"] = at
		if remaining == 0:
			break
	Input.action_release("move_forward")
	for actor: StarSeaPlayer in pool:
		actor.controls_enabled = false
	return true


static func _forward_blocker(actor: StarSeaPlayer, forward: Vector3) -> Node:
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	for height: float in [0.1, 0.25, 0.6, 1.0]:
		var from: Vector3 = actor.global_position + actor.up_direction * height
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + forward * 0.8, actor.collision_mask, [actor.get_rid()])
		query.hit_from_inside = true
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			return hit["collider"] as Node
	var capsule: CollisionShape3D = actor.get_node("Collision") as CollisionShape3D
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule.shape
	shape_query.transform = capsule.global_transform
	shape_query.transform.origin += forward * 0.2
	shape_query.collision_mask = actor.collision_mask
	shape_query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = space.intersect_shape(shape_query, 1)
	# 这是阻塞发生后的近距离候选，不用它豁免高墙，也不冒充碰撞接触证据。
	return hits[0]["collider"] as Node if not hits.is_empty() else null


static func _object_name(collider: Node) -> String:
	if collider.has_meta("ecology_kind"):
		return str(collider.get_path()) + "/" + str(collider.get_meta("ecology_kind"))
	var parent: Node = collider.get_parent()
	if parent is RuinBuilder:
		var builder: RuinBuilder = parent as RuinBuilder
		for index: int in builder._colliders:
			if builder._colliders[index] == collider:
				return str(collider.get_path()) + "/" + str(builder._placements[index]["piece"]) + "#" + str(index)
	return str(collider.get_path())


static func _height(collider: Node, up: Vector3) -> float:
	var low: float = INF
	var high: float = -INF
	for child: Node in collider.find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape.shape == null or shape.disabled:
			continue
		var bounds: AABB = shape.shape.get_debug_mesh().get_aabb()
		for corner: int in 8:
			var height_value: float = (shape.global_transform * bounds.get_endpoint(corner)).dot(up)
			low = minf(low, height_value)
			high = maxf(high, height_value)
	return high - low if is_finite(low) else 0.0


static func _evidence(context: VersionContext, state: Dictionary, manifest: Array[Dictionary], complete: bool) -> Dictionary:
	var groups: Dictionary = state["locations"]
	var ranked: Array = groups.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"]))
	for index: int in mini(10, ranked.size()):
		var finding: Dictionary = ranked[index]["finding"]
		var point: Vector3 = _vector(finding["position"])
		await context.place(point, _vector(finding["forward"]))
		ranked[index]["screenshot"] = await context.capture("stuck-top-%02d" % (index + 1))
	var report: Dictionary = _report(state, manifest, complete)
	report["worst_locations"] = ranked.slice(0, 10)
	report["ranking_scope"] = "已完成样本；提前失败时不代表整个世界的排名"
	report["source_signature"] = state["signature"]
	report["finding_logs"] = state["finding_logs"]
	report["blocked_examples_truncated"] = int(state["blocked_count"]) > state["blocked"].size()
	return report


static func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	var parts: PackedStringArray = str(value).trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _report(state: Dictionary, regions: Array[Dictionary], complete: bool) -> Dictionary:
	return {"passed": complete and state["blocked"].is_empty() and not state.has("error"), "coverage_complete": complete, "termination": state.get("termination", ""), "tested": state["tested"], "regions": regions, "blocked": state["blocked"], "blocked_count": state["blocked_count"], "excluded_tall_obstacles": state["excluded"], "excluded_occupied_starts": state["occupied_starts"], "unsupported_points": state["unsupported"], "checkpoint": {"region": state["region"], "point": state["point"], "direction": state["direction"]}, "error": state.get("error", ""), "simulation": "生产 StarSeaPlayer 控制器、真实 move_and_slide、固定 1/60 秒步长、独立无互撞的检查角色", "threshold": {"window_s": WINDOW, "minimum_expected_fraction": 0.2, "distance_m": DISTANCE, "grid_m": VersionContext.SPACING}}


static func _signature() -> String:
	var source: String = ""
	for path: String in [HydrologyData.PATH, CaveData.PATH, DawnHeightfield.PATH, "res://scripts/player/player.gd", "res://scripts/player/player_traversal.gd", "res://scripts/verify/stuck_checks.gd", "res://scripts/verify/version_context.gd", "res://models/ruins/geometry.json"]:
		source += FileAccess.get_sha256(path)
	for directory: String in ["res://scenes", "res://scripts/civilization", "res://scripts/planet", "res://models"]:
		source += _directory_hashes(directory)
	return source.sha256_text()


static func _directory_hashes(directory: String) -> String:
	var result: String = ""
	var children: PackedStringArray = DirAccess.get_directories_at(directory)
	children.sort()
	for child: String in children:
		result += _directory_hashes(directory.path_join(child))
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	for file: String in files:
		if file.get_extension() in ["gd", "tscn", "glb", "gltf", "json"]:
			var path: String = directory.path_join(file)
			result += path + FileAccess.get_sha256(path)
	return result
