class_name Soundscape
extends Node

var _loops: Dictionary = {}
var _step: AudioStreamPlayer
var _steps: Dictionary = {}
var _player: StarSeaPlayer
var _step_distance: float = 0.0
var _previous_relative: Vector3
var _previous_planet: Planet
var _last_variant: int = -1
var _environment: Dictionary = {}
var _sample_elapsed: float = 1.0
var _reverb: AudioEffectReverb
var _director: SkyDirector


func _ready() -> void:
	var music: MusicDirector = MusicDirector.new()
	music.name = "MusicDirector"
	get_parent().add_child.call_deferred(music)
	_reverb = AudioServer.get_bus_effect(AudioServer.get_bus_index("World"), 0) as AudioEffectReverb
	# 固定步长逻辑检查不依赖音频设备的实际混音时钟。
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_player = get_parent().get_node("Player") as StarSeaPlayer
	for filename: String in ["wind", "shore", "space", "rustle", "rain", "cave_drip", "cave_wind", "ruin_wind", "night_insects", "high_wind"]:
		var stream: AudioStreamWAV = (load("res://audio/" + filename + ".wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		var audio: AudioStreamPlayer = AudioStreamPlayer.new()
		audio.bus = "World"
		audio.name = filename.capitalize()
		audio.stream = stream
		audio.volume_linear = 0.0
		add_child(audio)
		audio.play()
		_loops[filename] = audio
	for surface: String in ["grass", "sand", "rock", "snow"]:
		var variants: Array[AudioStream] = []
		for variant: int in 3:
			variants.append(load("res://audio/step_%s_%d.wav" % [surface, variant]) as AudioStream)
		_steps[surface] = variants
	_step = AudioStreamPlayer.new()
	_step.bus = "World"
	_step.name = "Footsteps"
	_step.volume_db = -15.0
	_step.max_polyphony = 2
	add_child(_step)
	_previous_planet = _player.current_planet()
	_previous_relative = _player.global_position - _previous_planet.global_position


static func environment_at(planet: Planet, relative: Vector3) -> Dictionary:
	if LandingPads.on_platform(planet, relative):
		return {"wind": 0.0, "shore": 0.0, "space": 0.0, "rustle": 0.0, "surface": "rock"}
	if planet.noise.features != null and planet.noise.features.caves != null and planet.noise.features.caves.cave_at(relative) >= 0:
		return {"wind": 0.05, "shore": 0.0, "space": 0.0, "rustle": 0.0, "cave_drip": 0.2, "cave_wind": 0.12, "surface": "rock"}
	var up: Vector3 = relative.normalized()
	var height: float = planet.noise.height(up)
	var altitude: float = maxf(relative.length() - planet.surface_radius(up), 0.0)
	var air: float = 1.0 - smoothstep(planet.atmosphere_height * 0.3, planet.atmosphere_height, altitude)
	var near_ground: float = 1.0 - smoothstep(20.0, 200.0, altitude)
	var slope: float = planet.noise.slope(up, height)
	var forest: float = DawnBiomes.forest_cover(height, planet.noise.temperature(up, height), planet.noise.moisture(up), planet.noise.woodland(up)) if planet.profile == 0 else 0.0
	forest *= smoothstep(16.0, 60.0, height) * (1.0 - smoothstep(1350.0, 1600.0, height))
	forest *= smoothstep(0.16, 0.3, planet.noise.temperature(up, height)) * (1.0 - smoothstep(0.4, 0.65, slope))
	var coast: float = 0.0
	if planet.profile != 1 and height < 60.0:
		var forward: Vector3 = SurfaceSites.tangent_forward(up)
		var right: Vector3 = forward.cross(up)
		# 海浪依据附近水面采样，避免仅凭本地海拔在内陆盆地播放。
		for index: int in 8:
			var angle: float = TAU * index / 8.0
			var direction: Vector3 = (up * planet.radius + (forward * cos(angle) + right * sin(angle)) * 160.0).normalized()
			if planet.noise.height(direction) < -0.5:
				coast += 0.125
		coast *= near_ground
	var surface: String = "grass"
	if (planet.profile == 2 or (planet.profile == 0 and height > 1550.0)) and slope < 0.4:
		surface = "snow"
	elif planet.profile == 1 or height < 22.0:
		surface = "sand"
	elif slope > 0.28:
		surface = "rock"
	return {"wind": air * lerpf(0.14, 0.32, smoothstep(100.0, 1800.0, height)) * lerpf(1.0, 0.65, forest), "shore": coast * 0.4, "space": (1.0 - air) * 0.12, "rustle": forest * near_ground * 0.24, "surface": surface}


func _process(delta: float) -> void:
	var planet: Planet = _player.current_planet()
	var relative: Vector3 = _player.global_position - planet.global_position
	_sample_elapsed += delta
	if _sample_elapsed >= 0.2 or planet != _previous_planet:
		_environment = environment_at(planet, relative)
		_sample_elapsed = 0.0
		if _director == null:
			_director = get_tree().get_first_node_in_group("sky_director") as SkyDirector
		# 雨声只在晨的地面附近，越往高处越轻。
		var altitude: float = relative.length() - planet.surface_radius(relative.normalized())
		_environment["rain"] = _director.rain * (1.0 - smoothstep(150.0, 1500.0, altitude)) * 0.42 if _director != null and planet.profile == 0 and PlayerTraversal.cave_at(_player) == -1 else 0.0
		var sky_height: float = relative.normalized().dot(_director.sun_direction) if _director != null else 1
		_environment["night_insects"] = (1 - smoothstep(-0.18, -0.03, sky_height)) * (1 - smoothstep(10, 100, altitude)) * 0.08 if planet.profile == 0 and _environment.get("surface", "") == "grass" else 0.0
		var sites: CivilizationSites = planet.get_node_or_null("CivilizationSites") as CivilizationSites
		var proximity: float = sites.ruin_proximity(relative) if sites != null else 0.0
		_environment["ruin_wind"] = proximity * (0.1 + (_director.wind_strength * 0.08 if _director != null else 0)) if PlayerTraversal.cave_at(_player) < 0 else 0.0
		var high: float = smoothstep(120, 550, altitude) + smoothstep(1300, 2100, relative.length() - planet.radius)
		_environment["high_wind"] = minf(high, 1) * 0.2 if _player.mode != StarSeaPlayer.Mode.GLIDE and not LandingPads.on_platform(planet, relative) and PlayerTraversal.cave_at(_player) < 0 else 0.0
		_environment["interior"] = 2 if PlayerTraversal.cave_at(_player) >= 0 else (1 if sites != null and sites.indoors(relative) else 0)
	update_reverb(delta, int(_environment.get("interior", 0)))
	for kind: String in _loops:
		var audio: AudioStreamPlayer = _loops[kind]
		var attenuation: float = db_to_linear(-8 * _director.echo_blend) if _director != null and kind in ["wind", "cave_wind", "ruin_wind", "high_wind"] else 1.0
		audio.volume_linear = lerpf(audio.volume_linear, float(_environment.get(kind, 0.0)) * attenuation, 1.0 - exp(-delta * 1.6))
	var distance: float = relative.distance_to(_previous_relative) if planet == _previous_planet else INF
	_previous_planet = planet
	_previous_relative = relative
	if _player.mode == StarSeaPlayer.Mode.WALK and _player.is_on_floor() and distance < 2.0:
		_step_distance += distance
		var stride: float = 2.45 if _player.velocity.length() > 5.5 else 1.65
		if _step_distance >= stride:
			_step_distance = fmod(_step_distance, stride)
			var variant: int = (randi_range(1, 2) + _last_variant + 3) % 3
			_last_variant = variant
			_step.stream = (_steps[_environment.get("surface", "grass")] as Array[AudioStream])[variant]
			_step.pitch_scale = randf_range(0.94, 1.06)
			_step.play()
	else:
		_step_distance = 0.0


func _exit_tree() -> void:
	for child: Node in get_children():
		var audio: AudioStreamPlayer = child as AudioStreamPlayer
		if audio != null:
			audio.stop()
			audio.stream = null


func update_reverb(delta: float, interior: int) -> void:
	if _reverb == null:
		return
	var room: float = [0.1, 0.45, 0.8][interior]
	var wet: float = [0.0, 0.15, 0.35][interior]
	_reverb.room_size = move_toward(_reverb.room_size, room, delta * 0.7)
	_reverb.wet = move_toward(_reverb.wet, wet, delta * 0.35)
