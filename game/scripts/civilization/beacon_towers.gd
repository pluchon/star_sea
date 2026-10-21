class_name BeaconTowers
extends Node3D

signal lit_changed(id: int)

const TOP: float = 18.0 # 塔冠与末段石阶齐平的实际行走面高度，米。
const NEAR_DISTANCE: float = 2000.0 # 两公里内创建完整模型和碰撞。
const CROWN_SCALE: float = 0.85 # 塔冠缩至直径六点八米，给最后一圈石阶保留头部净空。
var lit: Array[int] = []
var echo_fire: float = 0.0
var towers: Array[Dictionary] = []
var _planet: Planet
var _near: Dictionary = {}
var _far: Array[MeshInstance3D] = []
var _flares: Array[MeshInstance3D] = []
var _flames: Dictionary = {}
var _awake: Dictionary = {}
var _waiting: Dictionary = {}
var _dwell: Dictionary = {}
var _time: float = 0.0
var _elapsed: float = 1.0


func _ready() -> void:
	_planet = get_parent() as Planet
	towers = _planet.noise.features.civilization.data.beacons
	for tower: Dictionary in towers:
		var frame: Transform3D = tower_frame(tower, _planet.radius)
		var far: MeshInstance3D = MeshInstance3D.new()
		var scene: Node3D = (load("res://models/beacons/tower_far.glb") as PackedScene).instantiate() as Node3D
		far.mesh = (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		far.material_override = RuinKit.material(0)
		scene.free()
		far.transform = frame
		far.visibility_range_end = 25000.0
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(far)
		_far.append(far)
		var flare: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE
		flare.mesh = quad
		flare.position = frame * Vector3(0, TOP + 1.5, 0)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = load("res://shaders/beacon_flare.gdshader") as Shader
		material.render_priority = 2
		flare.material_override = material
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flare)
		_flares.append(flare)


static func tower_frame(tower: Dictionary, radius: float) -> Transform3D:
	var up: Vector3 = tower["direction"]
	return Transform3D(Basis.looking_at(tower["forward"], up), up * (radius + float(tower["height"])))


static func pieces(tower: Dictionary, radius: float) -> Array[Dictionary]:
	var frame: Transform3D = tower_frame(tower, radius)
	var records: Array[Dictionary] = []
	for index: int in 6:
		for piece: String in ["tower_drum", "tower_stair_broken" if index == 2 else "tower_stair"]:
			var basis: Basis = Basis(Vector3.UP, index * PI / 2.0) if piece.begins_with("tower_stair") else Basis.IDENTITY
			records.append({"piece": piece, "transform": frame * Transform3D(basis, Vector3(0, index * 3, 0)), "moss": 0.2, "sand": 0.1})
	for pair: Array in [["plinth_round", -1.0], ["tower_crown_broken", TOP - 0.5], ["brazier", TOP]]:
		# 塔冠缺口对准最后一段石阶，避免完整护墙封住登顶路线。
		var basis: Basis = Basis(Vector3.UP, -3.0 * PI / 4.0).scaled(Vector3(CROWN_SCALE, 1, CROWN_SCALE)) if pair[0] == "tower_crown_broken" else Basis.IDENTITY
		records.append({"piece": pair[0], "transform": frame * Transform3D(basis, Vector3(0, float(pair[1]), 0)), "moss": 0.15})
	# 使用既有环与径刻纹作嵌墙铭牌，与火盆一起在点亮时恢复琥珀光。
	for sign_value: float in [-1.0, 1.0]:
		var basis: Basis = Basis(Vector3.UP, 0.0 if sign_value > 0 else PI).scaled(Vector3.ONE * 0.8)
		records.append({"piece": "road_stone", "transform": frame * Transform3D(basis, Vector3(0, 8.0 if sign_value > 0 else 12.0, -3.18 * sign_value)), "collision": false})
	return records


func responding(id: int) -> bool:
	if lit.has(id):
		return false
	if id == 0:
		return true
	return lit.has(id - 1) and not _waiting.has(id)


func ignite(id: int, sound: bool = true) -> void:
	if id < 0 or id >= towers.size() or lit.has(id):
		return
	lit.append(id)
	lit.sort()
	_awake[id] = 0.0
	_waiting[id + 1] = 2.0
	if sound:
		var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		audio.stream = load("res://audio/beacon_ignite.wav") as AudioStream
		audio.position = tower_frame(towers[id], _planet.radius) * Vector3(0, TOP + 1, 0)
		audio.max_distance = 100.0
		audio.volume_db = -8
		add_child(audio)
		audio.finished.connect(audio.queue_free)
		audio.play()
	lit_changed.emit(id)


func set_lit(values: Array[int]) -> void:
	lit = values.duplicate()
	_waiting.clear()
	_dwell.clear()
	_awake.clear()
	for id: int in lit:
		_awake[id] = 1.0


func update_trigger(local: Vector3, grounded: bool, delta: float) -> void:
	for tower: Dictionary in towers:
		var id: int = tower["id"]
		if lit.has(id):
			continue
		var frame: Transform3D = tower_frame(tower, _planet.radius)
		var at: Vector3 = frame.affine_inverse() * local
		var valid: bool = grounded and Vector2(at.x, at.z).length() <= 3 and absf(at.y - TOP) < 0.6
		_dwell[id] = float(_dwell.get(id, 0)) + delta if valid else 0.0
		if float(_dwell[id]) >= 1.0:
			ignite(id)


func _process(delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: StarSeaPlayer = scene.get_node_or_null("Player") as StarSeaPlayer
	var camera: Camera3D = get_viewport().get_camera_3d()
	if player == null or camera == null:
		return
	var paused: bool = (scene.get_node("SkyDirector") as SkyDirector).time_paused
	if not paused:
		_time += delta
	for id: int in _waiting.keys():
		_waiting[id] = float(_waiting[id]) - delta
		if float(_waiting[id]) <= 0:
			_waiting.erase(id)
	for id: int in lit:
		_awake[id] = minf(float(_awake.get(id, 0.0)) + delta / 3.0, 1.0)
	update_trigger(_planet.to_local(player.global_position), player.current_planet() == _planet and player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor(), delta)
	_elapsed += delta
	for tower: Dictionary in towers:
		var id: int = tower["id"]
		var distance: float = _planet.to_global(tower_frame(tower, _planet.radius).origin).distance_to(camera.global_position)
		if _elapsed >= 0.5:
			if distance < NEAR_DISTANCE and not _near.has(id):
				_build_near(tower)
			elif distance > NEAR_DISTANCE + 300 and _near.has(id):
				(_near[id] as Node3D).queue_free()
				_near.erase(id)
				_flames.erase(id)
		_far[id].visible = not _near.has(id)
		var flare: MeshInstance3D = _flares[id]
		flare.visible = distance > 30 and distance < 25000 and (lit.has(id) or responding(id))
		if flare.visible:
			flare.global_basis = camera.global_basis
			var size_value: float = flare_size(distance, camera.fov, get_viewport().get_visible_rect().size.y)
			flare.scale = Vector3.ONE * size_value
			var daylight: float = smoothstep(-0.1, 0.2, Vector3(tower["direction"]).dot((scene.get_node("SkyDirector") as SkyDirector).sun_direction))
			var intensity: float = 1.0 if lit.has(id) else 0.35 + 0.2 * sin(_time * TAU / 4.0)
			(flare.material_override as ShaderMaterial).set_shader_parameter("strength", intensity * lerpf(1.0, 0.35, daylight))
		if _flames.has(id):
			var flame: Node3D = _flames[id]
			flame.scale = Vector3.ONE * (1 + echo_fire * 0.35 if id == towers.size() - 1 else 1.0)
			flame.visible = lit.has(id)
			for node: Node in flame.get_children():
				if node is MeshInstance3D:
					var material: ShaderMaterial = (node as MeshInstance3D).material_override as ShaderMaterial
					material.set_shader_parameter("flame_time", _time)
					material.set_shader_parameter("strength", float(_awake.get(id, 1.0)))
		if _near.has(id):
			for node: Node in (_near[id] as Node3D).get_children():
				if node is MultiMeshInstance3D:
					var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
					for index: int in multi.instance_count:
						var weather: Color = multi.get_instance_custom_data(index)
						weather.b = float(_awake.get(id, 0.0))
						multi.set_instance_custom_data(index, weather)
	if _elapsed >= 0.5:
		_elapsed = 0.0


static func flare_size(distance: float, fov: float, viewport_height: float) -> float:
	# 柔边面片的明亮核心约占四成，十六像素面片才能留下至少六像素光点。
	return maxf(0.15, distance * 2.0 * tan(deg_to_rad(fov) * 0.5) * 16.0 / maxf(viewport_height, 1.0))


func _build_near(tower: Dictionary) -> void:
	var id: int = tower["id"]
	var builder: RuinBuilder = RuinBuilder.new()
	add_child(builder)
	_near[id] = builder
	builder.build(pieces(tower, _planet.radius))
	var flames: Node3D = Node3D.new()
	flames.transform = tower_frame(tower, _planet.radius) * Transform3D(Basis.IDENTITY, Vector3(0, TOP + 1.0, 0))
	builder.add_child(flames)
	_flames[id] = flames
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/beacon_flame.gdshader") as Shader
	for index: int in 4:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(1.1, 1.7)
		mesh.mesh = quad
		mesh.rotation.y = index * PI / 4.0
		mesh.position.y = 0.85
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.add_child(mesh)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1, 0.59, 0.2)
	light.omni_range = 14
	light.light_energy = 1.6
	light.shadow_enabled = false
	flames.add_child(light)
