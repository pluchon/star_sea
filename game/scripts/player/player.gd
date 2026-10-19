class_name StarSeaPlayer
extends CharacterBody3D

enum Mode { WALK, FLY }

var mode: Mode = Mode.WALK
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


func _ready() -> void:
	camera_boom.add_excluded_object(get_rid())
	explorer = ExplorerAvatar.new()
	explorer.name = "Explorer"
	add_child(explorer)
	set_third_person(false)
	_planet = get_tree().get_first_node_in_group("planets") as Planet
	var up: Vector3 = _planet.site["direction"]
	var forward: Vector3 = _planet.site["forward"]
	place_at(up * (_planet.surface_radius(up) + 0.05) + _planet.global_position, forward, up)
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
		# 捕获鼠标使用屏幕位移，水平转动沿角色自身上轴，避免缩放改变灵敏度和太空侧倾。
		var screen_delta: Vector2 = motion.screen_relative
		global_basis = (Basis(global_basis.y.normalized(), -screen_delta.x * StarSeaSettings.sensitivity) * global_basis).orthonormalized()
		set_head_pitch(_head.rotation.x - screen_delta.y * StarSeaSettings.sensitivity)
	elif event.is_action_pressed("toggle_fly"):
		if mode == Mode.WALK:
			mode = Mode.FLY
		elif altitude <= 2.0 and _planet.noise.height((global_position - _planet.global_position).normalized()) > 0.0:
			_start_walking()
		velocity = Vector3.ZERO
	elif event.is_action_pressed("toggle_perspective"):
		set_third_person(not third_person)


func set_third_person(enabled: bool) -> void:
	third_person = enabled
	camera_boom.spring_length = 4.5 if enabled else 0.0
	camera.position = Vector3(0, 0, 4.5 if enabled else 0.0)
	explorer.visible = enabled


func _process(delta: float) -> void:
	if third_person and _planet != null:
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
	explorer.visible = third_person and camera.global_position.distance_to(_head.global_position) > 0.75
	if explorer.visible:
		explorer.animate(delta, global_basis.inverse() * velocity, mode == Mode.FLY, is_on_floor())


func _physics_process(delta: float) -> void:
	_planet = Planet.nearest(get_tree(), global_position)
	var offset: Vector3 = global_position - _planet.global_position
	var distance: float = offset.length()
	var up: Vector3 = offset / maxf(distance, 0.001)
	altitude = distance - _planet.surface_radius(up)
	# 近地缩短裁剪范围，使近物可见；太空保留足够的近裁剪距离，避免超大远近比使视锥退化。
	camera.near = 0.15 if altitude < 5000.0 else 0.5
	camera.far = 200000.0 if altitude < 5000.0 else 3000000.0
	if mode == Mode.WALK:
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
