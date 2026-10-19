class_name AcceptanceChecks
extends RefCounted


static func core(scene: Node3D, output: String) -> Dictionary:
	var failures: Array[String] = []
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var settings: StarSeaSettings = scene.get_node("/root/GameSettings") as StarSeaSettings
	player.controls_enabled = false
	director.time_paused = true
	var flight: Array[Dictionary] = []
	for node: Node in scene.get_tree().get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var worst: float = INF
		for index: int in 24:
			var up: Vector3 = Vector3(sin(index * 2.4), cos(index * 0.7), sin(index * 0.93)).normalized()
			player.mode = StarSeaPlayer.Mode.FLY
			player.place_at(planet.global_position + up * (planet.radius + 5000.0), SurfaceSites.tangent_forward(up), up)
			player.velocity = -up * 120000.0
			player.advance_flight(player.velocity, 1.0)
			var relative: Vector3 = player.global_position - planet.global_position
			var altitude: float = relative.length() - planet.surface_radius(relative.normalized())
			worst = minf(worst, altitude)
			if relative.normalized().dot(up) < 0.999 or altitude < 1.15 or altitude > 1.25:
				failures.append(planet.planet_name + "的高速飞行越过首次地表接触。")
			for frame: int in 30:
				player.advance_flight(up * 12.0, 1.0 / 60.0)
			if player.altitude < 3.0:
				failures.append(planet.planet_name + "无法从贴地保护状态重新起飞。")
		flight.append({"planet": planet.planet_name, "cross_planet_sweeps": 24, "takeoffs_after_contact": 24, "minimum_clearance_m": worst})
	var systems: Dictionary = SystemChecks.run(scene)
	if not systems["passed"]:
		failures.append_array(systems["failures"])
	var save_path: String = "user://verify_acceptance_journey.cfg"
	var original_save: Error = JourneyStore.save(scene, save_path)
	var saved: ConfigFile = ConfigFile.new()
	saved.load(save_path)
	var before: Transform3D = player.global_transform
	var cases: Array = [["mode", []], ["pitch", "bad"], ["planet_seed", {}], ["position", Vector3(INF, 0, 0)], ["forward", Vector3.ONE * 1e30], ["up", Vector3.ZERO], ["sun", Vector3.ZERO], ["mode", 7], ["pitch", 3.0], ["planet_seed", -99]]
	var rejected: int = 0
	for record: Array in cases:
		var original: Variant = saved.get_value("journey", record[0])
		saved.set_value("journey", record[0], record[1])
		saved.save(save_path)
		if JourneyStore.restore(scene, save_path) == ERR_INVALID_DATA and player.global_transform == before:
			rejected += 1
		saved.set_value("journey", record[0], original)
	if original_save != OK or rejected != cases.size():
		failures.append("损坏存档没有全部安全拒绝。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var settings_path: String = "user://verify_acceptance_settings.cfg"
	var original_settings: Array = [StarSeaSettings.sensitivity, StarSeaSettings.volume, StarSeaSettings.render_scale, StarSeaSettings.field_of_view, StarSeaSettings.fullscreen, StarSeaSettings.vsync, StarSeaSettings.music_volume]
	settings.save(settings_path)
	var configuration: ConfigFile = ConfigFile.new()
	configuration.load(settings_path)
	var setting_cases: Array = [["controls", "sensitivity", []], ["audio", "volume", NAN], ["audio", "music", INF], ["video", "scale", INF], ["video", "fov", "bad"], ["video", "fullscreen", 1], ["video", "vsync", {}]]
	var settings_rejected: int = 0
	for record: Array in setting_cases:
		var original: Variant = configuration.get_value(record[0], record[1])
		configuration.set_value(record[0], record[1], record[2])
		configuration.save(settings_path)
		var error: Error = settings.load_settings(settings_path)
		var after: Array = [StarSeaSettings.sensitivity, StarSeaSettings.volume, StarSeaSettings.render_scale, StarSeaSettings.field_of_view, StarSeaSettings.fullscreen, StarSeaSettings.vsync, StarSeaSettings.music_volume]
		if error == ERR_INVALID_DATA and after == original_settings:
			settings_rejected += 1
		configuration.set_value(record[0], record[1], original)
	if settings_rejected != setting_cases.size():
		failures.append("损坏设置没有全部安全拒绝。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	StarSeaSettings.volume = 0.0
	settings.apply()
	var muted: bool = AudioServer.is_bus_mute(0)
	StarSeaSettings.volume = original_settings[1]
	settings.apply()
	if not muted:
		failures.append("音量为零时没有静音。")
	var environments: Array[Dictionary] = []
	for node: Node in scene.get_tree().get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var up: Vector3 = planet.site["direction"]
		var ground: Dictionary = Soundscape.environment_at(planet, up * (planet.surface_radius(up) + 1.0))
		var space: Dictionary = Soundscape.environment_at(planet, up * (planet.radius + planet.atmosphere_height * 2.0))
		if ground["wind"] <= 0.0 or space["wind"] != 0.0 or space["shore"] != 0.0 or space["rustle"] != 0.0 or space["space"] <= 0.0:
			failures.append(planet.planet_name + "的地表与太空声音未正确区分。")
		environments.append({"planet": planet.planet_name, "ground": ground, "space": space})
	var dawn: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	player.place_at(dawn.global_position + dawn.site["direction"] * (dawn.surface_radius(dawn.site["direction"]) + 0.05), dawn.site["forward"], dawn.site["direction"])
	player.mode = StarSeaPlayer.Mode.WALK
	(scene.get_node("HUD") as CanvasLayer).visible = true
	var interface_report: Dictionary = await InteractionChecks.run(scene, output)
	if not interface_report["passed"]:
		failures.append_array(interface_report["failures"])
	var menu: VoyageMenu = scene.get_node("VoyageMenu") as VoyageMenu
	menu.initialize()
	menu.open()
	var menu_paused: bool = scene.get_tree().paused and not player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not (scene.get_node("HUD") as CanvasLayer).visible
	for frame: int in 30:
		await scene.get_tree().process_frame
	await _capture(scene, output.path_join("menu.png"))
	(menu.find_child("Settings", true, false) as Button).pressed.emit()
	var settings_controls: bool = menu.find_children("*", "HSlider", true, false).size() == 5
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		scene.get_window().size = size
		for frame: int in 30:
			await scene.get_tree().process_frame
		await _capture(scene, output.path_join("settings_%d.png" % size.y))
	menu.resume()
	if not menu_paused or not settings_controls or scene.get_tree().paused or not player.controls_enabled or not (scene.get_node("HUD") as CanvasLayer).visible:
		failures.append("菜单暂停、设置或继续功能异常。")
	player.controls_enabled = false
	var sun_before: Vector3 = director.sun_direction
	var minimum_energy: float = INF
	var maximum_energy: float = 0.0
	var maximum_angle_step: float = 0.0
	director.time_paused = false
	for second: int in 1200:
		var previous: Vector3 = director.sun_direction
		director._process(1.0)
		maximum_angle_step = maxf(maximum_angle_step, previous.angle_to(director.sun_direction))
		var energy: float = (scene.get_node("Sun") as DirectionalLight3D).light_energy
		minimum_energy = minf(minimum_energy, energy)
		maximum_energy = maxf(maximum_energy, energy)
	var cycle_closed: bool = sun_before.angle_to(director.sun_direction) < 0.001
	if not cycle_closed or minimum_energy > 0.01 or maximum_energy < 1.2 or maximum_angle_step > 0.006:
		failures.append("完整昼夜没有覆盖白昼、黑夜或出现太阳方向突变。")
	director.time_paused = true
	InteractionChecks._emit_key(KEY_T, true)
	await scene.get_tree().process_frame
	var before_acceleration: Vector3 = director.sun_direction
	director.time_paused = false
	director._process(1.0 / 60.0)
	director.time_paused = true
	var accelerated: bool = director.sun_direction.angle_to(before_acceleration.rotated(Vector3.UP, TAU / 1200.0)) < 0.0001
	InteractionChecks._emit_key(KEY_T, false)
	if not accelerated:
		failures.append("T 未按要求加速昼夜。")
	director.sun_direction = sun_before
	director.time_paused = true
	return {"passed": failures.is_empty(), "failures": failures, "flight": flight, "systems": systems, "invalid_saves_rejected": rejected, "invalid_settings_rejected": settings_rejected, "zero_volume_muted": muted, "sound_environments": environments, "interface": interface_report, "menu_pauses_world": menu_paused, "settings_controls_present": settings_controls, "day_cycle": {"closed": cycle_closed, "accelerated_by_t": accelerated, "minimum_sun_energy": minimum_energy, "maximum_sun_energy": maximum_energy, "maximum_angle_step_degrees": rad_to_deg(maximum_angle_step)}}


static func world(scene: Node3D, output: String) -> Dictionary:
	var failures: Array[String] = []
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var origin: FloatingOrigin = scene.get_node("FloatingOrigin") as FloatingOrigin
	player.controls_enabled = false
	director.time_paused = true
	var routes: Array[Dictionary] = []
	var landings: Array[Dictionary] = []
	for node: Node in scene.get_tree().get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		for axis: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD]:
			var reference: Vector3 = SurfaceSites.tangent_forward(axis)
			var initial: Vector3 = reference * (planet.radius + 15000.0)
			player.mode = StarSeaPlayer.Mode.FLY
			player.place_at(planet.global_position + initial, axis.cross(reference), reference)
			var minimum: float = INF
			for step: int in range(1, 97):
				var up: Vector3 = reference.rotated(axis, TAU * step / 96.0)
				var destination: Vector3 = planet.global_position + up * (planet.radius + 15000.0)
				player.velocity = (destination - player.global_position) * 10.0
				player.advance_flight(player.velocity, 0.1)
				player.global_basis = Basis.looking_at(axis.cross(up), up)
				origin._physics_process(0.1)
				minimum = minf(minimum, player.altitude)
				await scene.get_tree().process_frame
			var closure: float = (player.global_position - planet.global_position).distance_to(initial)
			if closure > 0.2 or minimum < 12000.0:
				failures.append(planet.planet_name + "的整球绕行没有闭合。")
			routes.append({"planet": planet.planet_name, "axis": str(axis), "segments": 96, "closure_error_m": closure, "minimum_altitude_m": minimum})
		for face: int in 6:
			var up: Vector3 = _landing_direction(planet, face)
			if up.is_zero_approx():
				failures.append("没有找到面编号 %d 的可步行位置。" % face)
				continue
			var forward: Vector3 = SurfaceSites.tangent_forward(up)
			player.mode = StarSeaPlayer.Mode.FLY
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 80.0), forward, up)
			director.set_sun_altitude(up, -forward, 30.0)
			if not await _settle(scene, planet):
				failures.append(planet.planet_name + "的多地点着陆等待地形超时。")
				continue
			for step: int in 140:
				var local_up: Vector3 = (player.global_position - planet.global_position).normalized()
				player.advance_flight(-local_up * 50.0, 1.0 / 60.0)
				await scene.get_tree().physics_frame
			player._start_walking()
			player.simulated_forward = true
			var minimum: float = INF
			var grounded: int = 0
			var start: Vector3 = player.global_position - planet.global_position
			for step: int in 180:
				await scene.get_tree().physics_frame
				var relative: Vector3 = player.global_position - planet.global_position
				minimum = minf(minimum, relative.length() - planet.surface_radius(relative.normalized()))
				if player.is_on_floor():
					grounded += 1
			player.simulated_forward = false
			var relative: Vector3 = player.global_position - planet.global_position
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + up * 3.0, player.global_position - up * 5.0, 1)
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
			var passed: bool = minimum > -0.3 and grounded > 100 and not hit.is_empty()
			if not passed:
				failures.append("%s 面编号 %d 着陆或贴地检查失败。" % [planet.planet_name, face])
			landings.append({"planet": planet.planet_name, "face": face, "direction": str(up), "passed": passed, "minimum_altitude_m": minimum, "grounded_frames": grounded, "distance_m": relative.distance_to(start), "ground_collider_hit": not hit.is_empty()})
			if face == 0 or face == 3:
				await _capture(scene, output.path_join("landing_%d_%d.png" % [planet.profile, face]))
	return {"passed": failures.is_empty(), "failures": failures, "orbit_routes": routes, "landings": landings, "recenter_count": origin.recenter_count}


static func _landing_direction(planet: Planet, face: int) -> Vector3:
	var axes: Array = PlanetTerrain.FACES[face]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet.planet_seed + face * 701
	for attempt: int in 1200:
		var direction: Vector3 = PlanetTerrain.cube_to_sphere(axes[0] + axes[1] * rng.randf_range(-0.9, 0.9) + axes[2] * rng.randf_range(-0.9, 0.9)).normalized()
		var height: float = planet.noise.height(direction)
		if height > 25.0 and planet.noise.slope(direction, height) < 0.15:
			return direction
	return Vector3.ZERO


static func audio(scene: Node3D, output: String) -> Dictionary:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var sound: Soundscape = scene.get_node("Soundscape") as Soundscape
	var dawn: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	player.controls_enabled = false
	director.time_paused = true
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var effect: AudioEffectRecord = AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, effect)
	for shot: String in ["s6_shore", "s9_woodland", "s7_ember", "s8_frost", "s1_space"]:
		ShotCatalog.place(shot, player, dawn, director)
		if shot != "s1_space" and not await _settle(scene, player.current_planet()):
			failures.append(shot + "录音前等待地形超时。")
			continue
		await scene.get_tree().create_timer(3.0).timeout
		effect.set_recording_active(true)
		if shot != "s1_space":
			player._start_walking()
			player.simulated_forward = true
		await scene.get_tree().create_timer(5.0).timeout
		player.simulated_forward = false
		effect.set_recording_active(false)
		var recording: AudioStreamWAV = effect.get_recording()
		var path: String = output.path_join(shot + ".wav")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		var error: Error = recording.save_to_wav(ProjectSettings.globalize_path(path))
		if error != OK or recording.data.size() < 22050:
			failures.append(shot + "的实际混音录制失败。")
		records.append({"shot": shot, "seconds": recording.get_length(), "bytes": recording.data.size(), "environment": sound._environment.duplicate(), "saved": error == OK})
	AudioServer.remove_bus_effect(0, effect_index)
	for kind: String in sound._loops:
		var loop: AudioStreamPlayer = sound._loops[kind]
		if not loop.playing or (loop.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
			failures.append(kind + "没有持续循环。")
	return {"passed": failures.is_empty(), "failures": failures, "recordings": records, "ambient_loops": sound._loops.size(), "step_surfaces": sound._steps.size()}


static func _settle(scene: Node, planet: Planet) -> bool:
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var details: SurfaceDetails = planet.get_node("SurfaceDetails") as SurfaceDetails
	var deadline: int = Time.get_ticks_msec() + 120000
	for frame: int in 30:
		await scene.get_tree().process_frame
	while not terrain.is_settled() or not details.is_settled():
		await scene.get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			return false
	return true


static func _capture(scene: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	scene.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
