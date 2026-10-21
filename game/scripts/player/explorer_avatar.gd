class_name ExplorerAvatar
extends Node3D

const MODEL: String = "res://models/explorer/explorer.glb"
const SCARF_SEGMENTS: int = 7
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _model: Node3D
var _wing: MeshInstance3D
var _scarf_cloth: MeshInstance3D
var _edges: Node3D
var _wing_materials: Array[ShaderMaterial] = []
var _state: String = "locomotion"
var _time: float = 0.0
var _wing_visibility: float = 0.0
var _first_person: bool = false


func _ready() -> void:
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_materials(_model)
	_wing = _model.find_child("SoftWing", true, false) as MeshInstance3D
	_scarf_cloth = _model.find_child("ScarfCloth", true, false) as MeshInstance3D
	var machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	var locomotion: AnimationNodeBlendSpace1D = AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 8.0
	for entry: Array in [["idle", 0.0], ["walk", 4.0], ["run", 8.0]]:
		var animation: AnimationNodeAnimation = AnimationNodeAnimation.new()
		animation.animation = entry[0]
		locomotion.add_blend_point(animation, entry[1], -1, entry[0])
	machine.add_node("locomotion", locomotion)
	var states: Array[String] = ["locomotion", "jump", "fall", "land_stumble", "glide", "climb", "climb_rope", "mantle"]
	for state: String in states:
		if state == "locomotion":
			continue
		var animation: AnimationNodeAnimation = AnimationNodeAnimation.new()
		animation.animation = state
		machine.add_node(state, animation)
	for from_state: String in states:
		for to_state: String in states:
			if from_state == to_state:
				continue
			var transition: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.3 if to_state == "glide" else (0.25 if from_state == "glide" else 0.12)
			machine.add_transition(from_state, to_state, transition)
	for name: StringName in animation_player.get_animation_list():
		if String(name) in ["idle", "walk", "run", "glide", "climb", "climb_rope"]:
			animation_player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	animation_tree = AnimationTree.new()
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.root_node = animation_tree.get_path_to(animation_player.get_node(animation_player.root_node))
	animation_tree.tree_root = machine
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_playback.start("locomotion")
	animation_tree.advance(0.001)
	_wing.visible = false


func _materials(model: Node3D, edge_only: bool = false) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if edge_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface: int in mesh.mesh.get_surface_count():
			var material: ShaderMaterial = ShaderMaterial.new()
			if mesh.name == "SoftWing":
				material.shader = load("res://shaders/glider.gdshader") as Shader
				material.set_shader_parameter("edges_only", edge_only)
				_wing_materials.append(material)
			else:
				var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				material.shader = load("res://shaders/explorer.gdshader") as Shader
				material.set_shader_parameter("pigment", source.albedo_color)
			mesh.set_surface_override_material(surface, material)
		if edge_only:
			mesh.visible = mesh.name == "SoftWing"


func attach_edges(camera: Camera3D) -> void:
	_edges = (load(MODEL) as PackedScene).instantiate() as Node3D
	_edges.name = "GliderEdges"
	camera.add_child(_edges)
	_edges.position = Vector3(0, -1.5, -0.25)
	_edges.rotation.y = PI
	_materials(_edges, true)
	var player: AnimationPlayer = _edges.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play("glide")
	player.seek(0.0, true)
	player.pause()
	_edges.visible = false


func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if _edges != null:
		_edges.visible = enabled and _wing_visibility > 0.01


func hide_glider() -> void:
	_wing_visibility = 0.0
	_wing.visible = false
	if _edges != null:
		_edges.visible = false
	_state = "locomotion"
	_playback.start(_state)
	animation_tree.advance(0.001)


func animate(delta: float, local_velocity: Vector3, flying: bool, grounded: bool, mode: int = 0, rope: bool = false, stumbling: bool = false, mantling: bool = false) -> void:
	var director: SkyDirector = get_tree().get_first_node_in_group("sky_director") as SkyDirector
	var paused: bool = director != null and director.time_paused
	var speed: float = Vector2(local_velocity.x, local_velocity.z).length()
	var wanted: String = "locomotion"
	if mode == 3:
		wanted = "glide"
	elif mode == 2:
		wanted = "mantle" if mantling else ("climb_rope" if rope else "climb")
	elif stumbling:
		wanted = "land_stumble"
	elif not grounded or flying:
		wanted = "jump" if local_velocity.y > 0.1 else "fall"
	if wanted != _state:
		if paused:
			_playback.start(wanted)
		else:
			_playback.travel(wanted)
		_state = wanted
	animation_tree.set("parameters/locomotion/blend_position", speed)
	if not paused:
		_time += delta
		animation_tree.advance(delta)
	else:
		animation_tree.advance(0.0)
	_wing_visibility = (1.0 if mode == 3 else 0.0) if paused else move_toward(_wing_visibility, 1.0 if mode == 3 else 0.0, delta / (0.3 if mode == 3 else 0.25))
	_wing.visible = _wing_visibility > 0.01
	_scarf_cloth.visible = mode != 3
	if _edges != null:
		_edges.visible = _first_person and _wing_visibility > 0.01
	for material: ShaderMaterial in _wing_materials:
		material.set_shader_parameter("cloth_time", _time)
	var wind: Vector3 = global_basis.inverse() * director.wind_direction * director.wind_strength if director != null else Vector3.ZERO
	for index: int in SCARF_SEGMENTS:
		var bone: int = skeleton.find_bone("Scarf" + str(index))
		var swing: float = sin(_time * 2.6 - index * 0.45) * 0.05 * (1.0 + wind.length())
		var pitch: float = (-0.65 if index == 0 else -0.025) + minf(speed, 9.0) * 0.045 / (index + 1.0)
		skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, pitch + swing) * Quaternion(Vector3.FORWARD, wind.x * 0.035))
