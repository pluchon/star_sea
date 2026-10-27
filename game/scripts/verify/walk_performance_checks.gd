class_name WalkPerformanceChecks
extends RefCounted

const DURATION: float = 60.0
const WARMUP: float = 5.0


static func run(context: VersionContext) -> Dictionary:
	var results: Array[Dictionary] = []
	var selected: PackedStringArray = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--walk-scenes="):
			selected = argument.trim_prefix("--walk-scenes=").split(",")
	for id: String in TourShots.SHOTS:
		if not selected.is_empty() and not selected.has(id):
			continue
		ShotCatalog.place(TourShots.SHOTS[id], context.player, context.planet, context.director)
		context.player.mode = StarSeaPlayer.Mode.WALK
		if not await context.settle():
			results.append({"scene": id, "passed": false, "error": "场景加载超时"})
			continue
		var foot: Vector3 = context.local_position()
		if id == "ladder":
			foot = VersionContext.surface(context.planet.noise, foot.normalized())
		elif id == "ring":
			var frame: Transform3D = LandingPads.frame(context.planet)
			var ring_point: Vector3 = frame.affine_inverse() * foot
			ring_point = Vector3(ring_point.x, 0, ring_point.z).normalized() * 53 + Vector3.UP * LandingPads.balcony_height(context.planet)
			foot = frame * ring_point
		# 固定截图机位允许悬停，行走测量必须先落到真实地面，且避开外缘扶手。
		# 截图机位直接设置过相机局部朝向；清除它，保证避障方向就是输入前进方向。
		context.player.camera.rotation = Vector3.ZERO
		if not await context.place(foot, -context.player.global_basis.z):
			results.append({"scene": id, "passed": false, "error": "行走起点加载超时"})
			continue
		if not context.player.is_on_floor():
			results.append({"scene": id, "passed": false, "continuous_walk_valid": false, "error": "起点未取得真实支撑面，不能测量连续行走", "position": context.local_position()})
			continue
		context.player.controls_enabled = true
		Input.action_press("move_forward")
		var start: int = Time.get_ticks_usec()
		var previous: int = start
		var values: Array[float] = []
		var samples: Array[Dictionary] = []
		var start_position: Vector3 = context.local_position()
		var distance: float = 0
		var grounded_s: float = 0
		var measured_s: float = 0
		var longest_airborne_s: float = 0
		var airborne_s: float = 0
		var last_position: Vector3 = start_position
		var spike_count: int = 0
		var next_steer: float = 0
		var previous_steer_position: Vector3 = start_position
		var turn_events: Array[Dictionary] = []
		while float(Time.get_ticks_usec() - start) / 1000000 < DURATION + WARMUP:
			await context.tree.process_frame
			var now: int = Time.get_ticks_usec()
			var elapsed: float = float(now - start) / 1000000
			var frame_ms: float = float(now - previous) / 1000
			previous = now
			var at: Vector3 = context.local_position()
			if elapsed >= WARMUP:
				var seconds: float = frame_ms / 1000
				measured_s += seconds
				if context.player.is_on_floor():
					grounded_s += seconds
					airborne_s = 0
					distance += (at - last_position).slide(at.normalized()).length()
				else:
					airborne_s += seconds
					longest_airborne_s = maxf(longest_airborne_s, airborne_s)
				values.append(frame_ms)
				spike_count += int(frame_ms > 33)
				samples.append({"elapsed_s": elapsed - WARMUP, "frame_ms": frame_ms, "position": at, "grounded": context.player.is_on_floor()})
			last_position = at
			if elapsed >= next_steer:
				var forward: Vector3 = -context.player.global_basis.z
				if at.distance_to(start_position) > 15:
					forward = (start_position - at).slide(at.normalized()).normalized()
				var stalled: bool = at.distance_to(previous_steer_position) < 0.2 and elapsed > 0.5
				var direction: Vector3 = _safe_direction(context, forward, stalled)
				context.player.global_basis = Basis.looking_at(direction, at.normalized())
				context.player.set_head_pitch(0)
				if stalled:
					turn_events.append({"elapsed_s": elapsed, "position": at})
				previous_steer_position = at
				next_steer = elapsed + 0.25
		Input.action_release("move_forward")
		context.player.controls_enabled = false
		var statistics: Dictionary = VerificationMetrics.summarize(values)
		var grounded_fraction: float = grounded_s / maxf(measured_s, 0.001)
		var moving: bool = distance >= DURATION * 2 and grounded_fraction >= 0.95 and longest_airborne_s <= 0.5
		results.append({"scene": id, "passed": moving and float(statistics.get("p99", INF)) <= 20 and spike_count == 0, "walk_distance_m": distance, "grounded_fraction": grounded_fraction, "longest_airborne_s": longest_airborne_s, "continuous_walk_valid": moving, "frame_ms": statistics, "frames_over_33ms": spike_count, "samples": samples, "stalled_turns": turn_events})
		VerificationMetrics.write_json(context.output.path_join("walk-performance-progress.json"), {"status": "running", "results": results})
	return {"passed": results.size() == 7 and results.all(func(value: Dictionary) -> bool: return bool(value["passed"])), "coverage_complete": results.size() == 7, "selected_scenes": selected, "duration_s": DURATION, "warmup_s": WARMUP, "resolution": [1920, 1080], "render_scale": context.tree.root.scaling_3d_scale, "results": results}


static func _safe_direction(context: VersionContext, forward: Vector3, stalled: bool) -> Vector3:
	var up: Vector3 = context.local_position().normalized()
	var space: PhysicsDirectSpaceState3D = context.player.get_world_3d().direct_space_state
	var angles: Array = [60.0, -60.0, 110.0, -110.0, 180.0, 0.0] if stalled else [0.0, 35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 180.0]
	for angle: float in angles:
		var direction: Vector3 = forward.slide(up).normalized().rotated(up, deg_to_rad(angle))
		var from: Vector3 = context.player.global_position + up * 0.8
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + direction * 1.2, context.player.collision_mask, [context.player.get_rid()])
		if not space.intersect_ray(query).is_empty():
			continue
		var ahead: Vector3 = context.player.global_position + direction * 1.0
		var floor_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ahead + up * 0.5, ahead - up * 0.6, context.player.collision_mask, [context.player.get_rid()])
		var floor_hit: Dictionary = space.intersect_ray(floor_query)
		if not floor_hit.is_empty() and Vector3(floor_hit["normal"]).dot(up) > 0.7:
			return direction
	return forward.rotated(up, PI)
