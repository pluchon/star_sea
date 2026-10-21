class_name TravelJournal
extends Node

signal changed
var discovered: Array[String] = []
var sites: Dictionary = {}
var _planet: Planet
var _player: StarSeaPlayer
var _elapsed: float = 0.0
var _capture_queue: Array[Dictionary] = []
var _capturing: bool = false
var _notice: CanvasLayer
var _title: Label
var _notice_age: float = 10.0
var _sound: AudioStreamPlayer


func _ready() -> void:
	_planet = get_parent() as Planet
	_player = _planet.get_parent().get_parent().get_node("Player") as StarSeaPlayer
	sites = JournalSites.catalog(_planet)
	_notice = CanvasLayer.new()
	_notice.layer = 5
	add_child(_notice)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_title.offset_left = -320
	_title.offset_right = 320
	_title.offset_top = -120
	_title.offset_bottom = -80
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(1, 0.94, 0.83))
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI"])
	_title.add_theme_font_override("font", font)
	_notice.add_child(_title)
	_sound = AudioStreamPlayer.new()
	_sound.volume_db = -24
	if ResourceLoader.exists("res://audio/discover.wav"):
		_sound.stream = load("res://audio/discover.wav") as AudioStream
	add_child(_sound)
	(_planet.get_node("BeaconTowers") as BeaconTowers).lit_changed.connect(func(id: int) -> void: discover("beacon_" + str(id + 1)))
	(_planet.get_node("EchoSystem") as EchoSystem).completed.connect(func(_id: String) -> void: changed.emit())
	changed.connect(refresh_map)


func _process(delta: float) -> void:
	_notice_age += delta
	_title.modulate.a = minf(smoothstep(0, 0.6, _notice_age), 1 - smoothstep(3, 3.8, _notice_age))
	for record: Dictionary in _capture_queue:
		record["wait"] = float(record["wait"]) - delta
	if not _capture_queue.is_empty() and not _capturing and float(_capture_queue[0]["wait"]) <= 0:
		var item: Dictionary = _capture_queue.pop_front()
		capture(item["id"])
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0
	if _player.current_planet() != _planet:
		return
	var at: Vector3 = _player.global_position - _planet.global_position
	var caves: CaveSystem = _planet.get_node("CaveSystem") as CaveSystem
	if caves.data.cave_at(at) >= 0:
		discover("temple")
	for id: String in sites:
		if id.begins_with("beacon_") or id == "temple":
			continue
		var site: Dictionary = sites[id]
		if at.distance_to(Transform3D(site["frame"]).origin) < float(site["radius"]):
			discover(id)


func discover(id: String, notify: bool = true) -> void:
	if not sites.has(id) or discovered.has(id):
		return
	discovered.append(id)
	if notify:
		_title.text = sites[id]["name"]
		_notice_age = 0
		if _sound.stream != null:
			_sound.play()
		_capture_queue.append({"id": id, "wait": 1.5})
	changed.emit()
	if notify:
		JourneyStore.autosave(_planet.get_parent().get_parent())


func backfill() -> void:
	for id: int in (_planet.get_node("BeaconTowers") as BeaconTowers).lit:
		discover("beacon_" + str(id + 1), false)
	refresh_map()


func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_capturing = true
	var hud: CanvasLayer = _planet.get_parent().get_parent().get_node("HUD") as CanvasLayer
	var was_visible: bool = hud.visible
	hud.visible = false
	_notice.visible = false
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.resize(384, 216, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute("user://journal")
	image.save_png("user://journal/" + id + ".png")
	hud.visible = was_visible
	_notice.visible = true
	_capturing = false


func refresh_map() -> void:
	var atlas: TerrainAtlas = _planet.get_parent().get_parent().get_node_or_null("HUD/Layout/TerrainAtlas") as TerrainAtlas
	if atlas == null or atlas.global_view == null:
		return
	var marks: Array[Dictionary] = []
	for id: String in discovered:
		if sites.has(id):
			marks.append({"direction": Transform3D(sites[id]["frame"]).origin.normalized(), "echo": not String(sites[id]["echo"]).is_empty()})
	for view: TerrainMapView in [atlas.global_view, atlas.local_view]:
		view.discoveries = marks
		view.queue_redraw()
	atlas.globe_view.discoveries = marks
	atlas.globe_view.refresh()


static func valid_ids(value: Variant, allowed: Array) -> bool:
	if not value is Array or (value as Array).size() > allowed.size():
		return false
	var unique: Dictionary = {}
	for item: Variant in value:
		if not item is String or not allowed.has(item) or unique.has(item):
			return false
		unique[item] = true
	return true
