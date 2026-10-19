class_name SystemChecks
extends RefCounted


static func run(scene: Node3D) -> Dictionary:
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var origin: FloatingOrigin = scene.get_node("FloatingOrigin") as FloatingOrigin
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	player.controls_enabled = false
	var failures: Array[String] = []
	var up: Vector3 = planet.site["direction"]
	var minimum_sun_height: float = INF
	var maximum_sun_height: float = -INF
	for sample: int in 361:
		var direction: Vector3 = director.sun_direction.rotated(Vector3.UP, TAU * float(sample) / 360.0)
		minimum_sun_height = minf(minimum_sun_height, up.dot(direction))
		maximum_sun_height = maxf(maximum_sun_height, up.dot(direction))
	if minimum_sun_height >= -0.12 or maximum_sun_height <= 0.18:
		failures.append("出生点无法经历完整的昼夜。")
	var initial_direction: Vector3 = up
	player.mode = StarSeaPlayer.Mode.FLY
	player.place_at(planet.global_position + up * (planet.surface_radius(up) + 2.0), planet.site["forward"], up)
	var maximum_true_position_error: float = 0.0
	for step: int in 900:
		var before: Vector3 = origin.true_position()
		var local_up: Vector3 = (player.global_position - planet.global_position).normalized()
		var speed: float = clampf(player.global_position.distance_to(planet.global_position) - planet.surface_radius(local_up), 12.0, 30000.0) * 4.0
		player.advance_flight(initial_direction * speed, 1.0 / 60.0)
		var before_recenter: Vector3 = origin.true_position()
		origin._physics_process(1.0 / 60.0)
		maximum_true_position_error = maxf(maximum_true_position_error, origin.true_position().distance_to(before_recenter))
		if origin.true_position().distance_to(before) > 5000.0:
			failures.append("单次飞行位移超出速度上限。")
	var maximum_altitude: float = (player.global_position - planet.global_position).length() - planet.radius
	if maximum_altitude < 200000.0:
		failures.append("飞行未能到达 200 公里高度。")
	player.velocity = Vector3.ZERO
	for step: int in 1800:
		var local_up: Vector3 = (player.global_position - planet.global_position).normalized()
		var altitude: float = player.global_position.distance_to(planet.global_position) - planet.surface_radius(local_up)
		var speed: float = clampf(altitude, 12.0, 30000.0) * 4.0
		player.advance_flight(-local_up * speed, 1.0 / 60.0)
		var before_recenter: Vector3 = origin.true_position()
		origin._physics_process(1.0 / 60.0)
		maximum_true_position_error = maxf(maximum_true_position_error, origin.true_position().distance_to(before_recenter))
	var final_up: Vector3 = (player.global_position - planet.global_position).normalized()
	var final_altitude: float = player.global_position.distance_to(planet.global_position) - planet.surface_radius(final_up)
	if final_altitude < 1.19 or final_altitude > 2.0:
		failures.append("返航后的贴地保护高度错误。")
	if maximum_true_position_error > 0.05:
		failures.append("世界原点平移改变了宇宙坐标。")
	if origin.recenter_count < 10:
		failures.append("长距离飞行未触发足够的世界原点平移。")
	return {
		"passed": failures.is_empty(),
		"failures": failures,
		"maximum_altitude_m": maximum_altitude,
		"final_altitude_m": final_altitude,
		"maximum_recenter_position_error_m": maximum_true_position_error,
		"recenter_count": origin.recenter_count,
		"minimum_sun_altitude_degrees": rad_to_deg(asin(minimum_sun_height)),
		"maximum_sun_altitude_degrees": rad_to_deg(asin(maximum_sun_height)),
	}
