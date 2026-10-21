class_name EchoPersistenceChecks
extends RefCounted


static func run(scene: Node) -> Dictionary:
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var journal: TravelJournal = planet.get_node("TravelJournal") as TravelJournal
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	var ending: EndingDirector = planet.get_node("EndingDirector") as EndingDirector
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var original: String = "user://verify_echo_original.cfg"
	var path: String = "user://verify_echo.cfg"
	JourneyStore.save(scene, original)
	journal.discovered.assign(["town", "temple"])
	echoes.seen.assign(EchoScripts.IDS + ["dawn_ending"])
	ending.light_path = Vector3(0.2, 0.8, -0.3).normalized()
	ending.ending_seen = true
	JourneyStore.save(scene, path)
	journal.discovered.clear()
	echoes.seen.clear()
	ending.ending_seen = false
	ending.light_path = Vector3.ZERO
	var result: Error = JourneyStore.restore(scene, path)
	var roundtrip: bool = result == OK and journal.discovered.has("town") and echoes.seen.size() == 5 and ending.ending_seen and ending.light_path.length() > 0.99
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	var invalid: Array = [
		["discovered", 4], ["discovered", ["town", "town"]], ["discovered", ["other"]], ["discovered", [1]],
		["echoes_seen", 1], ["echoes_seen", ["dawn_daily", "dawn_daily"]], ["echoes_seen", ["other"]],
		["ending_seen", "yes"], ["light_path", Vector3(NAN, 0, 0)], ["light_path", Vector3.ONE], ["light_path", []]]
	var rejected: int = 0
	for entry: Array in invalid:
		config.load(path)
		var old: Variant = config.get_value("journey", entry[0])
		config.set_value("journey", entry[0], entry[1])
		config.save(path)
		var before: Transform3D = player.global_transform
		var before_journal: Array[String] = journal.discovered.duplicate()
		var before_echoes: Array[String] = echoes.seen.duplicate()
		var before_path: Vector3 = ending.light_path
		if JourneyStore.restore(scene, path) == ERR_INVALID_DATA and player.global_transform.is_equal_approx(before) and journal.discovered == before_journal and echoes.seen == before_echoes and ending.light_path == before_path:
			rejected += 1
		config.set_value("journey", entry[0], old)
		config.save(path)
	config.load(original)
	for key: String in ["discovered", "echoes_seen", "ending_seen", "light_path"]:
		config.erase_section_key("journey", key)
	config.save(path)
	var legacy: bool = JourneyStore.restore(scene, path) == OK and echoes.seen.is_empty() and not ending.ending_seen and ending.light_path.is_zero_approx()
	JourneyStore.restore(scene, original)
	for file: String in [original, path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return {"passed": roundtrip and legacy and rejected == invalid.size(), "roundtrip": roundtrip, "legacy": legacy, "invalid_cases": invalid.size(), "invalid_rejected": rejected}
