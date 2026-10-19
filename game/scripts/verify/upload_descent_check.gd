class_name UploadDescentCheck
extends RefCounted


static func run(scene: Node3D) -> Dictionary:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var up: Vector3 = planet.site["direction"]
	var forward: Vector3 = planet.site["forward"]
	player.controls_enabled = false
	player.mode = StarSeaPlayer.Mode.FLY
	director.time_paused = true
	(scene.get_node("HUD") as CanvasLayer).visible = false
	scene.get_window().mode = Window.MODE_WINDOWED
	scene.get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var surface_radius: float = planet.surface_radius(up)
	player.place_at(planet.global_position + up * (surface_radius + 200000.0), forward, up)
	player.camera.global_basis = Basis.looking_at(-up, forward)
	var deadline: int = Time.get_ticks_msec() + 120000
	for frame: int in 120:
		await scene.get_tree().process_frame
	while not terrain.is_settled():
		await scene.get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			return {"passed": false, "error": "固定速度降落前地形未就绪。"}
	var started: int = Time.get_ticks_usec()
	var maximum: int = 0
	var samples: Array[Dictionary] = []
	var elapsed: float = 0.0
	while elapsed < 100.0:
		await scene.get_tree().process_frame
		elapsed = float(Time.get_ticks_usec() - started) / 1000000.0
		var altitude: float = maxf(200000.0 - elapsed * 2000.0, 1.2)
		player.global_position = planet.global_position + up * (surface_radius + altitude)
		maximum = maxi(maximum, terrain.upload_us)
		if terrain.uploaded_this_frame > 0:
			samples.append({"elapsed_s": elapsed, "altitude_m": altitude, "uploaded_chunks": terrain.uploaded_this_frame, "upload_ms": float(terrain.upload_us) / 1000.0})
	return {"passed": maximum < 4000, "duration_s": elapsed, "descent_speed_m_s": 2000.0, "initial_altitude_m": 200000.0, "maximum_upload_ms": float(maximum) / 1000.0, "upload_frames": samples}
