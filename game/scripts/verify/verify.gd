extends Node

var _player: StarSeaPlayer
var _planet: Planet
var _terrain: PlanetTerrain
var _director: SkyDirector
var _viewport_rid: RID


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		return
	for argument: String in arguments:
		if argument.begins_with("--check="):
			return
	_run.call_deferred()


func _run() -> void:
	var shot: String = ""
	var output_directory: String = "res://../test-output/p1/shots"
	var descent_path: String = ""
	var walk_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			shot = argument.trim_prefix("--shot=")
		elif argument.begins_with("--out="):
			output_directory = argument.trim_prefix("--out=")
		elif argument.begins_with("--descent="):
			descent_path = argument.trim_prefix("--descent=")
		elif argument.begins_with("--walk="):
			walk_path = argument.trim_prefix("--walk=")
		else:
			_fail("未知验证参数：" + argument)
			return
	if int(not shot.is_empty()) + int(not descent_path.is_empty()) + int(not walk_path.is_empty()) != 1:
		_fail("每次运行只能选择一个截图、降落或行走验证项目。")
		return
	if DisplayServer.get_name() == "headless":
		_fail("性能与画面验收必须使用真实渲染器。")
		return
	await get_tree().process_frame
	var scene: Node = get_tree().current_scene
	_player = scene.get_node("Player") as StarSeaPlayer
	_planet = scene.get_node("Universe/PlanetDawn") as Planet
	_terrain = _planet.get_node("Terrain") as PlanetTerrain
	_director = scene.get_node("SkyDirector") as SkyDirector
	_viewport_rid = get_viewport().get_viewport_rid()
	_player.controls_enabled = false
	(scene.get_node("HUD") as CanvasLayer).visible = false
	# 验收固定在 1080p、关闭垂直同步，正常运行仍使用桌面分辨率和垂直同步。
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	if not shot.is_empty():
		if not ShotCatalog.NAMES.has(shot):
			_fail("未知机位：" + shot)
			return
		await _capture_shot(shot, output_directory)
	elif not descent_path.is_empty():
		await _measure_descent(descent_path)
	else:
		await _measure_walk(walk_path)


func _wait_for_terrain() -> bool:
	var deadline: int = Time.get_ticks_msec() + 120000
	var stable_since: int = -1
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _terrain.is_settled():
			if stable_since < 0:
				stable_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - stable_since >= 400:
				for frame: int in 120:
					await get_tree().process_frame
				return true
		else:
			stable_since = -1
	_fail("地形生成在 120 秒内没有完成。")
	return false


func _capture_shot(name: String, output_directory: String) -> void:
	ShotCatalog.place(name, _player, _planet, _director)
	await get_tree().physics_frame
	_planet = Planet.nearest(get_tree(), _player.global_position)
	_terrain = _planet.get_node("Terrain") as PlanetTerrain
	if not await _wait_for_terrain():
		return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path(output_directory) if output_directory.begins_with("res://") else output_directory
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		_fail("无法创建截图目录：" + error_string(directory_error))
		return
	var image: Image = get_viewport().get_texture().get_image()
	var image_error: Error = image.save_png(directory.path_join(name + ".png"))
	if image_error != OK:
		_fail("无法保存截图：" + error_string(image_error))
		return
	# Performance 部分监控器存在一秒更新延迟，截图写盘后先等待旧值失效。
	await get_tree().create_timer(2.2).timeout
	var intervals: Array[float] = []
	var cpu_times: Array[float] = []
	var gpu_times: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for frame: int in 240:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		cpu_times.append(_cpu_ms())
		gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
	var offset: Vector3 = _player.camera.global_position - _planet.global_position
	var interval_statistics: Dictionary = VerificationMetrics.summarize(intervals)
	var report: Dictionary = {
		"shot": name,
		"resolution": [image.get_width(), image.get_height()],
		"vsync_enabled": false,
		"engine_version": Engine.get_version_info()["string"],
		"terrain_grid": PlanetTerrain.GRID,
		"shadow_distance_m": (get_tree().current_scene.get_node("Sun") as DirectionalLight3D).directional_shadow_max_distance,
		"render_scale": get_viewport().scaling_3d_scale,
		"frames": 240,
		"camera_universe_position": _vector_array(_player.camera.global_position - (get_tree().current_scene.get_node("Universe") as Node3D).global_position),
		"camera_altitude_m": offset.length() - _planet.surface_radius(offset.normalized()),
		"sun_altitude_degrees": rad_to_deg(asin(clampf(offset.normalized().dot(_director.sun_direction), -1.0, 1.0))),
		"frame_ms": interval_statistics,
		"cpu_ms": VerificationMetrics.summarize(cpu_times),
		"cpu_metric": "TIME_PROCESS + TIME_PHYSICS_PROCESS; one-second peak monitors, not per-frame CPU samples",
		"gpu_ms": VerificationMetrics.summarize(gpu_times),
		"visible_chunks": _terrain.visible_chunks,
		"maximum_upload_ms": float(_terrain.maximum_upload_us) / 1000.0,
		"site": _site_report(),
		"performance_passed": float(interval_statistics["mean"]) <= 12.5 and float(interval_statistics["p95"]) <= 16.0,
	}
	var save_error: Error = VerificationMetrics.write_json(directory.path_join(name + ".json"), report)
	if save_error != OK:
		_fail("无法保存机位报告：" + error_string(save_error))
		return
	print(JSON.stringify(report))
	get_tree().quit(0)


func _cpu_ms() -> float:
	return (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0


func _site_report() -> Dictionary:
	return {"planet": _planet.planet_name, "height_m": _planet.noise.height(_planet.site["direction"]), "mountain_height_m": _planet.site.get("mountain_height_m", 0.0), "mountain_distance_m": _planet.site.get("mountain_distance_m", 0.0), "candidate_index": _planet.site.get("candidate_index", -1)}


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _measure_descent(path: String) -> void:
	ShotCatalog.place("s1_space", _player, _planet, _director)
	if not await _wait_for_terrain():
		return
	var universe: Node3D = get_tree().current_scene.get_node("Universe") as Node3D
	var start: Vector3 = _player.global_position - universe.global_position
	var up: Vector3 = _planet.site["direction"]
	var target: Vector3 = up * (_planet.surface_radius(up) + 1.2)
	var route_length: float = start.distance_to(target)
	var frames: Array[Dictionary] = []
	var intervals: Array[float] = []
	var slow_frames: Array[Dictionary] = []
	var maximum_upload_us: int = 0
	var initial_recenter_count: int = (get_tree().current_scene.get_node("FloatingOrigin") as FloatingOrigin).recenter_count
	var initial_pipeline_surface: int = int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))
	var initial_pipeline_draw: int = int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	var elapsed: float = 0.0
	var landed_after: float = -1.0
	while elapsed < 60.0:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var delta: float = float(now - previous) / 1000000.0
		previous = now
		elapsed = float(now - started) / 1000000.0
		var location: Vector3 = _player.global_position - universe.global_position
		var local_up: Vector3 = location.normalized()
		var altitude: float = location.length() - _planet.surface_radius(local_up)
		var remaining_time: float = maxf(60.0 - elapsed, 0.01)
		var remaining_distance: float = location.distance_to(target)
		# 在飞行模式速度上限内按剩余距离安排速度，保留最终接近地表的过程。
		var speed_limit: float = clampf(altitude, 12.0, 30000.0)
		var speed: float = minf(speed_limit, remaining_distance / remaining_time * 3.0)
		_player.advance_flight(location.direction_to(target) * speed, delta)
		location = _player.global_position - universe.global_position
		local_up = location.normalized()
		_player.camera.look_at(_planet.global_position + target, _player.global_basis.y)
		if location.distance_to(target) <= 2.0 and landed_after < 0.0:
			landed_after = elapsed
		var sample: Dictionary = {
			"elapsed_s": elapsed,
			"frame_ms": delta * 1000.0,
			"cpu_ms": _cpu_ms(),
			"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
			"uploaded_chunks": _terrain.uploaded_this_frame,
			"upload_ms": float(_terrain.upload_us) / 1000.0,
			"altitude_m": location.length() - _planet.surface_radius(local_up),
			"visible_chunks": _terrain.visible_chunks,
			"pipeline_surface": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)),
			"pipeline_draw": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)),
		}
		frames.append(sample)
		intervals.append(delta * 1000.0)
		maximum_upload_us = maxi(maximum_upload_us, _terrain.upload_us)
		if elapsed > 3.0 and delta > 0.05:
			slow_frames.append(sample)
	var statistics: Dictionary = VerificationMetrics.summarize(intervals)
	var final_location: Vector3 = _player.global_position - universe.global_position
	var remaining: float = final_location.distance_to(target)
	var report: Dictionary = {
		"duration_s": elapsed,
		"route_length_m": route_length,
		"landed_after_s": landed_after,
		"remaining_distance_m": remaining,
		"frame_ms": statistics,
		"slow_frames_after_3s": slow_frames,
		"maximum_upload_ms": float(maximum_upload_us) / 1000.0,
		"upload_budget_passed": maximum_upload_us < 4000,
		"recenter_count": (get_tree().current_scene.get_node("FloatingOrigin") as FloatingOrigin).recenter_count - initial_recenter_count,
		"frames": frames,
		"performance_passed": float(statistics["p99"]) <= 20.0 and slow_frames.is_empty(),
		"landing_passed": remaining <= 2.0,
		"pipeline_compilations_during_descent": {
			"surface": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)) - initial_pipeline_surface,
			"draw": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) - initial_pipeline_draw,
		},
	}
	if VerificationMetrics.write_json(path, report) != OK:
		_fail("无法写入降落验证报告。")
		return
	print(JSON.stringify({"descent": path, "frame_ms": statistics, "slow_frames_after_3s": slow_frames.size(), "remaining_distance_m": remaining, "maximum_upload_ms": report["maximum_upload_ms"]}))
	get_tree().quit(0 if report["performance_passed"] and report["landing_passed"] and report["upload_budget_passed"] else 1)


func _measure_walk(path: String) -> void:
	ShotCatalog.place("s3_ground_day", _player, _planet, _director)
	if not await _wait_for_terrain():
		return
	_player.mode = StarSeaPlayer.Mode.WALK
	_player.simulated_forward = true
	var universe: Node3D = get_tree().current_scene.get_node("Universe") as Node3D
	var start: Vector3 = _player.global_position - universe.global_position
	var start_up: Vector3 = start.normalized()
	var started: int = Time.get_ticks_usec()
	var next_sample: float = 0.0
	var minimum_altitude: float = INF
	var positions: Array[Dictionary] = []
	var elapsed: float = 0.0
	while elapsed < 40.0:
		await get_tree().physics_frame
		elapsed = float(Time.get_ticks_usec() - started) / 1000000.0
		var position: Vector3 = _player.global_position - universe.global_position
		var altitude: float = position.length() - _planet.surface_radius(position.normalized())
		minimum_altitude = minf(minimum_altitude, altitude)
		if elapsed >= next_sample:
			positions.append({"elapsed_s": elapsed, "position": _vector_array(position), "altitude_m": altitude, "on_floor": _player.is_on_floor()})
			next_sample += 0.5
	_player.simulated_forward = false
	var finish: Vector3 = _player.global_position - universe.global_position
	var displacement: Vector3 = finish - start
	var horizontal_distance: float = (displacement - start_up * displacement.dot(start_up)).length()
	var passed: bool = minimum_altitude >= -0.3 and horizontal_distance > 120.0
	var report: Dictionary = {"duration_s": elapsed, "minimum_altitude_m": minimum_altitude, "horizontal_displacement_m": horizontal_distance, "passed": passed, "samples": positions}
	if VerificationMetrics.write_json(path, report) != OK:
		_fail("无法写入行走验证报告。")
		return
	print(JSON.stringify({"walk": path, "minimum_altitude_m": minimum_altitude, "horizontal_displacement_m": horizontal_distance, "passed": passed}))
	get_tree().quit(0 if passed else 1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
