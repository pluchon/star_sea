class_name UpdraftVisuals
extends MultiMeshInstance3D

const PARTICLES: int = 96
var _time: float = 0.0


func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var leaf: QuadMesh = QuadMesh.new()
	leaf.size = Vector2(0.045, 0.08)
	multimesh.mesh = leaf
	multimesh.instance_count = PARTICLES
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.77, 0.74, 0.48)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))


func _process(delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: StarSeaPlayer = scene.get_node_or_null("Player") as StarSeaPlayer
	if player == null:
		return
	var planet: Planet = get_parent() as Planet
	var local: Vector3 = planet.to_local(player.global_position)
	var up: Vector3 = local.normalized()
	var exposed: bool = player.mode == StarSeaPlayer.Mode.GLIDE or (player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor())
	visible = exposed and player.current_planet() == planet and planet.noise.features.updraft_at(up, player.altitude) > 0.1
	if not visible:
		return
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	if not director.time_paused:
		_time += delta
	position = local
	basis = Basis.looking_at(SurfaceSites.tangent_forward(up), up)
	for index: int in PARTICLES:
		var phase: float = fposmod(_time * 0.25 + index * 0.6180339, 1.0)
		var angle: float = index * 2.39996 + phase * 0.5
		var radius: float = 2.0 + fposmod(index * 0.732, 1.0) * 12.0
		multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.FORWARD, angle), Vector3(cos(angle) * radius, phase * 18.0 - 2.0, sin(angle) * radius)))
