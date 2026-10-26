class_name SkyLadder
extends Node3D

const NEAR_RANGE: float = 2500.0
const LIFT_TIME: float = 75.0
var balcony_height: float = 240.0
const LIFT_CENTER: Vector3 = Vector3(0, 0, -26)
var lift: AnimatableBody3D
var lift_elapsed: float = -1.0
var lift_top: bool = false
var lift_target_top: bool = false
var dwell: float = 0.0
var far_triangles: int = 0
var bridge_direction: Vector3 = Vector3.BACK
var ending_awake: bool = false
var echo_rise: float = -1.0
var _planet: Planet
var _near: Node3D
var _platform: Node3D
var _far: MeshInstance3D
var _far_material: ShaderMaterial
var _near_material: ShaderMaterial
var _tether_material: ShaderMaterial
var _broken: Node3D
var _hum: AudioStreamPlayer3D
var _start: AudioStreamPlayer3D
var _models: Dictionary = {}
var _time: float = 0.0
var _flare: MeshInstance3D
var _stone_materials: Dictionary = {}
var _gate: Node3D
var _ring_flares: Array[MeshInstance3D] = []
var _lift_saved: Dictionary = {}
var _platform_wind: AudioStreamPlayer3D


func _ready() -> void:
	_planet = get_parent() as Planet
	transform = LandingPads.frame(_planet)
	balcony_height = LandingPads.balcony_height(_planet)
	for piece: String in ["lift", "balcony", "break_platform", "gangway", "gate", "broken_top", "watcher_lamp", "base_detail"]:
		_models[piece] = load("res://models/sky_ladder/" + piece + ".glb") as PackedScene
	_far_material = ShaderMaterial.new()
	_far_material.shader = load("res://shaders/sky_ladder.gdshader") as Shader
	_far_material.set_shader_parameter("stone_paint", load("res://textures/painted/stone.svg"))
	_near_material = _far_material.duplicate() as ShaderMaterial
	_far = MeshInstance3D.new()
	_far.mesh = SkyLadderMeshes.body(false, balcony_height)
	_far.material_override = _far_material
	add_child(_far)
	_broken = model("broken_top", self, Vector3(0, 6200, 0), false)
	_tether_material = ShaderMaterial.new()
	_tether_material.shader = load("res://shaders/tether.gdshader") as Shader
	for node: Node in _broken.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(surface).resource_name.to_lower() == "patina":
				mesh.set_surface_override_material(surface, _tether_material)
		far_triangles += mesh.mesh.get_faces().size() / 3
	far_triangles += _far.mesh.get_faces().size() / 3
	var giant: Node3D = _planet.get_parent().get_node("GasGiant") as Node3D
	bridge_direction = (global_basis.inverse() * global_position.direction_to(giant.global_position)).slide(Vector3.UP).normalized()
	if bridge_direction.is_zero_approx():
		bridge_direction = Vector3.BACK
	_flare = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	_flare.mesh = quad
	_flare.position = Vector3(0, 6200, 0)
	var glow: ShaderMaterial = ShaderMaterial.new()
	glow.shader = load("res://shaders/beacon_flare.gdshader") as Shader
	_flare.material_override = glow
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flare)
	# 六米环带在十五公里处不足一个像素，远处另用受深度测试的柔边光点保留夜间轮廓。
	for height: int in range(600, 6001, 600):
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = quad
		ring.set_meta("height", float(height))
		ring.position = Vector3.UP * height
		var material_value: ShaderMaterial = glow.duplicate() as ShaderMaterial
		ring.material_override = material_value
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_ring_flares.append(ring)
		far_triangles += 2


func model(piece: String, parent: Node3D, at: Vector3, collision: bool = true) -> Node3D:
	var instance: Node3D = (_models[piece] as PackedScene).instantiate() as Node3D
	instance.position = at
	if piece in ["break_platform", "gangway", "broken_top"]:
		instance.scale = Vector3(LandingPads.HORIZONTAL_SCALE, 1, LandingPads.HORIZONTAL_SCALE)
	elif piece == "lift":
		instance.scale = Vector3(4.0 / 3, 1, 4.0 / 3)
	parent.add_child(instance)
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			var kind: int = RuinMeshes.KINDS.find(original.resource_name.to_lower())
			if original.resource_name.contains("铜"):
				kind = 1
			elif original.resource_name.contains("琥珀"):
				kind = 2
			var frost: bool = piece in ["break_platform", "gangway", "watcher_lamp", "broken_top"]
			var key: String = "%d/%s" % [maxi(kind, 0), frost]
			if not _stone_materials.has(key):
				var material_value: ShaderMaterial = ShaderMaterial.new()
				material_value.shader = load("res://shaders/ladder_stone.gdshader") as Shader
				material_value.set_shader_parameter("kind", maxi(kind, 0))
				material_value.set_shader_parameter("frost", 0.3 if frost else 0.0)
				material_value.set_shader_parameter("stone_paint", load("res://textures/painted/stone.svg"))
				_stone_materials[key] = material_value
			mesh.set_surface_override_material(surface, _stone_materials[key])
		if collision:
			var body: StaticBody3D = StaticBody3D.new()
			body.collision_layer = 2
			var shape: CollisionShape3D = CollisionShape3D.new()
			shape.shape = mesh.mesh.create_trimesh_shape()
			body.add_child(shape)
			mesh.add_child(body)
	return instance


func _build_near() -> void:
	_near = Node3D.new()
	add_child(_near)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = SkyLadderMeshes.body(true, balcony_height)
	body.material_override = _near_material
	_near.add_child(body)
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 2
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = body.mesh.create_trimesh_shape()
	wall.add_child(collision)
	_near.add_child(wall)
	_gate = model("gate", _near, Vector3(0, 0, -60))
	model("balcony", _near, Vector3(0, balcony_height, 0))
	model("base_detail", _near, Vector3.ZERO, false)
	# 扶壁使用与 Blender 相同的六顶点楔形，避免把细石肋加入碰撞网格。
	var supports: StaticBody3D = StaticBody3D.new()
	supports.collision_layer = 2
	_near.add_child(supports)
	for side: int in 4:
		var angle: float = (side + 0.5) * TAU / 4
		var points: PackedVector3Array = PackedVector3Array()
		for pair: Vector2 in [Vector2(58, 0), Vector2(101, -6), Vector2(58, 60)]:
			for width: float in [-4, 4]:
				points.append(Vector3(sin(angle) * pair.x + cos(angle) * width, pair.y, -cos(angle) * pair.x + sin(angle) * width))
		var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		shape.points = points
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		supports.add_child(collider)
	var pieces: Array[Dictionary] = []
	for sign_value: float in [-1, 1]:
		pieces.append({"piece": "lamp_post", "transform": global_transform * Transform3D(Basis.IDENTITY, Vector3(sign_value * 16, -6, -91)), "awake": 0.4})
	for sign_value: float in [-1, 1]:
		pieces.append({"piece": "plinth", "transform": global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(1, 2, 1)), Vector3(sign_value * 28, 0, -58))})
		pieces.append({"piece": "statue", "transform": global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3), Vector3(sign_value * 28, 2.4, -58))})
	for i: int in 20:
		var angle: float = TAU * i / 20
		if absf(wrapf(angle - PI, -PI, PI)) < 0.5:
			continue
		pieces.append({"piece": "column", "transform": global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(2, 3, 2)), Vector3(sin(angle) * 78, -6, cos(angle) * 78))})
	for ring: int in 3:
		var radius: float = [180.0, 120.0, 70.0][ring]
		for i: int in ceili(TAU * radius / 6):
			var angle: float = TAU * i / ceili(TAU * radius / 6)
			if minf(absf(sin(angle)), absf(cos(angle))) * radius < 12:
				continue
			var position_value: Vector3 = Vector3(sin(angle) * radius, -18 + (ring + 1) * 6, cos(angle) * radius)
			var basis_value: Basis = Basis(Vector3.UP, angle).scaled(Vector3(3.1, 1.67, 1))
			pieces.append({"piece": "wall_broken" if i % 9 == 2 else "wall", "transform": global_transform * Transform3D(basis_value, position_value - Vector3.UP * 5.8), "moss": 0.25, "sand": 0.2})
		for side: int in 4:
			var basis_value: Basis = Basis(Vector3.UP, side * PI / 2)
			for flight: int in 4:
				for lane: int in 5:
					var position_value: Vector3 = basis_value * Vector3((lane - 2) * 4, 0, radius + 12 - (flight + 0.5) * 3)
					position_value.y = -18 + ring * 6 + flight * 1.5 - 0.3
					pieces.append({"piece": "steps", "transform": global_transform * Transform3D(basis_value.scaled(Vector3(1, 1, 3.0 / 3.6)), position_value), "moss": 0.1})
	var builder: RuinBuilder = RuinBuilder.new()
	# RuinBuilder 的放置坐标以星球中心为原点。
	_planet.add_child(builder)
	for record: Dictionary in pieces:
		record["transform"] = _planet.global_transform.affine_inverse() * Transform3D(record["transform"])
	builder.build(pieces)
	for node: Node in builder.get_children():
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh.mesh.get_aabb().size.y < 3.7:
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_near.set_meta("builder", builder)
	lift = AnimatableBody3D.new()
	lift.name = "Lift"
	lift.collision_layer = 2
	lift.collision_mask = 0
	# 已在物理帧直接更新位置，避免额外同步把原点平移前的全局变换写回。
	lift.sync_to_physics = false
	lift.position = LIFT_CENTER
	_near.add_child(lift)
	model("lift", lift, Vector3.ZERO, false)
	var floor_shape: CylinderShape3D = CylinderShape3D.new()
	floor_shape.radius = 8
	floor_shape.height = 0.7
	var lift_collision: CollisionShape3D = CollisionShape3D.new()
	lift_collision.shape = floor_shape
	lift_collision.position.y = -0.35
	lift.add_child(lift_collision)
	_hum = AudioStreamPlayer3D.new()
	_hum.bus = "World"
	var hum_stream: AudioStreamWAV = (load("res://audio/lift_hum.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	hum_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum_stream.loop_end = roundi(hum_stream.get_length() * hum_stream.mix_rate)
	_hum.stream = hum_stream
	_hum.max_distance = 100
	_hum.unit_size = 12
	_hum.volume_db = -14
	lift.add_child(_hum)
	_start = AudioStreamPlayer3D.new()
	_start.bus = "World"
	_start.stream = load("res://audio/lift_start.wav") as AudioStream
	_start.max_distance = 120
	_start.unit_size = 16
	lift.add_child(_start)
	restore_lift(_lift_saved)


func _build_platform() -> void:
	_platform = Node3D.new()
	_platform.position.y = LandingPads.HEIGHT
	add_child(_platform)
	var ring: Node3D = model("break_platform", _platform, Vector3.ZERO)
	# Blender 的 Y 向前在 glTF 中转为负 Z；此模型的停泊台位于另一端。
	ring.rotation.y = PI
	var bridge: Node3D = model("gangway", _platform, bridge_direction * LandingPads.BRIDGE_START)
	bridge.basis = Basis.looking_at(bridge_direction, Vector3.UP).scaled(Vector3(LandingPads.HORIZONTAL_SCALE, 1, LandingPads.HORIZONTAL_SCALE))
	var door: MeshInstance3D = MeshInstance3D.new()
	door.mesh = RuinKit.mesh("door_sealed") if RuinMeshes.recipes().has("door_sealed") else RuinKit.mesh("wall")
	door.position = Vector3(0, 0, -26)
	_platform.add_child(door)
	var wind: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	wind.bus = "World"
	_platform_wind = wind
	var stream: AudioStreamWAV = (load("res://audio/high_wind.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	wind.stream = stream
	wind.position = Vector3(0, 2, -LandingPads.DOCK_OFFSET)
	wind.max_distance = 400
	wind.unit_size = 100
	_platform.add_child(wind)
	wind.play()


func _process(delta: float) -> void:
	var player: StarSeaPlayer = get_tree().current_scene.get_node("Player") as StarSeaPlayer
	var at: Vector3 = to_local(player.camera.global_position)
	var director: SkyDirector = get_tree().current_scene.get_node("SkyDirector") as SkyDirector
	if is_instance_valid(_platform_wind):
		_platform_wind.volume_db = -8 * director.echo_blend
	if not director.time_paused:
		_time += delta
	_tether_material.set_shader_parameter("tether_time", _time)
	for material_value: ShaderMaterial in _stone_materials.values():
		material_value.set_shader_parameter("cloth_time", _time)
	var night: float = 1 - smoothstep(-0.1, 0.2, director.sun_direction.dot(global_basis.y))
	for material_value: ShaderMaterial in [_far_material, _near_material]:
		material_value.set_shader_parameter("awake", lerpf(0.3, 0.6, night))
		material_value.set_shader_parameter("echo_rise", echo_rise)
	_far_material.set_shader_parameter("hide_base", _near != null)
	var pixel_radius: float = 12.0 * tan(deg_to_rad(player.camera.fov) * 0.5) / get_viewport().get_visible_rect().size.y
	_far_material.set_shader_parameter("pixel_radius", pixel_radius)
	_planet.atmosphere_material.set_shader_parameter("tower_pixel_radius", pixel_radius)
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if at.length() < 3000 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node: Node in _broken.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = _far.cast_shadow
	var gap: float = at.length()
	if gap < NEAR_RANGE and _near == null:
		_build_near()
	elif gap > NEAR_RANGE + 400 and _near != null and lift_elapsed < 0:
		_lift_saved = lift_state()
		(_near.get_meta("builder") as Node).queue_free()
		_near.queue_free()
		_near = null
		lift = null
	if at.distance_to(Vector3(0, LandingPads.HEIGHT, 0)) < NEAR_RANGE and _platform == null:
		_build_platform()
	elif at.distance_to(Vector3(0, LandingPads.HEIGHT, 0)) > NEAR_RANGE + 400 and _platform != null:
		_platform.queue_free()
		_platform = null
	var flare_position: Vector3 = _flare.global_position
	var camera: Camera3D = player.camera
	_flare.global_basis = camera.global_basis
	var size_value: float = BeaconTowers.flare_size(flare_position.distance_to(camera.global_position), camera.fov, get_viewport().get_visible_rect().size.y)
	_flare.scale = Vector3.ONE * size_value
	(_flare.material_override as ShaderMaterial).set_shader_parameter("strength", (0.55 + 0.25 * sin(_time * TAU / 6)) * lerpf(0.6, 1.0, night) if ending_awake else 0.08 * night)
	if _platform != null:
		for node: Node in _platform.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).set_instance_shader_parameter("awake", 1.0 if ending_awake else 0.1)
	for ring: MeshInstance3D in _ring_flares:
		var height: float = ring.get_meta("height")
		var point: Vector3 = Vector3.UP * height
		var radial: Vector3 = (at - point).slide(Vector3.UP).normalized()
		ring.position = point + radial * (SkyLadderMeshes.radius_at(height) + 0.5)
		ring.global_basis = camera.global_basis
		var distance: float = ring.global_position.distance_to(camera.global_position)
		ring.scale = Vector3.ONE * BeaconTowers.flare_size(distance, camera.fov, get_viewport().get_visible_rect().size.y)
		var response: float = 1.0 if echo_rise >= height / 6200.0 and echo_rise >= 0 else 0.0
		ring.visible = (night > 0.01 or response > 0) and distance > 2000
		(ring.material_override as ShaderMaterial).set_shader_parameter("strength", maxf(0.5 * night, response) * smoothstep(2000, 3000, distance))


func _physics_process(delta: float) -> void:
	if lift == null:
		return
	var awake: float = 1.0 if lift_elapsed >= 0 else maxf(0.3, clampf(dwell / 2, 0, 1))
	for group: Node3D in [lift, _gate]:
		for node: Node in group.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).set_instance_shader_parameter("awake", awake)
	if lift_elapsed >= 0:
		lift_elapsed = minf(lift_elapsed + delta, LIFT_TIME)
		var fraction: float = lift_fraction(lift_elapsed)
		lift.position.y = balcony_height * (fraction if lift_target_top else 1 - fraction)
		if lift_elapsed >= LIFT_TIME:
			lift_top = lift_target_top
			lift_elapsed = -1
			dwell = 0
			_hum.stop()
		return
	var player: StarSeaPlayer = get_tree().current_scene.get_node("Player") as StarSeaPlayer
	var at: Vector3 = to_local(player.global_position)
	var radial: float = Vector2(at.x - LIFT_CENTER.x, at.z - LIFT_CENTER.z).length()
	var lower: bool = absf(at.y) < 2
	var upper: bool = absf(at.y - balcony_height) < 2
	var on_lift: bool = radial < 7.5 and player.is_on_floor() and (lower or upper)
	var calling: bool = radial < 13 and player.is_on_floor() and ((upper and not lift_top) or (lower and lift_top))
	dwell = dwell + delta if player.controls_enabled and player.mode == StarSeaPlayer.Mode.WALK and (on_lift or calling) else 0
	if dwell >= 2:
		lift_target_top = not lift_top
		lift_elapsed = 0
		dwell = 0
		_start.play()
		_hum.play()


static func lift_fraction(time: float) -> float:
	# 三秒加减速的速度积分，按完整行程归一化，端点速度为零。
	var cruise: float = LIFT_TIME - 3
	if time < 3:
		return time * time / (6 * cruise)
	if time > LIFT_TIME - 3:
		return 1 - pow(LIFT_TIME - time, 2) / (6 * cruise)
	return (time - 1.5) / cruise


func lift_state() -> Dictionary:
	return {"top": lift_top, "target_top": lift_target_top, "elapsed": lift_elapsed} if lift != null else _lift_saved.duplicate()


func restore_lift(value: Dictionary) -> void:
	_lift_saved = value.duplicate()
	lift_top = value.get("top", false)
	lift_target_top = value.get("target_top", false)
	lift_elapsed = value.get("elapsed", -1.0)
	dwell = 0
	if lift == null:
		return
	var fraction: float = lift_fraction(lift_elapsed) if lift_elapsed >= 0 else float(lift_top)
	lift.position.y = balcony_height * (fraction if lift_elapsed < 0 or lift_target_top else 1 - fraction)
	if lift_elapsed >= 0:
		_hum.play()
	else:
		_hum.stop()


static func valid_lift(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state: Dictionary = value
	if state.is_empty():
		return true
	if state.size() != 3 or not state.get("top") is bool or not state.get("target_top") is bool:
		return false
	var elapsed: Variant = state.get("elapsed")
	if (not elapsed is float and not elapsed is int) or not is_finite(float(elapsed)):
		return false
	return (float(elapsed) == -1 or (float(elapsed) >= 0 and float(elapsed) <= LIFT_TIME and state["top"] != state["target_top"]))
