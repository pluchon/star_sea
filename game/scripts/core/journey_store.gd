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
	var traversing: bool = player.mode in [StarSeaPlayer.Mode.CLIMB, StarSeaPlayer.Mode.GLIDE]
	var position: Vector3 = player.global_position - planet.global_position
	if traversing:
		position = player.traversal.last_grounded if player.traversal.last_ground_seed == planet.planet_seed else planet.site["direction"] * (planet.surface_radius(planet.site["direction"]) + 0.05)
	config.set_value("journey", "position", position)
	var saved_up: Vector3 = position.normalized() if traversing else player.global_basis.y
	var saved_forward: Vector3 = (-player.global_basis.z).slide(saved_up).normalized() if traversing else -player.global_basis.z
	if saved_forward.length_squared() < 0.5:
		saved_forward = SurfaceSites.tangent_forward(saved_up)
	config.set_value("journey", "forward", saved_forward)
	config.set_value("journey", "up", saved_up)
	config.set_value("journey", "pitch", player.head_pitch())
	config.set_value("journey", "mode", int(StarSeaPlayer.Mode.WALK if traversing else player.mode))
	config.set_value("journey", "third_person", player.third_person)
	config.set_value("journey", "sun", director.sun_direction)
	config.set_value("journey", "boarded", player.mode == StarSeaPlayer.Mode.FLY)
	var ship: StarSeaShip = player.ship
	var ship_planet: Planet = planet if player.mode == StarSeaPlayer.Mode.FLY else ship.planet
	var ship_transform: Transform3D = ship.target if ship.state == StarSeaShip.State.CALLED else Transform3D(ship.global_basis, ship.global_position - ship_planet.global_position)
	config.set_value("journey", "ship_planet_seed", ship_planet.planet_seed)
	config.set_value("journey", "ship_position", ship_transform.origin)
	config.set_value("journey", "ship_forward", -ship_transform.basis.z)
	config.set_value("journey", "ship_up", ship_transform.basis.y)
	var atlas: TerrainAtlas = scene.get_node_or_null("HUD/Layout/TerrainAtlas") as TerrainAtlas
	if atlas != null:
		config.set_value("journey", "flags", atlas.flags)
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
	var perspective: Variant = config.get_value("journey", "third_person", false)
	if not perspective is bool:
		return ERR_INVALID_DATA
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
	# 旗子是可选字段，旧存档没有；有的话每一项都必须是有限的单位方向。
	var flags_value: Variant = config.get_value("journey", "flags", [])
	if not flags_value is Array or (flags_value as Array).size() > TerrainAtlas.MAX_FLAGS:
		return ERR_INVALID_DATA
	var flags: Array[Vector3] = []
	for item: Variant in flags_value as Array:
		if not item is Vector3 or not (item as Vector3).is_finite() or absf((item as Vector3).length() - 1.0) > 0.01:
			return ERR_INVALID_DATA
		flags.append((item as Vector3).normalized())
	var boarded: Variant = config.get_value("journey", "boarded", mode == StarSeaPlayer.Mode.FLY)
	if not boarded is bool or boarded != (mode == StarSeaPlayer.Mode.FLY):
		return ERR_INVALID_DATA
	var ship_data: Dictionary = {}
	var ship_fields: Array[String] = ["ship_planet_seed", "ship_position", "ship_forward", "ship_up"]
	var ship_field_count: int = 0
	for key: String in ship_fields:
		if config.has_section_key("journey", key):
			ship_field_count += 1
	if ship_field_count != 0 and ship_field_count != ship_fields.size():
		return ERR_INVALID_DATA
	if ship_field_count > 0:
		var ship_seed: Variant = config.get_value("journey", "ship_planet_seed")
		var ship_position: Variant = config.get_value("journey", "ship_position")
		var ship_forward: Variant = config.get_value("journey", "ship_forward")
		var ship_up: Variant = config.get_value("journey", "ship_up")
		if not ship_seed is int or not ship_position is Vector3 or not ship_forward is Vector3 or not ship_up is Vector3:
			return ERR_INVALID_DATA
		var ship_planet: Planet
		for node: Node in scene.get_tree().get_nodes_in_group("planets"):
			if (node as Planet).planet_seed == ship_seed:
				ship_planet = node as Planet
		if ship_planet == null or not (ship_position as Vector3).is_finite() or not (ship_forward as Vector3).is_finite() or not (ship_up as Vector3).is_finite():
			return ERR_INVALID_DATA
		if (ship_position as Vector3).length() < ship_planet.radius - 450.0 or (ship_position as Vector3).length() > 100000000.0:
			return ERR_INVALID_DATA
		if absf((ship_forward as Vector3).length() - 1.0) > 0.01 or absf((ship_up as Vector3).length() - 1.0) > 0.01 or absf((ship_forward as Vector3).dot(ship_up)) > 0.01:
			return ERR_INVALID_DATA
		ship_data = {"planet": ship_planet, "transform": Transform3D(Basis.looking_at(ship_forward, ship_up), ship_position)}
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	if player.transition_busy:
		return ERR_BUSY
	var surface: float = planet.surface_radius(location.normalized())
	location = location.normalized() * maxf(location.length(), surface + (0.05 if mode == StarSeaPlayer.Mode.WALK else 1.2))
	player.place_at(planet.global_position + location, forward.normalized(), up.normalized())
	player.mode = mode as StarSeaPlayer.Mode
	if not boarded:
		if ship_data.is_empty():
			player.park_ship_nearby()
		else:
			player.ship.park(ship_data["planet"], ship_data["transform"])
	player.set_head_pitch(pitch)
	player.set_third_person(perspective)
	(scene.get_node("SkyDirector") as SkyDirector).sun_direction = sun.normalized()
	var atlas: TerrainAtlas = scene.get_node_or_null("HUD/Layout/TerrainAtlas") as TerrainAtlas
	if atlas != null:
		atlas.set_flags(flags)
	return OK
