class_name StarSeaPlayer
extends CharacterBody3D

enum Mode { WALK, FLY, CLIMB, GLIDE }

var mode: Mode = Mode.WALK:
	set(value):
		mode = value
		if is_node_ready() and ship != null:
			if value == Mode.FLY:
				ship.attach_to(self)
				explorer.hide_glider()
			elif ship.state == StarSeaShip.State.CARRIED:
				if not park_ship_nearby():
					ship.park(ship.planet, ship.last_park)
			set_third_person(third_person)
var controls_enabled: bool = true
var simulated_forward: bool = false
var altitude: float = 0.0
var third_person: bool = false
var _waiting_for_ground: bool = true
var _planet: Planet
@onready var _head: Node3D = $Head
@onready var camera: Camera3D = $Head/CameraBoom/Camera
@onready var camera_boom: SpringArm3D = $Head/CameraBoom
var explorer: ExplorerAvatar
var ship: StarSeaShip
var transition_busy: bool = false
var _f_held: float = -1.0
var _f_consumed: bool = false
var _message: String = ""
var _message_time: float = 0.0
var _fade: ColorRect
var _boarding_hint_seen: bool = false
var traversal: PlayerTraversal = PlayerTraversal.new()
var _glide_effect: AudioStreamPlayer
var _glide_wind: AudioStreamPlayer


func _ready() -> void:
	camera_boom.add_excluded_object(get_rid())
	explorer = ExplorerAvatar.new()
	explorer.name = "Explorer"
	add_child(explorer)
	explorer.attach_edges(camera)
	_glide_effect = AudioStreamPlayer.new()
	_glide_wind = AudioStreamPlayer.new()
	add_child(_glide_effect)
	add_child(_glide_wind)
	_glide_effect.volume_db = -12.0
	_glide_wind.volume_db = -18.0
	set_third_person(false)
	_planet = get_tree().get_first_node_in_group("planets") as Planet
	var up: Vector3 = _planet.site["direction"]
	var forward: Vector3 = _planet.site["forward"]
	place_at(up * (_planet.surface_radius(up) + 0.05) + _planet.global_position, forward, up)
	ship = StarSeaShip.new()
	ship.name = "Ship"
	add_child(ship)
	ship._player = self
	park_ship_nearby()
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func place_at(world_position: Vector3, forward: Vector3, up: Vector3) -> void:
	global_position = world_position
	_planet = Planet.nearest(get_tree(), world_position)
	global_basis = Basis.looking_at(forward, up)
	_head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_waiting_for_ground = true
	up_direction = up
	var offset: Vector3 = world_position - _planet.global_position
	altitude = offset.length() - _planet.surface_radius(offset.normalized())
	if PlayerTraversal.cave_at(self) >= 0:
		altitude = 0.0
	traversal.airborne_time = 0.0
	reset_physics_interpolation()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or transition_busy:
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		# 捕获鼠标使用屏幕位移，水平转动沿角色自身上轴，避免缩放改变灵敏度和太空侧倾。
		var screen_delta: Vector2 = motion.screen_relative
		global_basis = (Basis(global_basis.y.normalized(), -screen_delta.x * StarSeaSettings.sensitivity) * global_basis).orthonormalized()
		set_head_pitch(_head.rotation.x - screen_delta.y * StarSeaSettings.sensitivity)
	elif event.is_action_pressed("toggle_fly") and not event.is_echo():
		_f_held = 0.0
		_f_consumed = false
	elif event.is_action_released("toggle_fly"):
		if _f_held >= 0.0 and _f_held < 0.4 and not _f_consumed:
			if mode == Mode.FLY:
				land()
			elif mode == Mode.WALK and is_on_floor() and ship.state == StarSeaShip.State.PARKED and global_position.distance_to(ship.global_position) <= StarSeaShip.BOARD_RANGE:
				board()
		_f_held = -1.0
	elif event.is_action_pressed("toggle_perspective"):
		set_third_person(not third_person)


func set_third_person(enabled: bool) -> void:
	third_person = enabled
	var riding: bool = mode == Mode.FLY
	var length: float = (12.0 if riding else 4.5) if enabled else 0.0
	camera_boom.spring_length = length
	camera_boom.position.y = 2.0 if enabled and riding else 0.0
	camera.position = Vector3(0, 0, length)
	explorer.visible = enabled and not riding
	explorer.set_first_person(not enabled)
	if ship != null and ship.state == StarSeaShip.State.CARRIED:
		ship.visual.visible = enabled


func _process(delta: float) -> void:
	_message_time = maxf(0.0, _message_time - delta)
	var near_ship: bool = ship != null and mode == Mode.WALK and is_on_floor() and ship.state == StarSeaShip.State.PARKED and global_position.distance_to(ship.global_position) <= StarSeaShip.BOARD_RANGE
	if near_ship and not _boarding_hint_seen and controls_enabled:
		notify("F 登船")
	_boarding_hint_seen = near_ship
	if not controls_enabled:
		_f_held = -1.0
	elif _f_held >= 0.0:
		_f_held += delta
		if not _f_consumed and _f_held >= StarSeaShip.HOLD_TIME and mode != Mode.FLY:
			_f_consumed = true
			if not near_ship:
				call_ship()
	if third_person and _planet != null and PlayerTraversal.cave_at(self) == -1:
		var offset: Vector3 = camera.global_position - _planet.global_position
		if offset.length() < _planet.surface_radius(offset.normalized()) + 0.3:
			# 快速降落时物理地形可能尚未就绪，仍按共享高度函数缩短相机距离。
			var start: Vector3 = _head.global_position
			var movement: Vector3 = camera.global_position - start
			var low: float = 0.0
			var high: float = 1.0
			for iteration: int in 10:
				var middle: float = (low + high) * 0.5
				var point: Vector3 = start + movement * middle - _planet.global_position
				if point.length() < _planet.surface_radius(point.normalized()) + 0.3:
					high = middle
				else:
					low = middle
			camera.global_position = start + movement * low
	# 相机受阻收回到头部附近时隐藏身体，避免头盔遮住整个视野。
	explorer.visible = third_person and mode != Mode.FLY and camera.global_position.distance_to(_head.global_position) > 0.75
	camera_boom.position.x = 0.65 if third_person and mode == Mode.CLIMB else 0.0
	if mode != Mode.FLY:
		explorer.animate(delta, global_basis.inverse() * velocity, false, is_on_floor(), int(mode), traversal.zone.get("kind", "") == "rope", traversal.stumble_left > 0, traversal.mantle_time >= 0)
	else:
		explorer.set_first_person(false)


func _physics_process(delta: float) -> void:
	_planet = Planet.nearest(get_tree(), global_position)
	var offset: Vector3 = global_position - _planet.global_position
	var distance: float = offset.length()
	var up: Vector3 = offset / maxf(distance, 0.001)
	altitude = distance - _planet.surface_radius(up)
	if PlayerTraversal.cave_at(self) >= 0:
		altitude = 0.0
	# 近地缩短裁剪范围，使近物可见；太空保留足够的近裁剪距离，避免超大远近比使视锥退化。
	camera.near = 0.15 if altitude < 5000.0 else 0.5
	camera.far = 200000.0 if altitude < 5000.0 else 3000000.0
	if transition_busy:
		return
	if mode != Mode.FLY:
		up_direction = up
		_align_to_up(up, delta)
	if not controls_enabled and not simulated_forward:
		return
	if mode == Mode.WALK and _waiting_for_ground:
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + up * 3.0, global_position - up * 5.0, collision_mask, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			velocity = Vector3.ZERO
			return
		_waiting_for_ground = false
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_back", "move_forward") if controls_enabled else Vector2.ZERO
	if simulated_forward:
		input = Vector2(0.0, 1.0)
	var forward: Vector3 = -camera.global_basis.z
	var right: Vector3 = camera.global_basis.x
	var jump: bool = controls_enabled and Input.is_action_just_pressed("jump_up")
	if mode == Mode.CLIMB:
		set_wind_audio(false, false)
		traversal.step_climb(self, delta, input, jump)
		return
	if mode == Mode.GLIDE:
		if not traversal.try_climb(self, input):
			traversal.step_glide(self, delta, input, jump)
		return
	if mode == Mode.WALK:
		set_wind_audio(false, false)
		if traversal.update_walk(self, delta, jump) or traversal.try_climb(self, input):
			return
		var was_on_floor: bool = is_on_floor()
		var jumping: bool = was_on_floor and jump
		forward = (forward - up * forward.dot(up)).normalized()
		right = (right - up * right.dot(up)).normalized()
		var direction: Vector3 = (forward * input.y + right * input.x).limit_length(1.0)
		var speed: float = 8.0 if Input.is_action_pressed("run") and controls_enabled else 4.0
		if traversal.stumble_left > 0:
			speed *= 0.5
		var vertical: Vector3 = up * velocity.dot(up)
		velocity = direction * speed + vertical
		if not is_on_floor():
			velocity -= up * _planet.gravity * delta
		elif jumping:
			velocity = direction * speed + up * 5.0
		var impact: float = -velocity.dot(up)
		move_and_slide()
		if is_on_floor():
			if not was_on_floor and impact > 6.0:
				traversal.stumble_left = 0.4
			traversal.record_ground(self)
		# 球面切线不断变化，沿斜坡移动产生的微小上升分量不应解除贴地。
		if not jumping and (was_on_floor or velocity.dot(up) <= 0.0):
			apply_floor_snap()
	else:
		var vertical_input: float = Input.get_axis("descend", "jump_up")
		var direction: Vector3 = (forward * input.y + right * input.x + global_basis.y * vertical_input).limit_length(1.0)
		var speed: float = clampf(altitude, 12.0, 30000.0)
		if Input.is_action_pressed("run"):
			speed *= 4.0
		advance_flight(direction * speed, delta)


func advance_flight(target_velocity: Vector3, delta: float) -> void:
	velocity = velocity.lerp(target_velocity, clampf(delta * 3.0, 0.0, 1.0))
	var destination: Vector3 = global_position + velocity * delta
	var contact: Dictionary = FlightSafety.sweep(get_tree(), global_position, destination)
	if contact.is_empty():
		global_position = destination
	else:
		global_position = contact["position"]
		var contact_up: Vector3 = contact["up"]
		velocity -= contact_up * minf(velocity.dot(contact_up), 0.0)
	_planet = Planet.nearest(get_tree(), global_position)
	var new_offset: Vector3 = global_position - _planet.global_position
	var new_up: Vector3 = new_offset.normalized()
	var surface: float = _planet.surface_radius(new_up)
	if new_offset.length() < surface + 1.2:
		global_position = _planet.global_position + new_up * (surface + 1.2)
		velocity -= new_up * minf(velocity.dot(new_up), 0.0)
	altitude = global_position.distance_to(_planet.global_position) - surface


func current_planet() -> Planet:
	return _planet


func head_pitch() -> float:
	return _head.rotation.x


func set_head_pitch(value: float) -> void:
	_head.rotation.x = clampf(value, deg_to_rad(-89.0), deg_to_rad(89.0))


func _start_walking() -> void:
	var up: Vector3 = (global_position - _planet.global_position).normalized()
	var view_direction: Vector3 = -camera.global_basis.z
	var forward: Vector3 = view_direction - up * view_direction.dot(up)
	if forward.length_squared() < 0.00001:
		forward = -global_basis.z - up * (-global_basis.z).dot(up)
	if forward.length_squared() < 0.00001:
		forward = SurfaceSites.tangent_forward(up)
	global_basis = Basis.looking_at(forward.normalized(), up)
	set_head_pitch(asin(clampf(view_direction.dot(up), -1.0, 1.0)))
	up_direction = up
	mode = Mode.WALK
	_waiting_for_ground = true


func _align_to_up(up: Vector3, delta: float) -> void:
	var forward: Vector3 = -global_basis.z
	forward = forward - up * forward.dot(up)
	if forward.length_squared() < 0.00001:
		forward = SurfaceSites.tangent_forward(up)
	var target: Basis = Basis.looking_at(forward.normalized(), up)
	global_basis = global_basis.orthonormalized().slerp(target, clampf(delta * 8.0, 0.0, 1.0))


func park_ship_nearby() -> bool:
	var up: Vector3 = _planet.to_local(global_position).normalized()
	var location: Transform3D = StarSeaShip.find_landing(_planet, up, SurfaceSites.tangent_forward(up), true)
	if not location.origin.is_finite():
		notify("附近没有能降落的地方")
		return false
	ship.park(_planet, location)
	return true


func land() -> void:
	if PlayerTraversal.cave_at(self) >= 0:
		notify("洞穴内无法降落")
		return
	if transition_busy or mode != Mode.FLY or altitude > 40.0 or velocity.length() >= 30.0:
		return
	var landing_planet: Planet = current_planet()
	var direction: Vector3 = landing_planet.to_local(global_position).normalized()
	var reason: String = StarSeaShip.can_land(landing_planet, direction)
	if not reason.is_empty():
		notify(reason)
		return
	var local_velocity: Vector3 = velocity
	# 先预测减速后的停留点，避免减速阶段前移、下降阶段又退回原位置。
	var braking_position: Vector3 = landing_planet.to_local(global_position) + local_velocity * 0.3
	direction = braking_position.normalized()
	reason = StarSeaShip.can_land(landing_planet, direction)
	if not reason.is_empty():
		notify(reason)
		return
	transition_busy = true
	_f_held = -1.0
	var destination: Transform3D = StarSeaShip.landing_transform(landing_planet, direction, -global_basis.z)
	var initial: Transform3D = Transform3D(global_basis, landing_planet.to_local(global_position))
	var elapsed: float = 0.0
	while elapsed < 2.6:
		await get_tree().physics_frame
		if get_tree().paused:
			continue
		elapsed += get_physics_process_delta_time()
		var progress: float = smoothstep(0.6, 2.6, elapsed)
		var t: float = clampf(elapsed / 0.6, 0.0, 1.0)
		# 积分平滑减速曲线，0.6 秒后保留实际位移，再从该点下降。
		var braking_distance: float = 0.6 * (t - t * t * t + 0.5 * t * t * t * t)
		var local_position: Vector3 = (initial.origin + local_velocity * braking_distance).lerp(destination.origin - direction * 0.4, progress)
		var local_up: Vector3 = local_position.normalized()
		local_position = local_up * maxf(local_position.length(), landing_planet.surface_radius(local_up) + 0.8)
		global_position = landing_planet.to_global(local_position)
		global_basis = initial.basis.orthonormalized().slerp(destination.basis, smoothstep(0.0, 2.6, elapsed))
		velocity = local_velocity * (1.0 - smoothstep(0.0, 0.6, elapsed))
	ship.park(landing_planet, destination)
	ship.play_effect("ship_land")
	var exit_position: Vector3 = destination.origin - destination.basis.x * 4.0
	var exit_up: Vector3 = exit_position.normalized()
	place_at(landing_planet.to_global(exit_up * (landing_planet.surface_radius(exit_up) + 0.05)), -destination.basis.z, exit_up)
	mode = Mode.WALK
	velocity = Vector3.ZERO
	transition_busy = false


func board() -> void:
	if transition_busy or mode != Mode.WALK or not is_on_floor() or ship.state != StarSeaShip.State.PARKED or global_position.distance_to(ship.global_position) > StarSeaShip.BOARD_RANGE:
		return
	transition_busy = true
	_f_held = -1.0
	ship.play_effect("ship_hatch")
	await _screen_fade(1.0)
	var boarding_position: Vector3 = ship.global_position + ship.global_basis.y * 3.0
	var boarding_basis: Basis = ship.global_basis
	place_at(boarding_position, -boarding_basis.z, boarding_basis.y)
	mode = Mode.FLY
	await _screen_fade(0.0)
	transition_busy = false


func call_ship() -> void:
	if PlayerTraversal.cave_at(self) >= 0:
		notify("洞穴内无法召唤飞船")
		return
	if transition_busy or mode == Mode.FLY or ship.state == StarSeaShip.State.CALLED:
		return
	if ship.planet != _planet:
		notify("飞船不在这颗星球上")
		return
	if altitude > 300.0 and mode in [Mode.WALK, Mode.GLIDE] and not is_on_floor():
		ship.catch_airborne(self)
		return
	if mode != Mode.WALK or not is_on_floor():
		return
	var location: Transform3D = StarSeaShip.find_landing(_planet, _planet.to_local(global_position).normalized(), -global_basis.z)
	if not location.origin.is_finite():
		notify("附近没有能降落的地方")
		return
	ship.call_to(_planet, location.origin.normalized())


func play_traversal_effect() -> void:
	if ResourceLoader.exists("res://audio/glide_open.wav"):
		_glide_effect.stream = load("res://audio/glide_open.wav") as AudioStream
		_glide_effect.play()


func set_wind_audio(enabled: bool, rising: bool) -> void:
	if not enabled:
		_glide_wind.stop()
		return
	if not _glide_wind.playing and ResourceLoader.exists("res://audio/high_wind.wav"):
		var stream: AudioStreamWAV = (load("res://audio/high_wind.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_glide_wind.stream = stream
		_glide_wind.play()
	_glide_wind.pitch_scale = 1.08 if rising else 1.0
	_glide_wind.volume_db = lerpf(-24.0, -15.0, clampf(velocity.length() / 9.0, 0, 1))


func notify(text: String) -> void:
	_message = text
	_message_time = 2.0


func interaction_hint() -> String:
	if _message_time > 0.0:
		return _message
	return ""


func _screen_fade(alpha: float) -> void:
	if _fade == null:
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		_fade = ColorRect.new()
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.color = Color(0, 0, 0, 0)
		layer.add_child(_fade)
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", alpha, 0.5)
	await tween.finished
