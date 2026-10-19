class_name Soundscape
extends Node

var _wind: AudioStreamPlayer
var _shore: AudioStreamPlayer
var _space: AudioStreamPlayer
var _step: AudioStreamPlayer
var _player: StarSeaPlayer
var _step_distance: float = 0.0
var _previous: Vector3


func _ready() -> void:
	# 无界面逻辑验证不创建声音；固定步长会快于音频设备的实际混音时钟。
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_player = get_parent().get_node("Player") as StarSeaPlayer
	_wind = _loop("wind", -22.0)
	_shore = _loop("shore", -80.0)
	_space = _loop("space", -80.0)
	_step = AudioStreamPlayer.new()
	_step.stream = load("res://audio/step.wav") as AudioStream
	_step.volume_db = -18.0
	add_child(_step)
	_previous = _player.global_position


func _loop(filename: String, volume: float) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = (load("res://audio/" + filename + ".wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	player.play()
	return player


func _process(delta: float) -> void:
	var planet: Planet = _player.current_planet()
	var offset: Vector3 = _player.global_position - planet.global_position
	var up: Vector3 = offset.normalized()
	var height: float = planet.noise.height(up)
	var altitude: float = maxf(offset.length() - planet.radius - maxf(height, 0.0), 0.0)
	var atmosphere: float = 1.0 - smoothstep(planet.atmosphere_height * 0.3, planet.atmosphere_height, altitude)
	var coast: float = (1.0 - smoothstep(0.0, 40.0, absf(height))) * (1.0 - smoothstep(10.0, 150.0, altitude))
	if planet.profile == 1:
		coast = 0.0
	_wind.volume_db = lerpf(_wind.volume_db, lerpf(-80.0, -17.0, atmosphere), minf(delta * 2.0, 1.0))
	_shore.volume_db = lerpf(_shore.volume_db, lerpf(-80.0, -17.0, coast), minf(delta * 2.0, 1.0))
	_space.volume_db = lerpf(_space.volume_db, lerpf(-25.0, -80.0, atmosphere), minf(delta * 2.0, 1.0))
	var distance: float = _player.global_position.distance_to(_previous)
	_previous = _player.global_position
	if _player.mode == StarSeaPlayer.Mode.WALK and _player.is_on_floor() and distance < 2.0:
		_step_distance += distance
		if _step_distance > 1.8:
			_step_distance = 0.0
			_step.pitch_scale = randf_range(0.85, 1.15)
			_step.play()
	else:
		_step_distance = 0.0


func _exit_tree() -> void:
	for player: AudioStreamPlayer in [_wind, _shore, _space, _step]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
