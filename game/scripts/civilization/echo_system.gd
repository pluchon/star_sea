class_name EchoSystem
extends Node3D

signal completed(id: String)
var seen: Array[String] = []
var anchors: Dictionary = {}
var active: String = ""
var elapsed: float = 0.0
var blend: float = 0.0
var frozen: bool = false
var _planet: Planet
var _player: StarSeaPlayer
var _actors: Array[EchoFigure] = []
var _stage: Node3D
var _hints: Dictionary = {}
var _dwell: Dictionary = {}
var _armed: Dictionary = {}
var _restore: float = 0.0
var _sample_clock: float = 0.0
var _abort_at: float = -1.0
var _abort_elapsed: float = 0.0


func _ready() -> void:
	_planet = get_parent() as Planet
	_player = _planet.get_parent().get_parent().get_node("Player") as StarSeaPlayer
	anchors = JournalSites.anchors(_planet, JournalSites.catalog(_planet))
	for id: String in anchors:
		_armed[id] = true
		var hint: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1, 0.7, 0.3, 0.6)
		sphere.material = material
		hint.mesh = sphere
		hint.position = Transform3D(anchors[id]).origin + Transform3D(anchors[id]).basis.y * 1.0
		hint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hint.visibility_range_end = 250
		add_child(hint)
		var cloud: MultiMeshInstance3D = MultiMeshInstance3D.new()
		var points: MultiMesh = MultiMesh.new()
		points.transform_format = MultiMesh.TRANSFORM_3D
		var grain: SphereMesh = SphereMesh.new()
		grain.radius = 0.025
		grain.height = 0.05
		grain.radial_segments = 6
		grain.rings = 2
		grain.material = material
		points.mesh = grain
		points.instance_count = 16
		for i: int in 16:
			var angle: float = i * 2.39996
			points.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cos(angle) * 0.45, i / 16.0 * 1.2 - 0.6, sin(angle) * 0.45)))
		cloud.multimesh = points
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.visibility_range_end = 250
		hint.add_child(cloud)
		_hints[id] = hint


func eligible(id: String) -> bool:
	if id == "dawn_watcher":
		var towers: BeaconTowers = _planet.get_node("BeaconTowers") as BeaconTowers
		return towers.lit.has(towers.towers.size() - 1)
	if id == "dawn_ending":
		var ending: EndingDirector = _planet.get_node_or_null("EndingDirector") as EndingDirector
		return ending != null and ending.awakened
	return true


func _process(delta: float) -> void:
	if frozen:
		return
	var sky: SkyDirector = _planet.get_parent().get_parent().get_node("SkyDirector") as SkyDirector
	var ticking: bool = not sky.time_paused
	if not ticking:
		return
	_sample_clock += delta
	for id: String in _hints:
		var hint: MeshInstance3D = _hints[id]
		hint.visible = not seen.has(id) and id != active and eligible(id)
		hint.position = Transform3D(anchors[id]).origin + Transform3D(anchors[id]).basis.y * (1.2 + sin(_sample_clock) * 0.2)
		hint.basis = Transform3D(anchors[id]).basis * Basis(Vector3.UP, _sample_clock * 0.4)
	if not active.is_empty():
		elapsed += delta
		if _abort_at >= 0:
			_abort_elapsed += delta
		show_time(elapsed)
		var duration: float = EchoScripts.script_for(active)["duration"]
		var gap: float = (_player.global_position - _planet.global_position).distance_to(Transform3D(anchors[active]).origin)
		if gap > float(EchoScripts.script_for(active)["radius"]) * 2 and _abort_at < 0:
			_abort_at = elapsed
		if elapsed >= duration + 5 or _abort_elapsed >= 2:
			finish()
	else:
		_restore = maxf(_restore - delta, 0)
		blend = _restore / 3
		for id: String in anchors:
			var gap: float = (_player.global_position - _planet.global_position).distance_to(Transform3D(anchors[id]).origin)
			var radius: float = EchoScripts.script_for(id)["radius"]
			if gap > radius:
				_armed[id] = true
				_dwell[id] = 0.0
				continue
			var grounded: bool = _player.mode == StarSeaPlayer.Mode.WALK and _player.is_on_floor()
			if not grounded or _player.velocity.length() >= 0.5 or not eligible(id) or not _armed[id] or _restore > 0:
				_dwell[id] = 0.0
				continue
			_dwell[id] = float(_dwell.get(id, 0.0)) + delta
			if float(_dwell[id]) >= (3.0 if seen.has(id) else 2.0):
				begin(id)
				break
	sky.echo_blend = blend


func begin(id: String) -> void:
	if not active.is_empty():
		return
	active = id
	elapsed = 0
	_abort_at = -1
	_abort_elapsed = 0
	_armed[id] = false
	_stage = Node3D.new()
	_stage.transform = anchors[id]
	add_child(_stage)
	for record: Dictionary in EchoScripts.script_for(id)["actors"]:
		var figure: EchoFigure = EchoFigure.new()
		_stage.add_child(figure)
		figure.build(record["child"])
		if record["pose"] == "carry":
			figure.add_bundle()
		_actors.append(figure)
	var music: Node = _planet.get_parent().get_parent().get_node_or_null("MusicDirector")
	if music != null:
		music.call("play_echo", EchoScripts.script_for(id)["music"])
	show_time(0)


func show_time(time: float) -> void:
	if active.is_empty():
		return
	var script: Dictionary = EchoScripts.script_for(active)
	var story_time: float = maxf((_abort_at if _abort_at >= 0 else time) - 3, 0)
	blend = minf(clampf((time - 1.5) / 2, 0, 1), 1 - smoothstep(float(script["duration"]) + 3, float(script["duration"]) + 5, time))
	for i: int in _actors.size():
		var record: Dictionary = script["actors"][i]
		var sample: Dictionary = EchoScripts.sample(record, story_time)
		var figure: EchoFigure = _actors[i]
		var at: Vector3 = sample["position"]
		# 地表站位逐点投影；洞底、塔冠和断口使用各自真实建筑面。
		if active in ["dawn_daily", "dawn_departure"]:
			var frame: Transform3D = anchors[active]
			var ground: Vector3 = frame * at
			ground = ground.normalized() * (_planet.surface_radius(ground.normalized()) + 0.04)
			at = frame.affine_inverse() * ground
		figure.position = at
		figure.basis = Basis.looking_at(sample["forward"], Vector3.UP)
		figure.set_pose(sample["pose"], sample["pose_time"] if frozen else -1)
		if figure.bundle != null:
			figure.bundle.visible = sample["pose"] == "carry"
		if frozen and figure.animation != null:
			figure.animation.pause()
		figure.particles.speed_scale = 0 if frozen else 1
		var visible_amount: float = smoothstep(float(record["start"]), float(record["start"]) + 1.5, story_time) * (1 - smoothstep(float(record["end"]), float(record["end"]) + 2, story_time))
		figure.presence(visible_amount * (1 - clampf(_abort_elapsed / 2, 0, 1)), time)
	if active == "dawn_faith":
		(_planet.get_node("CaveSystem") as CaveSystem).set_mural_progress(clampf(story_time / 18, 0, 1))
	if active == "dawn_watcher":
		(_planet.get_node("SkyLadder") as SkyLadder).echo_rise = clampf(story_time / 15, 0, 1)
		(_planet.get_node("BeaconTowers") as BeaconTowers).echo_fire = sin(clampf((story_time - 11) / 3, 0, 1) * PI)
	if active == "dawn_ending" and story_time >= 19:
		(_planet.get_node("EndingDirector") as EndingDirector).illuminate(clampf((story_time - 19) / 6, 0, 1))


func finish() -> void:
	var id: String = active
	if id.is_empty():
		return
	if not seen.has(id):
		seen.append(id)
	active = ""
	_stage.queue_free()
	_stage = null
	_actors.clear()
	_restore = 3
	(_planet.get_node("SkyLadder") as SkyLadder).echo_rise = -1
	(_planet.get_node("BeaconTowers") as BeaconTowers).echo_fire = 0
	(_planet.get_node("CaveSystem") as CaveSystem).set_mural_progress(0)
	if id == "dawn_ending":
		(_planet.get_node("EndingDirector") as EndingDirector).illuminate(1)
	completed.emit(id)
	JourneyStore.autosave(_planet.get_parent().get_parent())


func restore_seen(value: Array) -> void:
	if _stage != null:
		_stage.queue_free()
	_stage = null
	_actors.clear()
	active = ""
	seen.assign(value)
	_restore = 0
	blend = 0
	_dwell.clear()
	(_planet.get_parent().get_parent().get_node("SkyDirector") as SkyDirector).echo_blend = 0
