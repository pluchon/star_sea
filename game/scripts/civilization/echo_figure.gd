class_name EchoFigure
extends Node3D

const BLEND: float = 0.3 # 动作混合时间，秒。
const LOOPS: Array[String] = ["stand", "walk", "carry", "child_run", "old_walk"]
var animation: AnimationPlayer
var material_value: ShaderMaterial
var particles: GPUParticles3D
var pose: String = ""
var bundle: Node3D


func build(child: bool = false) -> void:
	var model: Node3D = (load("res://models/ruins/echo_child.glb" if child else "res://models/ruins/echo_figure.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
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
		animation.play(key, BLEND)
		pose = value
	if seek >= 0:
		var length_value: float = animation.get_animation(key).length
		animation.seek(fposmod(seek, length_value) if value in LOOPS else minf(seek, length_value), true)


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
