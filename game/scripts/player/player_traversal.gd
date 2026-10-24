class_name PlayerTraversal
extends RefCounted

const OPEN_DELAY: float = 0.35 # 离地后允许展开的最短时间，秒。
const GROUND_CLEARANCE: float = 4.0 # 展开前脚下射线长度，米。
const GLIDE_FALL: float = 2.5 # 稳定下落速度，米每秒。
const GLIDE_BLEND: float = 0.6 # 下落速度过渡时间，秒。
const TURN_RATE: float = PI * 0.5 # 水平转向上限，弧度每秒。
const MANTLE_TIME: float = 0.6 # 翻越顶端的时间，秒。
const MANTLE_ARC_HEIGHT: float = 0.65 # 普通翻越的脚底抬升，米；洞穴岩缘可由攀爬区增加净空。
const CLIMB_JUMP_PUSH_TIME: float = 0.2 # 跳离后短暂保留向外的速度，避免下一帧步行控制立即覆盖。
var climb_jump_left: float = 0.0
var climb_jump_velocity: Vector3 = Vector3.ZERO
var airborne_time: float = 0.0
var glide_time: float = 0.0
var stumble_left: float = 0.0
var last_grounded: Vector3 = Vector3.ZERO
var last_ground_seed: int = 0
var zone: Dictionary = {}
var mantle_time: float = -1.0
var _mantle_start: Vector3
var _initial_fall: float = 0.0
var _heading: Vector3 = Vector3.ZERO
var _reattach_delay: float = 0.0
var _climb_progress: float = 0.0
var _climb_horizontal: float = 0.0


func record_ground(player: StarSeaPlayer) -> void:
	var planet: Planet = player.current_planet()
	last_grounded = planet.to_local(player.global_position)
	last_ground_seed = planet.planet_seed
	airborne_time = 0.0


func can_open(grounded: bool, clear_below: bool, cave: int) -> bool:
	return not grounded and airborne_time >= OPEN_DELAY and clear_below and cave == -1


func start_glide(player: StarSeaPlayer, up: Vector3) -> void:
	glide_time = 0.0
	_initial_fall = player.velocity.dot(up)
	_heading = (-player.global_basis.z).slide(up).normalized()
	player.mode = StarSeaPlayer.Mode.GLIDE
	player.play_traversal_effect()


func glide_velocity(delta: float, up: Vector3, desired: Vector3, input_forward: float, lift: float) -> Vector3:
	glide_time += delta
	var tangent: Vector3 = desired.slide(up).normalized()
	_heading = _heading.slide(up).normalized()
	if _heading.length_squared() < 0.5:
		_heading = tangent
	var angle: float = _heading.signed_angle_to(tangent, up)
	_heading = _heading.rotated(up, clampf(angle, -TURN_RATE * delta, TURN_RATE * delta))
	var speed: float = 9.0 if input_forward > 0.1 else (3.0 if input_forward < -0.1 else 5.0)
	var vertical: float = lerpf(_initial_fall, -GLIDE_FALL, clampf(glide_time / GLIDE_BLEND, 0.0, 1.0)) + lift
	return _heading * speed + up * vertical


func update_walk(player: StarSeaPlayer, delta: float, jump: bool) -> bool:
	stumble_left = maxf(0.0, stumble_left - delta)
	climb_jump_left = maxf(0.0, climb_jump_left - delta)
	_reattach_delay = maxf(0.0, _reattach_delay - delta)
	if player.is_on_floor():
		# 攀爬使用 move_and_collide，离开时的站立标志可能仍来自旧接触。
		# 只在玩家完成 move_and_slide 后记录落点，不能在这里提前更新。
		airborne_time = 0.0
	else:
		airborne_time += delta
	if jump and not player.is_on_floor():
		var up: Vector3 = player.up_direction
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + up * 0.05, player.global_position - up * GROUND_CLEARANCE, 3, [player.get_rid()])
		var clear: bool = player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if can_open(false, clear, cave_at(player)):
			start_glide(player, up)
			return true
	return false


func step_glide(player: StarSeaPlayer, delta: float, input: Vector2, jump: bool) -> void:
	var planet: Planet = player.current_planet()
	var local: Vector3 = planet.to_local(player.global_position)
	var up: Vector3 = local.normalized()
	if jump or cave_at(player) != -1 or local.length() <= planet.radius + maxf(planet.noise.water_surface(up), 0.0) + 0.05:
		player.mode = StarSeaPlayer.Mode.WALK
		airborne_time = OPEN_DELAY
		return
	var lift: float = planet.noise.features.updraft_at(up, player.altitude) if planet.noise.features != null else 0.0
	player.velocity = glide_velocity(delta, up, -player.camera.global_basis.z, input.y, lift)
	var impact: float = -player.velocity.dot(up)
	player.move_and_slide()
	if player.is_on_floor() or player.get_slide_collision_count() > 0:
		player.mode = StarSeaPlayer.Mode.WALK
		if impact > 6.0:
			stumble_left = 0.4
		if player.is_on_floor():
			record_ground(player)
	player.set_wind_audio(true, lift > 0.1)


func try_climb(player: StarSeaPlayer, input: Vector2) -> bool:
	if _reattach_delay > 0.0 or input.length_squared() < 0.01:
		return false
	var planet: Planet = player.current_planet()
	var zones: ClimbZones = planet.get_node_or_null("ClimbZones") as ClimbZones
	if zones == null:
		return false
	var local: Vector3 = planet.to_local(player.global_position)
	var candidate: Dictionary = zones.zone_near(local, input.y >= 0)
	if candidate.is_empty():
		return false
	var contact: Dictionary = ClimbZones.contact(candidate, local)
	var normal: Vector3 = contact["normal"]
	var facing: float = (-player.global_basis.z).dot(-normal)
	var from_top: bool = local.distance_to(candidate["exit_top"]) < 0.9 and input.y < -0.1 and facing < -cos(deg_to_rad(50.0))
	if not from_top and (facing < cos(deg_to_rad(50.0)) or input.y < 0.1):
		return false
	zone = candidate
	_climb_progress = ClimbZones.length(zone) if from_top else float(contact["progress"])
	_climb_horizontal = (local - Vector3(contact["position"])).dot(Vector3(contact["tangent"]).cross(normal).normalized())
	zone["occupied"] = true
	player.mode = StarSeaPlayer.Mode.CLIMB
	player.velocity = Vector3.ZERO
	mantle_time = -1.0
	if from_top:
		player.global_position = planet.to_global(Vector3(zone["top"]) + normal * 0.45)
	player.global_basis = Basis.looking_at(-normal, local.normalized())
	if not StarSeaSettings.climb_hint_seen:
		player.notify("W/S 攀爬　空格 跳离")
		StarSeaSettings.climb_hint_seen = true
		if OS.get_cmdline_user_args().is_empty():
			(player.get_node("/root/GameSettings") as StarSeaSettings).save()
	return true


func step_climb(player: StarSeaPlayer, delta: float, input: Vector2, jump: bool) -> void:
	var planet: Planet = player.current_planet()
	var up: Vector3 = planet.to_local(player.global_position).normalized()
	var current: Dictionary = ClimbZones.point_at(zone, _climb_progress)
	var normal: Vector3 = current["normal"]
	if mantle_time >= 0.0:
		mantle_time += delta
		var weight: float = clampf(mantle_time / MANTLE_TIME, 0, 1)
		var target: Vector3 = _mantle_start.lerp(zone["exit_top"], smoothstep(0, 1, weight)) + up * sin(weight * PI) * float(zone.get("mantle_height", MANTLE_ARC_HEIGHT))
		player.move_and_collide(planet.to_global(target) - player.global_position)
		if weight >= 1.0:
			leave_climb(player)
			player.velocity = -up * 0.5
			player.move_and_slide()
		return
	if jump:
		leave_climb(player)
		player.velocity = normal * 2.0 + up * 3.0
		climb_jump_velocity = player.velocity.slide(up)
		climb_jump_left = CLIMB_JUMP_PUSH_TIME
		airborne_time = 0.0
		# 立即离开支撑面，清除攀爬前遗留的站立标志。
		player.move_and_slide()
		return
	var along: Vector3 = current["tangent"]
	var side: Vector3 = along.cross(normal).normalized()
	var local: Vector3 = planet.to_local(player.global_position)
	var height: float = _climb_progress
	var width: float = float(zone["width"])
	var rope: bool = zone["kind"] == "rope"
	var horizontal: float = 0.0 if rope else clampf(_climb_horizontal + input.x * delta, -width * 0.5, width * 0.5)
	height += input.y * (1.3 if rope else 1.6) * delta
	if height >= ClimbZones.length(zone):
		mantle_time = 0.0
		_mantle_start = local
		return
	if height <= 0.0 and input.y < 0.0:
		leave_climb(player)
		return
	_climb_progress = maxf(height, 0.0)
	_climb_horizontal = horizontal
	current = ClimbZones.point_at(zone, _climb_progress)
	normal = current["normal"]
	along = current["tangent"]
	side = along.cross(normal).normalized()
	var target: Vector3 = Vector3(current["position"]) + side * horizontal + normal * 0.45
	if zone["kind"] == "climb_route":
		# 分块碰撞会近似曲面，按真实岩壁接触校正胶囊与表面的间距。
		var correction: float = 0.0
		for lift: float in [0.35, 0.875, 1.4]:
			var center: Vector3 = planet.to_global(target + up * lift)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(center + normal * 2.0, center - normal * 2.0, 1, [player.get_rid()])
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				correction = maxf(correction, (Vector3(hit["position"]) - center).dot(normal) + 0.45)
		target += normal * correction
	var motion: Vector3 = planet.to_global(target) - player.global_position
	player.velocity = motion / maxf(delta, 0.0001)
	player.move_and_collide(motion)
	player.global_basis = Basis.looking_at(-normal, up)


func leave_climb(player: StarSeaPlayer) -> void:
	zone["occupied"] = false
	zone = {}
	mantle_time = -1.0
	_reattach_delay = 0.7
	player.mode = StarSeaPlayer.Mode.WALK


static func cave_at(player: StarSeaPlayer) -> int:
	var planet: Planet = player.current_planet()
	var features: TerrainFeatures = planet.noise.features
	return features.caves.cave_at(planet.to_local(player.global_position)) if features != null and features.caves != null else -1
