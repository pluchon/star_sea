class_name MusicDirector
extends Node

const ROOT: String = "res://audio/music/"
const CONTEXTS: Array[String] = ["dawn_day", "dawn_dusk", "night", "rain", "cave", "space", "ending"]
var tracks: Dictionary = {}
var previous: Dictionary = {}
var context: String = "dawn_day"
var current: String = ""
var quiet: float = 8.0
var remaining: float = 0.0
var auto_context: bool = true
var audio: AudioStreamPlayer
var _pending: String = ""
var _fade_out: float = 0.0
var _fade_length: float = 0.0
var _fade_start: float = 0.0
var _fade_in: float = 0.0
var _sample: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	tracks = scan()
	audio = AudioStreamPlayer.new()
	audio.name = "Music"
	audio.bus = "Music"
	audio.volume_linear = 0
	add_child(audio)
	audio.finished.connect(_finished)


static func scan() -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(ROOT)
	if directory != null:
		for entry: String in directory.get_files():
			var file: String = entry.trim_suffix(".import").trim_suffix(".remap")
			if not file.ends_with(".ogg"):
				continue
			var group: String = file.get_basename()
			if not group.begins_with("echo_"):
				group = group.get_slice("_", 0) if not group.begins_with("dawn_") else "dawn_" + group.get_slice("_", 1)
			if not result.has(group):
				result[group] = []
			if not result[group].has(ROOT + file):
				result[group].append(ROOT + file)
	if not result.has("dawn_day") and ResourceLoader.exists(ROOT + "fallback/dawn_theme.wav"):
		result["dawn_day"] = [ROOT + "fallback/dawn_theme.wav"]
	return result


static func select_context(profile: int, altitude: float, atmosphere: float, sun_height: float, rain: float, in_cave: bool, ending: bool) -> String:
	if ending:
		return "ending"
	if in_cave:
		return "cave"
	if altitude > atmosphere:
		return "space"
	if profile == 0 and rain > 0.15:
		return "rain"
	if sun_height < -0.1:
		return "night"
	if profile == 0:
		return "dawn_dusk" if sun_height <= 0.15 else "dawn_day"
	return ""


func sample_context() -> String:
	var scene: Node = get_parent()
	var player: StarSeaPlayer = scene.get_node_or_null("Player") as StarSeaPlayer
	var sky: SkyDirector = scene.get_node_or_null("SkyDirector") as SkyDirector
	if player == null or sky == null:
		return context
	var planet: Planet = player.current_planet()
	var relative: Vector3 = player.global_position - planet.global_position
	var ending: EndingDirector = scene.get_node("Universe/PlanetDawn/EndingDirector") as EndingDirector
	return select_context(planet.profile, relative.length() - planet.surface_radius(relative.normalized()), planet.atmosphere_height, relative.normalized().dot(sky.sun_direction), sky.rain, PlayerTraversal.cave_at(player) >= 0, ending.busy or ending.flight_seconds > 0)


func _process(delta: float) -> void:
	if auto_context:
		_sample += delta
		if _sample >= 0.25:
			_sample = 0
			update_context(sample_context())
	tick(delta)


func update_context(value: String) -> void:
	if context == value:
		return
	context = value
	if value == "ending":
		_request(value, 2.0)
	elif value in ["cave", "space"] and not current.begins_with("echo_"):
		_request("", 4.0)


func quiet_interval(value: String) -> float:
	var interval: float = _rng.randf_range(60, 150) if value in ["night", "rain"] else _rng.randf_range(40, 120)
	return interval * 2 if value == "cave" else interval


func choose(value: String) -> String:
	var candidates: Array = tracks.get(value, []).duplicate()
	if candidates.size() > 1:
		candidates.erase(previous.get(value, ""))
	if candidates.is_empty():
		return ""
	var selected: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
	previous[value] = selected
	return selected


func play_echo(value: String) -> void:
	_request(value, 2.0)


func end_echo() -> void:
	if current.begins_with("echo_") or _pending.begins_with("echo_"):
		_request("", 2.0)


func _request(value: String, fade: float) -> void:
	_pending = value
	if not current.is_empty():
		_fade_start = audio.volume_linear
		_fade_length = fade
		_fade_out = fade
	else:
		_transition()


func _transition() -> void:
	audio.stop()
	current = ""
	remaining = 0
	_fade_out = 0
	var next: String = _pending
	_pending = ""
	quiet = quiet_interval(context)
	if not next.is_empty():
		_start(next)


func _start(value: String) -> void:
	var path: String = choose(value)
	if path.is_empty():
		quiet = quiet_interval(context)
		return
	audio.stream = load(path) as AudioStream
	current = value
	remaining = audio.stream.get_length()
	_fade_in = 0
	audio.volume_linear = 0
	audio.play()


func tick(delta: float) -> void:
	if _fade_out > 0:
		_fade_out = maxf(0, _fade_out - delta)
		audio.volume_linear = _fade_start * _fade_out / _fade_length
		if _fade_out <= 0:
			_transition()
		return
	if not current.is_empty():
		_fade_in = minf(3, _fade_in + delta)
		audio.volume_linear = _fade_in / 3
		remaining -= delta
		if remaining <= 0:
			_finished()
	else:
		quiet -= delta
		if quiet <= 0:
			_start(context)


func _finished() -> void:
	if current.is_empty():
		return
	if _fade_out > 0:
		_transition()
		return
	audio.stop()
	current = ""
	remaining = 0
	quiet = quiet_interval(context)
