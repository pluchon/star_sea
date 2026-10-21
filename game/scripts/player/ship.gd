class_name StarSeaShip
extends Node3D

enum State { CARRIED, PARKED, CALLED }

const BOARD_RANGE: float = 6.0 # 登船距离，米。
const HOLD_TIME: float = 1.2 # 召唤按住时间，秒。
const LAND_RADIUS: float = 6.0 # 降落检查范围，米。
const FOOT_HEIGHT: float = 1.2 # 飞船原点离地高度，米。
var state: State = State.PARKED
var planet: Planet
var visual: Node3D
var body: StaticBody3D
var engine: AudioStreamPlayer3D
var effect: AudioStreamPlayer3D
var target: Transform3D
var _player: StarSeaPlayer
var _call_start: Vector3
var _call_elapsed: float = 0.0
var _call_duration: float = 0.0
var _ramp: Node3D
var _exhausts: Array[Node3D] = []
var _dust: GPUParticles3D
var _air_catch: bool = false
var _air_start: Vector3
var last_park: Transform3D
var _pad_call: bool = false
var _pad_start: Vector3


func _ready() -> void:
	visual = ShipMeshes.build()
	visual.position.y = -FOOT_HEIGHT
	add_child(visual)
	_ramp = visual.find_child("Ramp", true, false) as Node3D
	for node: Node in visual.find_children("Exhaust*", "Node3D", true, false):
		_exhausts.append(node as Node3D)
	body = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position.y = -FOOT_HEIGHT
	add_child(body)
	var hull: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([Vector3(-1.4, 0.5, -3), Vector3(1.4, 0.5, -3), Vector3(0, 0.5, -4.2), Vector3(-1.4, 0.5, 3.3), Vector3(1.4, 0.5, 3.3), Vector3(-1.2, 2.5, -1), Vector3(1.2, 2.5, -1), Vector3(0, 1.8, 3.8)])
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = hull
	body.add_child(collision)
	var ramp_shape: BoxShape3D = BoxShape3D.new()
	ramp_shape.size = Vector3(1.5, 0.12, 1.0)
	var ramp_collision: CollisionShape3D = CollisionShape3D.new()
	ramp_collision.shape = ramp_shape
	ramp_collision.position = Vector3(-2.1, 0.43, -0.1)
	ramp_collision.rotation.z = 0.45
	body.add_child(ramp_collision)
	engine = AudioStreamPlayer3D.new()
	engine.name = "ShipEngine"
	var loop: AudioStreamWAV = (load("res://audio/engine.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	engine.stream = loop
	engine.max_distance = 450.0
	engine.unit_size = 16.0
	engine.volume_db = -12.0
	add_child(engine)
	effect = AudioStreamPlayer3D.new()
	effect.max_distance = 100.0
	effect.unit_size = 12.0
	effect.volume_db = -8.0
	add_child(effect)
	_dust = GPUParticles3D.new()
	_dust.one_shot = true
	_dust.emitting = false
	_dust.amount = 28
	_dust.lifetime = 1.3
	_dust.explosiveness = 0.95
	var dust_process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	dust_process.direction = Vector3.RIGHT
	dust_process.spread = 180.0
	dust_process.initial_velocity_min = 2.0
	dust_process.initial_velocity_max = 4.5
	dust_process.gravity = Vector3.ZERO
	dust_process.scale_min = 0.08
	dust_process.scale_max = 0.25
	dust_process.color = Color(0.6, 0.53, 0.4, 0.35)
	_dust.process_material = dust_process
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	dust_mesh.material = ShipMeshes.material("hull")
	_dust.draw_pass_1 = dust_mesh
	_dust.position.y = -FOOT_HEIGHT
	add_child(_dust)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	for collider: Node in body.get_children():
		(collider as CollisionShape3D).set_deferred("disabled", state != State.PARKED)
	if _ramp != null:
		_ramp.visible = state == State.PARKED
	for exhaust: Node3D in _exhausts:
		exhaust.visible = state != State.PARKED
	if state == State.PARKED:
		engine.stop()
	elif not engine.playing:
		engine.play()


func attach_to(player: StarSeaPlayer) -> void:
	_player = player
	state = State.CARRIED
	if get_parent() != player:
		reparent(player, false)
	# 船体最低点高于角色的贴地保护面，避免近地驾驶时支架穿入地形。
	transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0))
	_refresh()


func park(planet_value: Planet, local_transform: Transform3D) -> void:
	_pad_call = false
	_air_catch = false
	last_park = local_transform
	planet = planet_value
	state = State.PARKED
	if get_parent() != planet:
		reparent(planet, false)
	transform = local_transform
	visual.visible = true
	_refresh()


static func landing_transform(planet_value: Planet, direction: Vector3, forward: Vector3) -> Transform3D:
	var heading: Vector3 = forward - direction * forward.dot(direction)
	if heading.length_squared() < 0.001:
		heading = SurfaceSites.tangent_forward(direction)
	return Transform3D(Basis.looking_at(heading.normalized(), direction), direction * (planet_value.surface_radius(direction) + FOOT_HEIGHT))


static func can_land(planet_value: Planet, direction: Vector3) -> String:
	var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
	var minimum: float = INF
	var maximum: float = -INF
	for index: int in 9:
		var offset: Vector3 = Vector3.ZERO
		if index > 0:
			var angle: float = float((index - 1) % 4) * TAU / 4.0 + (PI / 4.0 if index > 4 else 0.0)
			offset = tangent.rotated(direction, angle) * (LAND_RADIUS if index > 4 else LAND_RADIUS * 0.5)
		var up: Vector3 = (direction * planet_value.radius + offset).normalized()
		var height: float = planet_value.noise.height(up)
		if height < 0.5 or planet_value.noise.water_surface(up) > -INF:
			return "这里不能降落：水面"
		if planet_value.noise.features != null and planet_value.noise.features.in_clearing(up):
			return "这里不能降落：地标占地"
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
	if maximum - minimum > 2.5:
		return "这里不能降落：地面不平"
	return ""


static func find_landing(planet_value: Planet, direction: Vector3, forward: Vector3, initial: bool = false) -> Transform3D:
	var distances: PackedFloat32Array = PackedFloat32Array([16.0, 10.0, 24.0, 32.0, 40.0] if initial else [15.0, 20.0, 25.0, 32.0, 40.0])
	for distance: float in distances:
		for index: int in 24:
			var heading: Vector3 = forward.rotated(direction, deg_to_rad(120.0) + index * TAU / 24.0)
			var up: Vector3 = SurfaceSites.offset_direction(direction, heading, distance, planet_value.radius)
			if can_land(planet_value, up).is_empty():
				return landing_transform(planet_value, up, forward)
	return Transform3D(Basis.IDENTITY, Vector3.INF)


func call_to(planet_value: Planet, target_direction: Vector3) -> void:
	_pad_call = false
	planet = planet_value
	target = landing_transform(planet, target_direction, -basis.z)
	_call_start = position.normalized()
	var distance: float = _call_start.angle_to(target_direction) * planet.radius
	_call_duration = distance / clampf(distance / 20.0, 40.0, 300.0)
	_call_elapsed = 0.0
	state = State.CALLED
	_refresh()


func call_to_pad(planet_value: Planet, destination: Transform3D) -> void:
	planet = planet_value
	if get_parent() != planet:
		reparent(planet, true)
	_pad_call = true
	_pad_start = position
	target = destination
	_call_elapsed = 0
	_call_duration = clampf(position.distance_to(target.origin) / 300, 3, 22)
	state = State.CALLED
	_refresh()


func _process(delta: float) -> void:
	if _pad_call:
		_call_elapsed += delta
		var weight: float = smoothstep(0, _call_duration, _call_elapsed)
		var up: Vector3 = target.basis.y
		# 先升至塔顶外侧再靠近停泊台，避免召回路线贯穿塔身。
		var summit: Vector3 = up * maxf(_pad_start.length(), target.origin.length() + 120) - target.basis.z * 100
		position = _pad_start.lerp(summit, smoothstep(0, 0.55, weight)) if weight < 0.55 else summit.lerp(target.origin, smoothstep(0.55, 1, weight))
		basis = target.basis
		if _call_elapsed >= _call_duration:
			park(planet, target)
		return
	if _air_catch:
		_advance_air_catch(delta)
		return
	if state == State.CARRIED and _player != null:
		engine.pitch_scale = lerpf(0.8, 1.65, smoothstep(0.0, 800.0, _player.velocity.length()))
	elif state == State.CALLED:
		_call_elapsed += delta
		var destination: Vector3 = target.origin.normalized()
		if _player != null and _player.current_planet() == planet and _player.global_position.distance_to(planet.to_global(target.origin)) > 60.0:
			var replacement: Transform3D = find_landing(planet, planet.to_local(_player.global_position).normalized(), -_player.global_basis.z)
			if replacement.origin.is_finite():
				call_to(planet, replacement.origin.normalized())
				return
		var progress: float = clampf((_call_elapsed - 2.0) / maxf(_call_duration, 0.1), 0.0, 1.0)
		var direction: Vector3 = _call_start.slerp(destination, progress).normalized()
		var clearance: float = lerpf(FOOT_HEIGHT, 120.0, smoothstep(0.0, 2.0, _call_elapsed))
		clearance = lerpf(clearance, FOOT_HEIGHT, smoothstep(_call_duration + 2.0, _call_duration + 4.0, _call_elapsed))
		position = direction * (planet.surface_radius(direction) + clearance)
		basis = landing_transform(planet, direction, -target.basis.z).basis
		if _call_elapsed >= _call_duration + 4.0:
			park(planet, target)
			play_effect("ship_land")


func play_effect(filename: String) -> void:
	effect.stream = load("res://audio/" + filename + ".wav") as AudioStream
	effect.play()
	if filename == "ship_land":
		_dust.restart()
		_dust.emitting = true


func catch_airborne(player: StarSeaPlayer) -> void:
	_player = player
	planet = player.current_planet()
	if get_parent() != planet:
		reparent(planet, true)
	_air_start = position
	_call_elapsed = 0.0
	_air_catch = true
	state = State.CALLED
	visual.visible = true
	_refresh()


func _advance_air_catch(delta: float) -> void:
	_call_elapsed += delta
	if _player.mode == StarSeaPlayer.Mode.FLY:
		_air_catch = false
		return
	var target_position: Vector3 = planet.to_local(_player.global_position)
	var progress: float = smoothstep(0.0, 8.0, _call_elapsed)
	var destination: Vector3 = _air_start.lerp(target_position - target_position.normalized() * 1.2, progress)
	var direction: Vector3 = destination.normalized()
	destination = direction * maxf(destination.length(), planet.surface_radius(direction) + FOOT_HEIGHT)
	position = destination
	basis = Basis.looking_at((-_player.global_basis.z).slide(direction).normalized(), direction)
	if _call_elapsed >= 8.0:
		_air_catch = false
		_player.mode = StarSeaPlayer.Mode.FLY
		_player.set_wind_audio(false, false)


# 飞船在玩家与星球之间重新挂接时会离开场景树，不能在这里清空可复用音频。
# 节点最终释放时由音频子节点回收播放实例与资源。
