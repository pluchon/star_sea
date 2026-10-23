class_name EchoFigure
extends Node3D

const BLEND: float = 0.3 # 动作混合时间，秒。
const LOOPS: Array[String] = ["stand", "walk", "carry", "child_run", "old_walk"]
var animation: AnimationPlayer
var material_value: ShaderMaterial
var particles: GPUParticles3D
var pose: String = ""
var bundle: Node3D
var lamp: Node3D
var _skeleton: Skeleton3D


func build(child: bool = false) -> void:
	var model: Node3D = (load("res://models/ruins/echo_child.glb" if child else "res://models/ruins/echo_figure.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0] as AnimationPlayer
	material_value = ShaderMaterial.new()
	material_value.shader = load("res://shaders/echo.gdshader") as Shader
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material_value
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if animation != null:
		for key: StringName in animation.get_animation_list():
			var clip: Animation = animation.get_animation(key)
			clip.loop_mode = Animation.LOOP_LINEAR if String(key).get_slice("/", String(key).get_slice_count("/") - 1) in LOOPS else Animation.LOOP_NONE
	particles = GPUParticles3D.new()
	particles.amount = 12
	particles.use_fixed_seed = true
	particles.seed = 20261021
	particles.lifetime = 2.4
	particles.position.y = 0.8
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.25, 0.7, 0.2)
	process.direction = Vector3.UP
	process.gravity = Vector3(0, 0.1, 0)
	process.initial_velocity_min = 0.12
	process.initial_velocity_max = 0.32
	process.scale_min = 0.012
	process.scale_max = 0.03
	process.color = Color(1, 0.71, 0.33, 0.5)
	particles.process_material = process
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 6
	mesh.rings = 2
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1, 0.71, 0.33)
	mesh.material = glow
	particles.draw_pass_1 = mesh
	add_child(particles)


func set_pose(value: String, seek: float = -1) -> void:
	if animation == null:
		return
	var key: StringName = ""
	for candidate: StringName in animation.get_animation_list():
		if String(candidate).get_file() == value:
			key = candidate
			break
	if key.is_empty():
		return
	if pose != value:
		animation.play(key, 0.0 if seek >= 0 else BLEND)
		pose = value
	animation.speed_scale = 1.0 / 6.0 if value == "paint" else 1.0
	if seek >= 0:
		seek *= animation.speed_scale
		var length_value: float = animation.get_animation(key).length
		animation.seek(fposmod(seek, length_value) if value in LOOPS else minf(seek, length_value), true)
		animation.advance(0)


func presence(value: float, time: float) -> void:
	material_value.set_shader_parameter("presence", value)
	material_value.set_shader_parameter("phase", time)
	particles.emitting = value > 0.05


func add_bundle() -> void:
	bundle = (load("res://models/ruins/echo_bundle.glb") as PackedScene).instantiate() as Node3D
	bundle.position = Vector3(0, 1.2, 0.24)
	add_child(bundle)
	for node: Node in bundle.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material_value
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func add_lamp() -> void:
	if _skeleton == null:
		return
	var grip: BoneAttachment3D = BoneAttachment3D.new()
	_skeleton.add_child(grip)
	for index: int in _skeleton.get_bone_count():
		var bone_name: String = _skeleton.get_bone_name(index)
		if bone_name.replace("_", ".") == "Hand.R":
			grip.bone_name = bone_name
			break
	lamp = (load("res://models/sky_ladder/watcher_lamp.glb") as PackedScene).instantiate() as Node3D
	grip.add_child(lamp)
	lamp.top_level = true
	lamp.position.y = -0.35
	lamp.scale = Vector3.ONE * 0.6
	for node: Node in lamp.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(surface)
			mesh.set_surface_override_material(surface, RuinKit.material(2 if source.resource_name.to_lower().begins_with("glyph") else 1))
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func update_lamp(world_basis: Basis) -> void:
	if lamp == null:
		return
	var grip: BoneAttachment3D = lamp.get_parent() as BoneAttachment3D
	if grip.bone_idx < 0:
		return
	var hand: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(grip.bone_idx)
	# 提灯保持竖直，握点仍由手骨动画驱动，不随手腕翻成横躺。
	lamp.global_transform = Transform3D(world_basis.scaled(Vector3.ONE * 0.6), hand.origin - world_basis.y * 0.50)
