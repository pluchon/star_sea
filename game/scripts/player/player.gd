class_name StarSeaPlayer
extends CharacterBody3D

enum Mode { WALK, FLY }

var mode: Mode = Mode.WALK
var controls_enabled: bool = true
var simulated_forward: bool = false
var altitude: float = 0.0
var _waiting_for_ground: bool = true
var _planet: Planet
@onready var _head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera


func _ready() -> void:
	_planet = get_tree().get_first_node_in_group("planets") as Planet
	var up: Vector3 = _planet.site["direction"]
	var forward: Vector3 = _planet.site["forward"]
	place_at(up * (_planet.surface_radius(up) + 0.05) + _planet.global_position, forward, up)
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func place_at(world_position: Vector3, forward: Vector3, up: Vector3) -> void:
	global_position = world_position
	global_basis = Basis.looking_at(forward, up)
	_head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_waiting_for_ground = true
	up_direction = up
	altitude = world_position.distance_to(_planet.global_position) - _planet.surface_radius(up)
	reset_physics_interpolation()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var up: Vector3 = (_planet.global_position.direction_to(global_position)).normalized()
		global_basis = Basis(up, -motion.relative.x * StarSeaSettings.sensitivity) * global_basis
		_head.rotation.x = clampf(_head.rotation.x - motion.relative.y * StarSeaSettings.sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("toggle_fly"):
		if mode == Mode.WALK:
			mode = Mode.FLY
		elif altitude <= 2.0 and _planet.noise.height((global_position - _planet.global_position).normalized()) > 0.0:
			mode = Mode.WALK
			_waiting_for_ground = true
		velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_planet = Planet.nearest(get_tree(), global_position)
	var offset: Vector3 = global_position - _planet.global_position
	var distance: float = offset.length()
	var up: Vector3 = offset / maxf(distance, 0.001)
	altitude = distance - _planet.surface_radius(up)
	if distance < _planet.radius * 3.0:
		up_direction = up
		_align_to_up(up, delta)
	if not controls_enabled and not simulated_forward:
		return
	if mode == Mode.WALK and _waiting_for_ground:
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + up * 3.0, global_position - up * 5.0, 1, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			velocity = Vector3.ZERO
			return
		_waiting_for_ground = false
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_back", "move_forward") if controls_enabled else Vector2.ZERO
	if simulated_forward:
		input = Vector2(0.0, 1.0)
	var forward: Vector3 = -camera.global_basis.z
	var right: Vector3 = camera.global_basis.x
	if mode == Mode.WALK:
		var was_on_floor: bool = is_on_floor()
		var jumping: bool = was_on_floor and controls_enabled and Input.is_action_just_pressed("jump_up")
		forward = (forward - up * forward.dot(up)).normalized()
		right = (right - up * right.dot(up)).normalized()
		var direction: Vector3 = (forward * input.y + right * input.x).limit_length(1.0)
		var speed: float = 8.0 if Input.is_action_pressed("run") and controls_enabled else 4.0
		var vertical: Vector3 = up * velocity.dot(up)
		velocity = direction * speed + vertical
		if not is_on_floor():
			velocity -= up * _planet.gravity * delta
		elif jumping:
			velocity = direction * speed + up * 5.0
		move_and_slide()
		# 球面切线不断变化，沿斜坡移动产生的微小上升分量不应解除贴地。
		if not jumping and (was_on_floor or velocity.dot(up) <= 0.0):
			apply_floor_snap()
	else:
		var vertical_input: float = Input.get_axis("descend", "jump_up")
		var direction: Vector3 = (forward * input.y + right * input.x + up * vertical_input).limit_length(1.0)
		var speed: float = clampf(altitude, 12.0, 30000.0)
		if Input.is_action_pressed("run"):
			speed *= 4.0
		advance_flight(direction * speed, delta)


func advance_flight(target_velocity: Vector3, delta: float) -> void:
	velocity = velocity.lerp(target_velocity, clampf(delta * 3.0, 0.0, 1.0))
	global_position += velocity * delta
	_planet = Planet.nearest(get_tree(), global_position)
	var new_offset: Vector3 = global_position - _planet.global_position
	var new_up: Vector3 = new_offset.normalized()
	var surface: float = _planet.surface_radius(new_up)
	if new_offset.length() < surface + 1.2:
		global_position = _planet.global_position + new_up * (surface + 1.2)
		velocity -= new_up * minf(velocity.dot(new_up), 0.0)


func current_planet() -> Planet:
	return _planet


func head_pitch() -> float:
	return _head.rotation.x


func set_head_pitch(value: float) -> void:
	_head.rotation.x = clampf(value, deg_to_rad(-89.0), deg_to_rad(89.0))


func _align_to_up(up: Vector3, delta: float) -> void:
	var forward: Vector3 = -global_basis.z
	forward = forward - up * forward.dot(up)
	if forward.length_squared() < 0.00001:
		forward = SurfaceSites.tangent_forward(up)
	var target: Basis = Basis.looking_at(forward.normalized(), up)
	global_basis = global_basis.orthonormalized().slerp(target, clampf(delta * 8.0, 0.0, 1.0))
