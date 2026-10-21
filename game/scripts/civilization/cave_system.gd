class_name CaveSystem
extends Node3D

const BUILD_BUDGET_US: int = 2000 # 单帧创建与释放预算，两毫秒。
const DRAW_RANGE: float = 600.0
const COLLISION_RANGE: float = 150.0
const CAVE_SHADER: Shader = preload("res://shaders/cave.gdshader")
const COLLISION_SLICE: int = 768 # 每次最多创建二百五十六个三角形的碰撞，避免整块构建 BVH。
var data: CaveData
var seen: Array[String] = []
var cave_blend: float = 0.0
var active_lights: int = 0
var maximum_build_us: int = 0
var maximum_mesh_us: int = 0
var maximum_collision_us: int = 0
var maximum_props_us: int = 0
var _planet: Planet
var _built: Dictionary = {}
var _bodies: Dictionary = {}
var _props: Dictionary = {}
var _lamps: Array[Light3D] = []
var _shaft_materials: Array[ShaderMaterial] = []
var _lantern: OmniLight3D
var _lantern_mesh: Node3D
var _elapsed: float = 1.0
var _time: float = 0.0
var _cursor: int = 0
var _materials: Array[ShaderMaterial] = []
var _collision_jobs: Dictionary = {}
var _prop_groups: Array[Dictionary] = []
var _mural_scenes: Array[PackedScene] = []
var _prop_cursor: int = 0
var _water_materials: Array[ShaderMaterial] = []
var _dust_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = get_parent() as Planet
	data = _planet.noise.features.caves
	for index: int in 6:
		_mural_scenes.append(load("res://models/cave/mural_%d.glb" % index) as PackedScene)
	for network: Dictionary in data.networks:
		var material_value: ShaderMaterial = ShaderMaterial.new()
		material_value.shader = CAVE_SHADER
		material_value.set_shader_parameter("local_up", Transform3D(network["frame"]).basis.y)
		_materials.append(material_value)
		# 启动时缓存既有构件，接近洞口后只创建实例，避免分块阶段首次解析 glb。
		var pieces: Dictionary = {}
		for record: Dictionary in network["props"]:
			pieces[record["piece"]] = true
		for piece: String in pieces:
			RuinKit.mesh(piece)
		var groups: Dictionary = {}
		var frame: Transform3D = network["frame"]
		var mural: int = 0
		for original: Dictionary in network["props"]:
			var record: Dictionary = original.duplicate()
			if record["piece"] == "mural_panel":
				record["mural"] = mural
				mural += 1
			var at: Vector3 = frame.affine_inverse() * Transform3D(record["transform"]).origin
			var key: Vector3i = Vector3i((at / CaveData.BLOCK).floor())
			if not groups.has(key):
				groups[key] = []
			groups[key].append(record)
		for key: Vector3i in groups:
			_prop_groups.append({"position": frame * (Vector3(key) * CaveData.BLOCK + Vector3.ONE * 16), "records": groups[key]})
		_build_water(network, self)
		for record: Dictionary in network["lights"]:
			var lamp: Light3D
			if record["kind"] == "shaft":
				var spot: SpotLight3D = SpotLight3D.new()
				spot.spot_range = float(record["range"]) * 1.6
				spot.spot_angle = 18
				spot.transform = Transform3D(Basis.looking_at(Vector3(record["position"]).direction_to(record["target"]), Vector3(record["position"]).normalized().cross(Vector3.RIGHT).normalized()), record["position"])
				lamp = spot
				_build_shaft(record)
			else:
				var omni: OmniLight3D = OmniLight3D.new()
				omni.omni_range = record["range"]
				omni.position = record["position"]
				lamp = omni
			lamp.light_color = record["color"]
			lamp.light_energy = 1.2
			if record["kind"] == "shaft":
				lamp.light_energy = 18.0
			lamp.shadow_enabled = false
			lamp.visible = false
			add_child(lamp)
			_lamps.append(lamp)
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color("ffd9a0")
	_lantern.omni_range = 9
	_lantern.light_energy = 0
	_lantern.shadow_enabled = false
	add_child(_lantern)
	if ResourceLoader.exists("res://models/cave/lantern.glb"):
		_lantern_mesh = (load("res://models/cave/lantern.glb") as PackedScene).instantiate() as Node3D
		add_child(_lantern_mesh)


func _build_shaft(record: Dictionary) -> void:
	var top: Vector3 = record["position"]
	var target: Vector3 = record["target"]
	var length_value: float = top.distance_to(target)
	var material_value: ShaderMaterial = ShaderMaterial.new()
	material_value.shader = load("res://shaders/light_shaft.gdshader") as Shader
	_shaft_materials.append(material_value)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 3.8
	cone.bottom_radius = 7
	cone.height = length_value
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = material_value
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = DRAW_RANGE
	var up: Vector3 = target.direction_to(top)
	var right: Vector3 = SurfaceSites.tangent_forward(up)
	# 用一盏低能量点光近似井底反射，保留巨像正面的轮廓。
	var bounce: OmniLight3D = OmniLight3D.new()
	bounce.position = target + up * 4
	bounce.omni_range = 18
	bounce.light_energy = 1.2
	bounce.light_color = Color("fff0d2")
	bounce.shadow_enabled = false
	bounce.visible = false
	bounce.set_meta("shaft_bounce", true)
	add_child(bounce)
	_lamps.append(bounce)
	mesh.transform = Transform3D(Basis(right, up, right.cross(up)), top.lerp(target, 0.5))
	add_child(mesh)
	var dust: MultiMesh = MultiMesh.new()
	dust.transform_format = MultiMesh.TRANSFORM_3D
	dust.use_custom_data = true
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * 0.04
	dust.mesh = quad
	dust.instance_count = 48
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261029
	for index: int in 48:
		var point: Vector3 = up * rng.randf_range(-length_value * 0.5, length_value * 0.5) + right * rng.randf_range(-3, 3) + right.cross(up) * rng.randf_range(-3, 3)
		dust.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
		dust.set_instance_custom_data(index, Color(rng.randf(), 0, 0))
	var dust_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	dust_instance.multimesh = dust
	dust_instance.position = top.lerp(target, 0.5)
	dust_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust_instance.visibility_range_end = DRAW_RANGE
	var dust_material: ShaderMaterial = ShaderMaterial.new()
	dust_material.shader = load("res://shaders/cave_dust.gdshader") as Shader
	dust_material.set_shader_parameter("up_direction", up)
	_dust_materials.append(dust_material)
	dust_instance.material_override = dust_material
	add_child(dust_instance)


func _process(delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: StarSeaPlayer = scene.get_node_or_null("Player") as StarSeaPlayer
	if player == null:
		return
	var camera: Camera3D = player.camera
	var local: Vector3 = _planet.to_local(camera.global_position)
	var id: int = data.cave_at(local)
	var blend: float = 0.0
	if id >= 0:
		blend = 1.0
		for entrance: Dictionary in data.networks[id]["entrances"]:
			blend = minf(blend, local.distance_to(entrance["position"]) / 30.0)
		if not get_tree().paused:
			_reveal(id, _planet.to_local(player.global_position))
	cave_blend = move_toward(cave_blend, blend, delta / 1.5)
	_lantern.position = _planet.to_local(camera.global_position - player.up_direction * 0.4) if not player.third_person else _planet.to_local(player.global_position + player.up_direction * 0.9)
	_lantern.light_energy = move_toward(_lantern.light_energy, 0.9 if cave_blend > 0.5 else 0.0, delta * 0.9)
	if _lantern_mesh != null:
		_lantern_mesh.visible = player.third_person and id >= 0
		_lantern_mesh.transform = Transform3D(_planet.global_basis.inverse() * player.global_basis, _planet.to_local(player.global_position + player.global_basis * Vector3(-0.27, 0.95, 0.05)))
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	if not get_tree().paused and not director.time_paused:
		_time += delta
	for material_value: ShaderMaterial in _shaft_materials:
		material_value.set_shader_parameter("phase", _time)
		material_value.set_shader_parameter("strength", 0.04 if _planet.to_local(camera.global_position).normalized().dot(director.sun_direction) > 0 else 0.012)
		material_value.set_shader_parameter("tint", Color("fff0d2") if local.normalized().dot(director.sun_direction) > 0 else Color("b0c6ed"))
	for material_value: ShaderMaterial in _dust_materials:
		material_value.set_shader_parameter("phase", _time)
	for material_value: ShaderMaterial in _water_materials:
		material_value.set_shader_parameter("cave_time", _time)
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		_lamps.sort_custom(func(a: Light3D, b: Light3D) -> bool: return a.position.distance_squared_to(local) < b.position.distance_squared_to(local))
		active_lights = 0
		for index: int in _lamps.size():
			_lamps[index].visible = index < 11 and _lamps[index].position.distance_to(local) < DRAW_RANGE
			active_lights += int(_lamps[index].visible)
			if _lamps[index] is SpotLight3D:
				_lamps[index].light_energy = 18 if local.normalized().dot(director.sun_direction) > 0 else 5.4
				_lamps[index].light_color = Color("fff0d2") if local.normalized().dot(director.sun_direction) > 0 else Color("b0c6ed")
			elif _lamps[index].has_meta("shaft_bounce"):
				_lamps[index].light_energy = 1.2 if local.normalized().dot(director.sun_direction) > 0 else 0.36
	_update_chunks(local)


func _reveal(id: int, position_value: Vector3) -> void:
	for node: Dictionary in data.networks[id]["nodes"] + data.networks[id].get("map_nodes", []):
		var key: String = "%d:%s" % [id, node["id"]]
		if position_value.distance_to(node["position"]) < 20 and not seen.has(key):
			seen.append(key)


func _update_chunks(eye: Vector3) -> void:
	var started: int = Time.get_ticks_usec()
	for count: int in data.chunks.size():
		if Time.get_ticks_usec() - started > BUILD_BUDGET_US - 700:
			break
		var index: int = _cursor
		_cursor = (_cursor + 1) % data.chunks.size()
		var record: Dictionary = data.chunks[index]
		var frame: Transform3D = data.networks[record["network"]]["frame"]
		var bounds: AABB = record["bounds"]
		var distance: float = (frame.affine_inverse() * eye).distance_to(bounds.get_center())
		if distance < DRAW_RANGE + 28 and not _built.has(index):
			var mesh_started: int = Time.get_ticks_usec()
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = record["vertices"]
			arrays[Mesh.ARRAY_NORMAL] = record["normals"]
			arrays[Mesh.ARRAY_COLOR] = record["colors"]
			arrays[Mesh.ARRAY_INDEX] = record["indices"]
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = _materials[record["network"]]
			instance.transform = frame * Transform3D(Basis.IDENTITY, record["origin"])
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			_built[index] = instance
			maximum_mesh_us = maxi(maximum_mesh_us, Time.get_ticks_usec() - mesh_started)
			# 每帧只进行一次创建，避免网格、碰撞和摆设各自达标却累计超时。
			maximum_build_us = maxi(maximum_build_us, Time.get_ticks_usec() - started)
			return
		if distance > 700 + 28 and _built.has(index):
			(_built[index] as Node3D).queue_free()
			_built.erase(index)
		if distance < COLLISION_RANGE + 28 and _built.has(index) and not _bodies.has(index):
			var collision_started: int = Time.get_ticks_usec()
			if not _collision_jobs.has(index):
				var body: StaticBody3D = StaticBody3D.new()
				body.transform = (_built[index] as MeshInstance3D).transform
				body.collision_layer = 1
				add_child(body)
				_collision_jobs[index] = {"body": body, "cursor": 0}
			var job: Dictionary = _collision_jobs[index]
			var faces: PackedVector3Array = record["faces"]
			var end: int = mini(int(job["cursor"]) + COLLISION_SLICE, faces.size())
			var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
			shape.set_faces(faces.slice(job["cursor"], end))
			shape.backface_collision = true
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = shape
			(job["body"] as StaticBody3D).add_child(collision)
			job["cursor"] = end
			if end == faces.size():
				_bodies[index] = job["body"]
				_collision_jobs.erase(index)
			maximum_collision_us = maxi(maximum_collision_us, Time.get_ticks_usec() - collision_started)
			maximum_build_us = maxi(maximum_build_us, Time.get_ticks_usec() - started)
			return
		if distance > 200 + 28 and _bodies.has(index):
			(_bodies[index] as Node3D).queue_free()
			_bodies.erase(index)
		if distance > 200 + 28 and _collision_jobs.has(index):
			(_collision_jobs[index]["body"] as Node3D).queue_free()
			_collision_jobs.erase(index)
		if Time.get_ticks_usec() - started >= BUILD_BUDGET_US:
			break
	maximum_build_us = maxi(maximum_build_us, Time.get_ticks_usec() - started)
	# 摆设按三十二米格子分帧创建，避免一次实例化整个网络。
	for count: int in _prop_groups.size():
		if Time.get_ticks_usec() - started > BUILD_BUDGET_US - 700:
			break
		var id: int = _prop_cursor
		_prop_cursor = (_prop_cursor + 1) % _prop_groups.size()
		var group: Dictionary = _prop_groups[id]
		var near: bool = eye.distance_to(group["position"]) < DRAW_RANGE + 28
		if near and not _props.has(id):
			var props_started: int = Time.get_ticks_usec()
			var builder: RuinBuilder = RuinBuilder.new()
			add_child(builder)
			var placements: Array[Dictionary] = []
			for record: Dictionary in group["records"]:
				if record["piece"] != "mural_panel":
					placements.append(record)
					continue
				var model: Node3D = _mural_scenes[record["mural"]].instantiate() as Node3D
				model.transform = record["transform"]
				for child: Node in model.find_children("*", "MeshInstance3D", true, false):
					var mesh: MeshInstance3D = child as MeshInstance3D
					for surface: int in mesh.mesh.get_surface_count():
						var source: Material = mesh.mesh.surface_get_material(surface)
						mesh.set_surface_override_material(surface, RuinKit.material(2 if source.resource_name.to_lower().begins_with("glyph") else 0))
					mesh.set_instance_shader_parameter("awake", 0.15)
				builder.add_child(model)
			builder.build(placements)
			_props[id] = builder
			maximum_props_us = maxi(maximum_props_us, Time.get_ticks_usec() - props_started)
			maximum_build_us = maxi(maximum_build_us, Time.get_ticks_usec() - started)
			return
		elif not near and _props.has(id):
			(_props[id] as Node3D).queue_free()
			_props.erase(id)
	maximum_build_us = maxi(maximum_build_us, Time.get_ticks_usec() - started)


func _build_water(network: Dictionary, owner_node: Node3D) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for water: Dictionary in network["waters"]:
		for edge_index: int in water["edges"]:
			var edge: Dictionary = network["edges"][edge_index]
			var a: Vector3 = network["nodes"][edge["a"]]["local"]
			var b: Vector3 = network["nodes"][edge["b"]]["local"]
			if b.y > a.y:
				var higher: Vector3 = b
				b = a
				a = higher
			var side: Vector3 = a.direction_to(b).cross(Vector3.UP).normalized() * float(water["width"]) * 0.5
			var steps: int = ceili(a.distance_to(b) / 2.0)
			for index: int in steps:
				var p: Vector3 = a.lerp(b, index / float(steps)) + Vector3.UP * 0.3
				var q: Vector3 = a.lerp(b, (index + 1) / float(steps)) + Vector3.UP * 0.3
				var corners: Array[Vector3] = [p - side, p + side, q - side, q + side]
				for corner: int in [0, 2, 1, 1, 2, 3]:
					surface.set_normal(Vector3.UP)
					surface.set_uv(Vector2(-1 if corner in [0, 2] else 1, (index + (1 if corner >= 2 else 0)) * 2.0))
					surface.add_vertex(corners[corner])
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material_value: ShaderMaterial = ShaderMaterial.new()
	material_value.shader = load("res://shaders/cave_water.gdshader") as Shader
	material_value.set_shader_parameter("shallow", Color(0.21, 0.37, 0.35))
	material_value.set_shader_parameter("deep", Color(0.065, 0.17, 0.21))
	_water_materials.append(material_value)
	mesh.material_override = material_value
	mesh.transform = network["frame"]
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = DRAW_RANGE
	owner_node.add_child(mesh)


func is_settled() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var eye: Vector3 = _planet.to_local(camera.global_position)
	for index: int in data.chunks.size():
		var record: Dictionary = data.chunks[index]
		var frame: Transform3D = data.networks[record["network"]]["frame"]
		var bounds: AABB = record["bounds"]
		var distance: float = (frame.affine_inverse() * eye).distance_to(bounds.get_center())
		if distance < DRAW_RANGE + 28 and not _built.has(index):
			return false
		if distance < COLLISION_RANGE + 28 and not _bodies.has(index):
			return false
	for id: int in _prop_groups.size():
		if eye.distance_to(_prop_groups[id]["position"]) < DRAW_RANGE + 28 and not _props.has(id):
			return false
	return true
