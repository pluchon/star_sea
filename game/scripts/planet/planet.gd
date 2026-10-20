class_name Planet
extends Node3D

@export var planet_seed: int = 20261019
@export var radius: float = 40000.0
@export var atmosphere_height: float = 8000.0
@export var gravity: float = 9.8
@export var planet_name: String = "晨"
@export_enum("草原海岸", "赤色沙丘", "冰蓝高地") var profile: int = 0

var noise: TerrainNoise
var site: Dictionary
var atmosphere_material: ShaderMaterial


func _enter_tree() -> void:
	# 子节点的 _ready 先于父节点执行，噪声必须在子节点进入场景前就绪。
	noise = TerrainNoise.new(planet_seed, radius, profile)
	if profile == 0:
		# 出发地按基础地形选定，与样板区特征使用同一个位置。
		site = noise.features.site
	else:
		site = SurfaceSites.find_inland(noise)
	assert(not site.is_empty(), "固定种子下没有找到符合地形约束的观景位置。")
	add_to_group("planets")


func _ready() -> void:
	atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = load("res://shaders/atmosphere.gdshader") as Shader
	# 透明海面和光环先绘制，大气最后覆盖，避免水面绕过大气淡化。
	atmosphere_material.render_priority = 1
	atmosphere_material.set_shader_parameter("planet_center", global_position)
	atmosphere_material.set_shader_parameter("planet_radius", radius)
	atmosphere_material.set_shader_parameter("atmo_radius", radius + atmosphere_height)
	if profile == 1:
		atmosphere_material.set_shader_parameter("day_color", Color(0.77, 0.53, 0.39))
		atmosphere_material.set_shader_parameter("sunset_color", Color(0.95, 0.37, 0.25))
		atmosphere_material.set_shader_parameter("density", 0.8)
	elif profile == 2:
		atmosphere_material.set_shader_parameter("day_color", Color(0.49, 0.68, 0.83))
		atmosphere_material.set_shader_parameter("sunset_color", Color(0.73, 0.55, 0.81))
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius + atmosphere_height
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "Atmosphere"
	shell.mesh = sphere
	shell.material_override = atmosphere_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	if noise.features != null:
		var waters: InlandWaters = InlandWaters.new()
		waters.name = "InlandWaters"
		add_child(waters)
		waters.build(noise.features)
	var details: SurfaceDetails = SurfaceDetails.new()
	details.name = "SurfaceDetails"
	add_child(details)


func surface_radius(direction: Vector3) -> float:
	return radius + maxf(noise.height(direction), 0.0)


static func nearest(tree: SceneTree, position_world: Vector3) -> Planet:
	var result: Planet
	var minimum: float = INF
	for node: Node in tree.get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var distance: float = planet.global_position.distance_to(position_world) - planet.radius
		if distance < minimum:
			minimum = distance
			result = planet
	return result
