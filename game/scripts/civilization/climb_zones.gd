class_name ClimbZones
extends Node3D

const BUILD_DISTANCE: float = 300.0 # 仅在玩家三百米内生成攀爬外形。
const CAVE_MANTLE_HEIGHT: float = 1.5 # 天井出口越过岩石边缘时，脚底弧线的额外净空，米。
var zones: Array[Dictionary] = []
var _placements: Array[Dictionary] = []
var _visuals: Dictionary[String, Node3D] = {}
var _elapsed: float = 1.0
var _time: float = 0.0
var _prop_meshes: Dictionary[String, ArrayMesh] = {}


func _ready() -> void:
	var layout: Resource = load(ClimbLayout.LAYOUT_PATH)
	var data: Dictionary = layout.get("metadata").get("climbs", {})
	zones.assign(data.get("zones", []).duplicate(true))
	var planet: Planet = get_parent() as Planet
	if planet.noise.features.civilization != null:
		zones.append_array(planet.noise.features.civilization.data.climbs.duplicate(true))
	if planet.noise.features.caves != null:
		for network: Dictionary in planet.noise.features.caves.networks:
			for source: Dictionary in network["climbs"]:
				var zone: Dictionary = source.duplicate(true)
				zone["mantle_height"] = CAVE_MANTLE_HEIGHT
				zones.append(zone)
	_placements.assign(data.get("placements", []))
	var builder: RuinBuilder = RuinBuilder.new()
	add_child(builder)
	builder.build(_placements)
	for zone: Dictionary in zones:
		if not zone.get("support_wall", false):
			continue
		# 显示模型按高度缩放；碰撞直接使用最终米制尺寸，避免缩放物理节点。
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 2
		var normal: Vector3 = zone["normal"]
		var bottom: Vector3 = zone["bottom"]
		var along: Vector3 = bottom.direction_to(zone["top"])
		var height: float = bottom.distance_to(zone["top"])
		body.transform = Transform3D(Basis.looking_at(normal, along), bottom + along * height * 0.5 - normal * 0.3)
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(float(zone["width"]), height, 0.6)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)


func zone_near(position_local: Vector3, prefer_bottom: bool = true) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	for zone: Dictionary in zones:
		var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(position_local, zone["bottom"], zone["top"])
		if position_local.distance_to(nearest) > float(zone["width"]) + 4.0 and position_local.distance_to(zone["exit_top"]) > 0.9:
			continue
		var point: Dictionary = contact(zone, position_local)
		var offset: Vector3 = position_local - Vector3(point["position"])
		var normal: Vector3 = point["normal"]
		var across: float = absf(offset.dot(Vector3(point["tangent"]).cross(normal).normalized()))
		var on_face: bool = across <= float(zone["width"]) * 0.5 and absf(offset.dot(normal) - 0.45) < 0.6 and offset.length() < float(zone["width"]) + 0.6
		if not on_face and position_local.distance_to(zone["exit_top"]) >= 0.9:
			continue
		var score: float = position_local.distance_to(zone["bottom"] if prefer_bottom else zone["top"])
		if score < best_score:
			best_score = score
			best = zone
	return best


static func length(zone: Dictionary) -> float:
	return float((zone["path_lengths"] as PackedFloat32Array)[-1]) if zone.has("path") else Vector3(zone["bottom"]).distance_to(zone["top"])


static func point_at(zone: Dictionary, progress: float) -> Dictionary:
	if not zone.has("path"):
		var bottom: Vector3 = zone["bottom"]
		var tangent: Vector3 = bottom.direction_to(zone["top"])
		return {"position": bottom + tangent * clampf(progress, 0, length(zone)), "normal": zone["normal"], "tangent": tangent}
	var points: PackedVector3Array = zone["path"]
	var normals: PackedVector3Array = zone["path_normals"]
	var lengths: PackedFloat32Array = zone["path_lengths"]
	var segment: int = 0
	while segment + 1 < lengths.size() - 1 and lengths[segment + 1] < progress:
		segment += 1
	var weight: float = clampf((progress - lengths[segment]) / maxf(lengths[segment + 1] - lengths[segment], 0.001), 0, 1)
	return {"position": points[segment].lerp(points[segment + 1], weight), "normal": normals[segment].lerp(normals[segment + 1], weight).normalized(), "tangent": points[segment].direction_to(points[segment + 1])}


static func contact(zone: Dictionary, position_local: Vector3) -> Dictionary:
	var points: PackedVector3Array = zone.get("path", PackedVector3Array([zone["bottom"], zone["top"]]))
	var lengths: PackedFloat32Array = zone.get("path_lengths", PackedFloat32Array([0.0, length(zone)]))
	var best: float = INF
	var progress: float = 0.0
	for index: int in points.size() - 1:
		var delta: Vector3 = points[index + 1] - points[index]
		var weight: float = clampf((position_local - points[index]).dot(delta) / maxf(delta.length_squared(), 0.0001), 0, 1)
		var distance: float = position_local.distance_squared_to(points[index].lerp(points[index + 1], weight))
		if distance < best:
			best = distance
			progress = lerpf(lengths[index], lengths[index + 1], weight)
	var result: Dictionary = point_at(zone, progress)
	result["progress"] = progress
	return result


func _process(delta: float) -> void:
	var player: StarSeaPlayer = get_tree().current_scene.get_node_or_null("Player") as StarSeaPlayer if get_tree().current_scene != null else null
	if player == null:
		return
	var director: SkyDirector = get_tree().get_first_node_in_group("sky_director") as SkyDirector
	if director == null or not director.time_paused:
		_time += delta
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var eye: Vector3 = to_local(player.global_position)
	for zone: Dictionary in zones:
		var id: String = zone["id"]
		var distance: float = eye.distance_to(Geometry3D.get_closest_point_to_segment(eye, zone["bottom"], zone["top"]))
		if distance < BUILD_DISTANCE and not _visuals.has(id):
			_visuals[id] = _build(zone)
		elif distance > BUILD_DISTANCE + 30.0 and _visuals.has(id):
			_visuals[id].queue_free()
			_visuals.erase(id)
		if zone["kind"] == "rope" and _visuals.has(id):
			var visual: Node3D = _visuals[id]
			# 绳子以上端为轴，攀爬时停摆；底端摆幅最多三十厘米。
			var swing: float = 0.0 if zone.get("occupied", false) else sin(_time * 0.7) * 0.3 / maxf(1.0, Vector3(zone["bottom"]).distance_to(zone["top"]))
			visual.basis = (visual.get_meta("rest_basis") as Basis) * Basis(Vector3.FORWARD, swing)


func _build(zone: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	add_child(root)
	var bottom: Vector3 = zone["bottom"]
	var top: Vector3 = zone["top"]
	var along: Vector3 = bottom.direction_to(top)
	var normal: Vector3 = zone["normal"]
	var across: Vector3 = along.cross(normal).normalized()
	var frame: Basis = Basis(across, along, normal)
	root.transform = Transform3D(frame, top)
	root.set_meta("rest_basis", frame)
	var height: float = bottom.distance_to(top)
	if zone["kind"] == "vine_wall":
		var vine: MeshInstance3D = MeshInstance3D.new()
		vine.mesh = RuinKit.mesh("vine_wall")
		var bounds: AABB = vine.mesh.get_aabb()
		vine.scale = Vector3(float(zone["width"]) / bounds.size.x, height / bounds.size.y, 1)
		vine.rotation.y = PI
		vine.position = Vector3(0, -height, 0)
		root.add_child(vine)
	elif zone["kind"] == "rope":
		var offset: float = 0.0
		var transforms: Array[Transform3D] = []
		while offset < height:
			var length: float = minf(1.2, height - offset)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, length / 1.2, 1)), Vector3(0, -height + offset, 0)))
			offset += 1.2
		_batch(root, "climb_rope", transforms)
		_batch(root, "climb_anchor", [Transform3D.IDENTITY])
	else:
		var transforms: Array[Transform3D] = []
		var footholds: Array[Transform3D] = []
		for index: int in ceili(length(zone) / 0.5):
			var point: Dictionary = point_at(zone, index * 0.5)
			var tangent: Vector3 = point["tangent"]
			var outward: Vector3 = point["normal"]
			var side: Vector3 = tangent.cross(outward).normalized()
			var placement: Transform3D = Transform3D(Basis(side, tangent, outward), Vector3(point["position"]) + side * (-0.22 if index % 2 == 0 else 0.22))
			placement = root.transform.affine_inverse() * placement
			footholds.append(placement)
			if index % 4 == 0:
				transforms.append(placement)
		_batch(root, "climb_peg", transforms)
		_batch(root, "climb_foothold", footholds)
	return root


func _prop_mesh(piece: String) -> ArrayMesh:
	if _prop_meshes.has(piece):
		return _prop_meshes[piece]
	var source_piece: String = "climb_peg" if piece == "climb_foothold" else piece
	var model: Node3D = (load("res://models/explorer/" + source_piece + ".glb") as PackedScene).instantiate() as Node3D
	var surfaces: Dictionary[String, SurfaceTool] = {}
	var materials: Dictionary[String, StandardMaterial3D] = {}
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if piece == "climb_foothold" and mesh.name != "FootHold":
			continue
		var transform_value: Transform3D = mesh.transform
		var parent: Node = mesh.get_parent()
		while parent != model:
			if parent is Node3D:
				transform_value = (parent as Node3D).transform * transform_value
			parent = parent.get_parent()
		for index: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(index) as StandardMaterial3D
			var key: String = source.resource_name
			if not surfaces.has(key):
				surfaces[key] = SurfaceTool.new()
				surfaces[key].begin(Mesh.PRIMITIVE_TRIANGLES)
				materials[key] = source
			surfaces[key].append_from(mesh.mesh, index, transform_value)
	var result: ArrayMesh = ArrayMesh.new()
	for key: String in surfaces:
		var material: ShaderMaterial = ShaderMaterial.new()
		if piece == "climb_peg" and key.ends_with("light"):
			material = RuinKit.material(2).duplicate() as ShaderMaterial
			material.set_shader_parameter("awake", 0.25)
		else:
			material.shader = load("res://shaders/explorer.gdshader") as Shader
			material.set_shader_parameter("pigment", Color(0.66, 0.57, 0.44) if piece == "climb_foothold" else materials[key].albedo_color)
		surfaces[key].set_material(material)
		surfaces[key].commit(result)
	model.free()
	_prop_meshes[piece] = result
	return result


func _batch(parent: Node3D, piece: String, transforms: Array[Transform3D]) -> void:
	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _prop_mesh(piece)
	batch.instance_count = transforms.size()
	for index: int in transforms.size():
		batch.set_instance_transform(index, transforms[index])
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	visual.multimesh = batch
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
