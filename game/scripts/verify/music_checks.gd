extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var director: MusicDirector = scene.get_node("MusicDirector") as MusicDirector
	director.auto_context = false
	director.set_process(false)
	var cases: Array = [[0, 0, 8000, 0.8, 0, false, false, "dawn_day"], [0, 0, 8000, 0.1, 0, false, false, "dawn_dusk"], [2, 0, 8000, -0.2, 0, false, false, "night"], [0, 0, 8000, 0.5, 0.6, false, false, "rain"], [0, -50, 8000, 0.8, 0, true, false, "cave"], [0, 9000, 8000, 0.8, 0, false, false, "space"], [0, 9000, 8000, 0.8, 0, false, true, "ending"]]
	for item: Array in cases:
		check(MusicDirector.select_context(item[0], item[1], item[2], item[3], item[4], item[5], item[6]) == item[7], "情境判断错误：" + item[7])
	var count: int = 0
	for group: String in director.tracks:
		count += director.tracks[group].size()
		var previous: String = ""
		for i: int in 30:
			var selected: String = director.choose(group)
			check(ResourceLoader.exists(selected), "曲目不可读取：" + selected)
			if director.tracks[group].size() > 1:
				check(selected != previous, "情境连续重复同一首。")
			previous = selected
	check(count == 27, "曲目数量不是 27：%d" % count)
	for group: String in MusicDirector.CONTEXTS:
		for i: int in 50:
			var interval: float = director.quiet_interval(group)
			check(interval >= (80 if group == "cave" else (60 if group in ["night", "rain"] else 40)) and interval <= (240 if group == "cave" else (150 if group in ["night", "rain"] else 120)), "安静间隔超出范围。")
	director._start("dawn_day")
	director.tick(1.5)
	check(is_equal_approx(director.audio.volume_linear, 0.5), "开始播放没有三秒淡入。")
	director.tick(1.5)
	var stream: AudioStream = director.audio.stream
	director.update_context("rain")
	director.tick(1)
	check(director.current == "dawn_day" and director.audio.stream == stream, "普通情境变化打断曲目。")
	director.update_context("cave")
	director.tick(2)
	check(director.current == "dawn_day" and is_equal_approx(director.audio.volume_linear, 0.5), "进洞没有按四秒淡出。")
	director.tick(2)
	check(director.current.is_empty() and not director.audio.playing and director.quiet >= 80, "进洞淡出后没有安静计时。")
	director._start("dawn_day")
	director.tick(3)
	director.play_echo("echo_daily")
	director.tick(1)
	check(director.current == "dawn_day" and is_equal_approx(director.audio.volume_linear, 0.5), "回声没有两秒淡出。")
	director.tick(1)
	check(director.current == "echo_daily", "回声未接续播放。")
	director.tick(director.remaining + 0.1)
	check(director.current.is_empty() and director.quiet >= 80, "回声播完没有重新安静计时。")
	director._start("echo_watcher")
	director.end_echo()
	director.tick(2)
	check(director.current.is_empty(), "回声提前退出未淡出。")
	director.update_context("ending")
	check(director.current == "ending", "结局没有从头开始。")
	check(director.choose("missing_group").is_empty(), "缺失情境没有静默处理。")
	var volume: float = StarSeaSettings.music_volume
	StarSeaSettings.music_volume = 0
	StarSeaSettings.apply_music_volume()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "音乐零音量没有静音总线。")
	StarSeaSettings.music_volume = volume
	StarSeaSettings.apply_music_volume()
	var sound: Soundscape = scene.get_node("Soundscape") as Soundscape
	for interior: int in [2, 1, 0]:
		sound.update_reverb(1, interior)
		check(is_equal_approx(sound._reverb.wet, [0.0, 0.15, 0.35][interior]) and is_equal_approx(sound._reverb.room_size, [0.1, 0.45, 0.8][interior]), "混响未在一秒内过渡。")
	for node: Node in scene.find_children("*", "AudioStreamPlayer*", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			check(node.get("bus") != &"Master", "实际声源仍然直接进入 Master：" + str(node.get_path()))
	if DisplayServer.get_name() != "headless":
		# 只录音乐总线，验证真实解码、播放器和混音链路。
		var bus: int = AudioServer.get_bus_index("Music")
		var effect: AudioEffectRecord = AudioEffectRecord.new()
		effect.format = AudioStreamWAV.FORMAT_16_BITS
		var effect_index: int = AudioServer.get_bus_effect_count(bus)
		AudioServer.add_bus_effect(bus, effect)
		director._start("dawn_day")
		director.audio.volume_linear = 1
		effect.set_recording_active(true)
		await create_timer(5).timeout
		effect.set_recording_active(false)
		var recording: AudioStreamWAV = effect.get_recording()
		var recording_path: String = ProjectSettings.globalize_path("res://../test-output/wanderer/12-audio/music-mix.wav")
		DirAccess.make_dir_recursive_absolute(recording_path.get_base_dir())
		check(recording.get_length() >= 4.0 and recording.save_to_wav(recording_path) == OK, "实际音乐混音录制失败。")
		AudioServer.remove_bus_effect(bus, effect_index)
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "context_cases": cases.size(), "music_tracks": count, "reverb_transition_s": 1}
	var output: String = ProjectSettings.globalize_path("res://../test-output/wanderer/music_checks.json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
