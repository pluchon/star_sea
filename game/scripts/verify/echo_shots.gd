class_name EchoShots
extends RefCounted


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	player.mode = StarSeaPlayer.Mode.FLY
	player.controls_enabled = false
	player.set_third_person(false)
	director.time_paused = true
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	var id: String = "dawn_faith" if name == "s47_echo_temple" else "dawn_daily"
	if name == "s46b_echo_departure":
		id = "dawn_departure"
	elif name == "s46c_echo_watcher":
		id = "dawn_watcher"
	if name == "s61_light_path":
		id = "dawn_ending"
	var frame: Transform3D = echoes.anchors[id]
	var eye: Vector3 = frame * Vector3(7, 1.9, 9)
	var target: Vector3 = frame * Vector3(0, 1, 0)
	if name == "s46b_echo_departure":
		eye = frame * Vector3(9, 2.0, 20)
		target = frame * Vector3(0, 2, -3)
	elif name == "s46c_echo_watcher":
		eye = frame * Vector3(3.0, 1.8, 3.5)
		target = frame * Vector3(1.0, 0.8, 0)
		var towers: BeaconTowers = planet.get_node("BeaconTowers") as BeaconTowers
		towers.set_lit([towers.towers.size() - 1])
	if name == "s47_echo_temple":
		eye = frame * Vector3(-7, 2.2, -5)
		target = frame * Vector3(3, 2, 10)
	elif name == "s61_light_path":
		eye = frame * Vector3(8, 3, 12)
		target = frame * Vector3(0, 20, -30)
		var ending: EndingDirector = planet.get_node("EndingDirector") as EndingDirector
		ending.awakened = true
		ending.illuminate(1)
		player.camera.fov = 85
	else:
		echoes.frozen = true
		echoes.begin(id)
		echoes.show_time(15 if name == "s46b_echo_departure" else (16 if name == "s46c_echo_watcher" else 11))
	if name == "s47_echo_temple":
		echoes.frozen = true
		echoes.begin(id)
		echoes.show_time(13)
	player.place_at(planet.to_global(eye - frame.basis.y * 1.62), -frame.basis.z, frame.basis.y)
	player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(target)), frame.basis.y)
	director.set_sun_altitude(frame.basis.y, -frame.basis.z, -18 if name == "s61_light_path" else (75 if name == "s47_echo_temple" else 6))
	director.echo_blend = 1 if name in ["s46_echo_plaza", "s47_echo_temple"] else 0
	if name == "s48_journal":
		var journal: TravelJournal = planet.get_node("TravelJournal") as TravelJournal
		for site: String in ["town", "temple", "temple_hall", "ladder_base", "beacon_1", "canyon"]:
			journal.discover(site, false)
		echoes.seen.assign(["dawn_daily", "dawn_faith"])
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 10
		player.get_tree().current_scene.add_child(layer)
		var page: JournalPage = JournalPage.new()
		page.scene = player.get_tree().current_scene
		page.journal = journal
		var theme: Theme = Theme.new()
		var font: SystemFont = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI"])
		theme.default_font = font
		theme.default_font_size = 18
		page.theme = theme
		layer.add_child(page)
