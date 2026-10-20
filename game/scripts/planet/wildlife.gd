class_name Wildlife
extends Node3D

# 晨上的少量动物：白天天上盘旋的鸟群，草地上的一小群鹿，夜里水边和林间的萤火。
# 只在玩家附近生成，离开太远就挪到玩家前方重新出现；不做种群或食物链模拟。
# 坐标以星球中心为原点，随星球一起参与浮动原点平移。

const FLOCKS: int = 2
const BIRDS_PER_FLOCK: int = 7
const DEER: int = 5
const FIREFLIES: int = 70
# 靠近到这个距离以内鹿会受惊跑开；玩家奔跑或飞行时距离加倍。
const SCARE_DISTANCE: float = 26.0

var _planet: Planet
var _noise: TerrainNoise
var _director: SkyDirector
var _material: ShaderMaterial
var _bird_material: ShaderMaterial
var _flocks: Array[Dictionary] = []
var _birds: MultiMeshInstance3D
var _deer: Array[Dictionary] = []
var _herd_center: Vector3 = Vector3.ZERO
var _fireflies: MultiMeshInstance3D
var _firefly_material: ShaderMaterial
var _firefly_center: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0


func _ready() -> void:
	_planet = get_parent() as Planet
	_noise = _planet.noise
	_rng.seed = _planet.planet_seed + 77
	var shader: Shader = load("res://shaders/wildlife.gdshader") as Shader
	_material = ShaderMaterial.new()
	_material.shader = shader
	_bird_material = ShaderMaterial.new()
	_bird_material.shader = shader
	_bird_material.set_shader_parameter("flap_speed", 9.0)
	_build_birds()
	_build_deer()
	_build_fireflies()


func _process(delta: float) -> void:
	if _director == null:
		_director = get_tree().get_first_node_in_group("sky_director") as SkyDirector
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _director == null:
		return
	_time += delta
	var eye: Vector3 = _planet.to_local(camera.global_position)
	var up: Vector3 = eye.normalized()
	var altitude: float = eye.length() - _planet.surface_radius(up)
	var near_ground: bool = Planet.nearest(get_tree(), camera.global_position) == _planet and altitude < 1500.0
	var sun_height: float = up.dot(_director.sun_direction)
	_update_birds(delta, eye, up, near_ground and sun_height > 0.02)
	_update_deer(delta, eye, up, near_ground and altitude < 400.0 and sun_height > -0.05)
	_update_fireflies(eye, up, near_ground and altitude < 200.0, sun_height)


func _surface(direction: Vector3, lift: float = 0.0) -> Vector3:
	return direction * (_noise.radius + maxf(_noise.height(direction), 0.0) + lift)


func _offset(up: Vector3, angle: float, distance: float) -> Vector3:
	var tangent: Vector3 = SurfaceSites.tangent_forward(up).rotated(up, angle)
	return SurfaceSites.offset_direction(up, tangent, distance, _noise.radius)


# —— 鸟群 ——

func _build_birds() -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body: Color = Color(0.22, 0.24, 0.28)
	# 机身是细长的菱形，两翼各一个三角形，翼尖略向后掠。
	var parts: Array = [
		[Vector3(0.0, 0.0, -0.32), Vector3(0.07, 0.0, 0.0), Vector3(0.0, 0.0, 0.30), 0.0],
		[Vector3(0.0, 0.0, -0.32), Vector3(0.0, 0.0, 0.30), Vector3(-0.07, 0.0, 0.0), 0.0],
		[Vector3(0.05, 0.0, -0.10), Vector3(0.62, 0.04, 0.10), Vector3(0.05, 0.0, 0.10), 1.0],
		[Vector3(-0.05, 0.0, -0.10), Vector3(-0.05, 0.0, 0.10), Vector3(-0.62, 0.04, 0.10), 1.0],
	]
	for part: Array in parts:
		for index: int in 3:
			var point: Vector3 = part[index]
			tool.set_color(body)
			tool.set_normal(Vector3.UP)
			tool.set_uv2(Vector2(absf(point.x) / 0.62 * part[3], 0.0))
			tool.add_vertex(point)
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = tool.commit()
	multi.instance_count = FLOCKS * BIRDS_PER_FLOCK
	for index: int in multi.instance_count:
		multi.set_instance_custom_data(index, Color(_rng.randf(), 0.0, 0.0))
	_birds = MultiMeshInstance3D.new()
	_birds.name = "Birds"
	_birds.multimesh = multi
	_birds.material_override = _bird_material
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_birds.extra_cull_margin = 2000.0
	add_child(_birds)
	for flock: int in FLOCKS:
		_flocks.append({"center": Vector3.ZERO, "radius": 0.0, "height": 0.0, "speed": 0.0, "drift": 0.0})


func _update_birds(delta: float, eye: Vector3, up: Vector3, active: bool) -> void:
	_birds.visible = active
	if not active:
		return
	var multi: MultiMesh = _birds.multimesh
	for flock_index: int in FLOCKS:
		var flock: Dictionary = _flocks[flock_index]
		var center: Vector3 = flock["center"]
		if center == Vector3.ZERO or center.normalized().angle_to(up) * _noise.radius > 900.0:
			# 在玩家周围 250～550 米处重新放一群，高度离地 50～110 米。
			var direction: Vector3 = _offset(up, _rng.randf() * TAU, _rng.randf_range(250.0, 550.0))
			flock["center"] = direction
			flock["radius"] = _rng.randf_range(35.0, 70.0)
			flock["height"] = _rng.randf_range(50.0, 110.0)
			flock["speed"] = _rng.randf_range(0.14, 0.22) * (1.0 if _rng.randf() > 0.5 else -1.0)
			flock["drift"] = _rng.randf() * TAU
			center = direction
		# 整群缓慢漂移，看起来在巡游而不是钉在一个点上空。
		var drift_direction: Vector3 = _offset(center, flock["drift"], 1.8 * delta)
		flock["center"] = drift_direction
		var axis_a: Vector3 = SurfaceSites.tangent_forward(drift_direction)
		var axis_b: Vector3 = axis_a.cross(drift_direction)
		var base: Vector3 = _surface(drift_direction, flock["height"])
		for bird: int in BIRDS_PER_FLOCK:
			var angle: float = _time * float(flock["speed"]) + float(bird) * TAU / BIRDS_PER_FLOCK * 0.55 + sin(_time * 0.3 + bird) * 0.25
			var radius_value: float = float(flock["radius"]) * (0.75 + 0.25 * sin(bird * 2.1))
			var position: Vector3 = base + (axis_a * cos(angle) + axis_b * sin(angle)) * radius_value + drift_direction * sin(_time * 0.6 + bird) * 4.0
			var tangent: Vector3 = (axis_b * cos(angle) - axis_a * sin(angle)) * signf(flock["speed"])
			# 转弯时向圆心侧倾。
			var bank: float = 0.35 * signf(flock["speed"])
			var basis: Basis = Basis.looking_at(tangent, drift_direction).rotated(tangent.normalized(), bank)
			multi.set_instance_transform(flock_index * BIRDS_PER_FLOCK + bird, Transform3D(basis.scaled(Vector3.ONE * 1.4), position))


# —— 鹿 ——

func _build_deer() -> void:
	for index: int in DEER:
		var root: Node3D = Node3D.new()
		root.name = "Deer%d" % index
		root.visible = false
		add_child(root)
		var adult: bool = index != DEER - 1
		var scale_value: float = 1.0 if adult else 0.7
		var coat: Color = Color(0.66, 0.46, 0.30).lerp(Color(0.74, 0.58, 0.40), float(index) / DEER)
		var body: Node3D = Node3D.new()
		root.add_child(body)
		_blob(body, Vector3(0.0, 1.0, 0.0), Vector3(0.36, 0.34, 0.75), coat, Vector3.ZERO, true)
		_blob(body, Vector3(0.0, 0.92, 0.0), Vector3(0.30, 0.22, 0.62), coat.lerp(Color(0.92, 0.86, 0.74), 0.6))
		_blob(body, Vector3(0.0, 1.15, 0.62), Vector3(0.08, 0.10, 0.08), Color(0.94, 0.90, 0.82))
		var neck: Node3D = Node3D.new()
		neck.position = Vector3(0.0, 1.18, -0.55)
		body.add_child(neck)
		_blob(neck, Vector3(0.0, 0.22, -0.08), Vector3(0.13, 0.30, 0.14), coat)
		_blob(neck, Vector3(0.0, 0.48, -0.24), Vector3(0.13, 0.13, 0.25), coat)
		_blob(neck, Vector3(0.0, 0.46, -0.46), Vector3(0.05, 0.05, 0.05), Color(0.15, 0.12, 0.11))
		for side: float in [-1.0, 1.0]:
			_blob(neck, Vector3(side * 0.12, 0.62, -0.18), Vector3(0.04, 0.10, 0.03), coat)
			if index == 0:
				# 领头的一只长着分叉的角。
				_blob(neck, Vector3(side * 0.10, 0.80, -0.16), Vector3(0.025, 0.18, 0.025), Color(0.86, 0.80, 0.66), Vector3(0.0, 0.0, side * 0.35))
				_blob(neck, Vector3(side * 0.17, 0.92, -0.22), Vector3(0.02, 0.10, 0.02), Color(0.86, 0.80, 0.66), Vector3(-0.4, 0.0, side * 0.7))
		var legs: Array[Node3D] = []
		for leg_index: int in 4:
			var leg: Node3D = Node3D.new()
			leg.position = Vector3(0.18 if leg_index % 2 == 0 else -0.18, 0.86, -0.48 if leg_index < 2 else 0.46)
			body.add_child(leg)
			_blob(leg, Vector3(0.0, -0.42, 0.0), Vector3(0.05, 0.44, 0.06), coat.darkened(0.15))
			_blob(leg, Vector3(0.0, -0.85, -0.02), Vector3(0.05, 0.04, 0.06), Color(0.18, 0.14, 0.12))
			legs.append(leg)
		root.scale = Vector3.ONE * scale_value
		_deer.append({"node": root, "neck": neck, "legs": legs, "direction": Vector3.ZERO, "heading": 0.0, "state": "graze", "timer": 0.0, "phase": _rng.randf() * TAU, "speed": 0.0})


# 只有身体投影；腿、头和角这些细小部件不投影，避免四级阴影成倍增加绘制次数。
func _blob(parent: Node3D, location: Vector3, size: Vector3, color: Color, angles: Vector3 = Vector3.ZERO, casts_shadow: bool = false) -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.position = location
	part.rotation = angles
	part.scale = size
	# 球体网格没有顶点色，颜色写进实例参数，所有部件共用一个材质。
	part.set_instance_shader_parameter("tint", color)
	parent.add_child(part)


func _herd_spot(up: Vector3) -> Vector3:
	# 在玩家前后左右 120～260 米找一块草甸或干草地，避开水边和陡坡。
	for attempt: int in 24:
		var direction: Vector3 = _offset(up, _rng.randf() * TAU, _rng.randf_range(120.0, 260.0))
		var elevation: float = _noise.height(direction)
		if elevation < 5.0 or elevation > 1200.0 or _noise.water_surface(direction) > -INF or _noise.river_distance(direction) < 15.0:
			continue
		var biome: String = _noise.biome(direction)
		if (biome == "草甸" or biome == "干草地") and _noise.slope(direction, elevation) < 0.25:
			return direction
	return Vector3.ZERO


func _update_deer(delta: float, eye: Vector3, up: Vector3, active: bool) -> void:
	var player_speed: float = 0.0
	var player: StarSeaPlayer = get_tree().current_scene.get_node_or_null("Player") as StarSeaPlayer if get_tree().current_scene != null else null
	if player != null:
		player_speed = player.velocity.length()
	if not active:
		for deer: Dictionary in _deer:
			(deer["node"] as Node3D).visible = false
		return
	if _herd_center == Vector3.ZERO or _herd_center.angle_to(up) * _noise.radius > 700.0:
		_herd_center = _herd_spot(up)
		for deer: Dictionary in _deer:
			deer["direction"] = Vector3.ZERO
		if _herd_center == Vector3.ZERO:
			return
	var scare: float = SCARE_DISTANCE * (2.0 if player_speed > 6.0 else 1.0)
	for index: int in _deer.size():
		var deer: Dictionary = _deer[index]
		var node: Node3D = deer["node"]
		if deer["direction"] == Vector3.ZERO:
			deer["direction"] = _offset(_herd_center, _rng.randf() * TAU, _rng.randf_range(3.0, 14.0))
			deer["heading"] = _rng.randf() * TAU
			deer["state"] = "graze"
			deer["timer"] = _rng.randf_range(2.0, 6.0)
		var direction: Vector3 = deer["direction"]
		var distance_to_player: float = direction.angle_to(up) * _noise.radius
		var away: Vector3 = (direction - up * direction.dot(up)) if distance_to_player > 0.1 else SurfaceSites.tangent_forward(direction)
		var forward_zero: Vector3 = SurfaceSites.tangent_forward(direction)
		var right_zero: Vector3 = forward_zero.cross(direction)
		var state: String = deer["state"]
		deer["timer"] = float(deer["timer"]) - delta
		if distance_to_player < scare and state != "flee":
			state = "flee"
			deer["timer"] = _rng.randf_range(5.0, 7.0)
			deer["heading"] = atan2(away.dot(right_zero), away.dot(forward_zero)) + _rng.randf_range(-0.4, 0.4)
		elif distance_to_player < scare * 2.2 and state == "graze":
			state = "alert"
			deer["timer"] = _rng.randf_range(1.5, 3.0)
		elif float(deer["timer"]) <= 0.0:
			# 平静时在吃草和慢走之间切换；受惊跑完后先停下来张望。
			state = "walk" if state == "graze" else "graze"
			deer["timer"] = _rng.randf_range(3.0, 8.0)
			if state == "walk":
				deer["heading"] = float(deer["heading"]) + _rng.randf_range(-1.2, 1.2)
		deer["state"] = state
		var target_speed: float = {"graze": 0.0, "alert": 0.0, "walk": 1.1, "flee": 9.0}[state]
		deer["speed"] = lerpf(deer["speed"], target_speed, clampf(delta * 3.0, 0.0, 1.0))
		var heading: float = deer["heading"]
		var tangent: Vector3 = (forward_zero * cos(heading) + right_zero * sin(heading)).normalized()
		var next: Vector3 = SurfaceSites.offset_direction(direction, tangent, float(deer["speed"]) * delta, _noise.radius)
		# 前方是水面或陡坡就掉头，不会走进河里。
		var next_height: float = _noise.height(next)
		if _noise.water_surface(next) > next_height - 0.2 or next_height < 1.0 or _noise.slope(next, next_height) > 0.45:
			deer["heading"] = heading + PI * 0.6
		else:
			direction = next
		deer["direction"] = direction
		var facing: Vector3 = tangent if state != "alert" else (-away).normalized()
		node.transform = Transform3D(Basis.looking_at(facing, direction).scaled(node.scale), _surface(direction))
		node.visible = true
		deer["phase"] = float(deer["phase"]) + delta * (2.0 + float(deer["speed"]) * 2.2)
		var stride: float = sin(float(deer["phase"])) * minf(float(deer["speed"]) / 3.0, 1.0)
		var legs: Array[Node3D] = deer["legs"]
		for leg_index: int in 4:
			var opposite: float = 1.0 if leg_index == 0 or leg_index == 3 else -1.0
			legs[leg_index].rotation.x = stride * 0.6 * opposite
		var neck: Node3D = deer["neck"]
		var bow: float = 1.1 if state == "graze" else (-0.15 if state == "alert" else 0.1)
		neck.rotation.x = lerpf(neck.rotation.x, bow + sin(_time * 1.3 + index) * 0.05, clampf(delta * 4.0, 0.0, 1.0))


# —— 萤火 ——

func _build_fireflies() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = FIREFLIES
	for index: int in FIREFLIES:
		multi.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), 0.0))
	_firefly_material = ShaderMaterial.new()
	_firefly_material.shader = load("res://shaders/firefly.gdshader") as Shader
	_fireflies = MultiMeshInstance3D.new()
	_fireflies.name = "Fireflies"
	_fireflies.multimesh = multi
	_fireflies.material_override = _firefly_material
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.extra_cull_margin = 200.0
	_fireflies.visible = false
	add_child(_fireflies)


func _update_fireflies(eye: Vector3, up: Vector3, near_ground: bool, sun_height: float) -> void:
	var night: float = 1.0 - smoothstep(-0.12, -0.02, sun_height)
	_fireflies.visible = near_ground and night > 0.01
	if not _fireflies.visible:
		return
	_firefly_material.set_shader_parameter("intensity", night)
	if _firefly_center != Vector3.ZERO and _firefly_center.angle_to(up) * _noise.radius < 30.0:
		return
	_firefly_center = up
	# 只在潮湿的地方放：湿地、林地、河湖边；其余的放到地下藏起来。
	var multi: MultiMesh = _fireflies.multimesh
	for index: int in FIREFLIES:
		var direction: Vector3 = _offset(up, _rng.randf() * TAU, sqrt(_rng.randf()) * 70.0)
		var elevation: float = _noise.height(direction)
		var moist: bool = _noise.moisture(direction) > 0.58 or _noise.river_distance(direction) < 40.0 or _noise.woodland(direction) > 0.6
		if elevation < 0.5 or _noise.water_surface(direction) > elevation or not moist:
			multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, direction * (_noise.radius - 50.0)))
			continue
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, _surface(direction, _rng.randf_range(0.6, 2.8))))
