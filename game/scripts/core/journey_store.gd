class_name JourneyStore
extends RefCounted

const PATH: String = "user://journey.cfg"


static func save(scene: Node, path: String = PATH) -> Error:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = player.current_planet()
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var config: ConfigFile = ConfigFile.new()
	config.set_value("journey", "version", 1)
	config.set_value("journey", "planet_seed", planet.planet_seed)
	# 保存相对天体的坐标，避免把浮动原点偏移写入存档。
	config.set_value("journey", "position", player.global_position - planet.global_position)
	config.set_value("journey", "forward", -player.global_basis.z)
	config.set_value("journey", "up", player.global_basis.y)
	config.set_value("journey", "pitch", player.head_pitch())
	config.set_value("journey", "mode", int(player.mode))
	config.set_value("journey", "sun", director.sun_direction)
	var error: Error = config.save(path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))


static func restore(scene: Node, path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK:
		return error
	if config.get_value("journey", "version", 0) != 1:
		return ERR_FILE_UNRECOGNIZED
	var seed_data: Variant = config.get_value("journey", "planet_seed", null)
	var mode_data: Variant = config.get_value("journey", "mode", null)
	var pitch_data: Variant = config.get_value("journey", "pitch", null)
	if not seed_data is int or not mode_data is int or (not pitch_data is float and not pitch_data is int):
		return ERR_INVALID_DATA
	var seed_value: int = seed_data
	var planet: Planet
	for node: Node in scene.get_tree().get_nodes_in_group("planets"):
		if (node as Planet).planet_seed == seed_value:
			planet = node as Planet
	if planet == null:
		return ERR_INVALID_DATA
	var position_value: Variant = config.get_value("journey", "position", null)
	var forward_value: Variant = config.get_value("journey", "forward", null)
	var up_value: Variant = config.get_value("journey", "up", null)
	var sun_value: Variant = config.get_value("journey", "sun", null)
	if not position_value is Vector3 or not forward_value is Vector3 or not up_value is Vector3 or not sun_value is Vector3:
		return ERR_INVALID_DATA
	var location: Vector3 = position_value
	var forward: Vector3 = forward_value
	var up: Vector3 = up_value
	var sun: Vector3 = sun_value
	var pitch: float = pitch_data
	var mode: int = mode_data
	if not location.is_finite() or not forward.is_finite() or not up.is_finite() or not sun.is_finite() or not is_finite(pitch):
		return ERR_INVALID_DATA
	if forward.length_squared() < 0.5 or up.length_squared() < 0.5 or sun.length_squared() < 0.5 or forward.cross(up).length_squared() < 0.1:
		return ERR_INVALID_DATA
	if forward.length_squared() > 1.5 or up.length_squared() > 1.5 or sun.length_squared() > 1.5 or absf(pitch) > deg_to_rad(89.0):
		return ERR_INVALID_DATA
	if location.length() < planet.radius - 450.0 or location.length() > 100000000.0 or mode < 0 or mode > 1:
		return ERR_INVALID_DATA
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var surface: float = planet.surface_radius(location.normalized())
	location = location.normalized() * maxf(location.length(), surface + (0.05 if mode == StarSeaPlayer.Mode.WALK else 1.2))
	player.place_at(planet.global_position + location, forward.normalized(), up.normalized())
	player.mode = mode as StarSeaPlayer.Mode
	player.set_head_pitch(pitch)
	(scene.get_node("SkyDirector") as SkyDirector).sun_direction = sun.normalized()
	return OK
