class_name ExplorerAvatar
extends Node3D

# 围巾由几段薄片组成，每帧按风、移动和重力重新摆放；不使用物理模拟。
const SCARF_SEGMENTS: int = 6
const SCARF_LENGTH: float = 0.13
const SCARF_ROOT: Vector3 = Vector3(0.08, 1.30, 0.22)

var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _body: Node3D
var _phase: float = 0.0
var _materials: Dictionary = {}
var _scarf: Array[Node3D] = []
var _scarf_flow: Vector3 = Vector3.ZERO
var _scarf_time: float = 0.0
var _director: SkyDirector


func _ready() -> void:
	for entry: Array in [["cloth", Color(0.72, 0.79, 0.67)], ["dark", Color(0.15, 0.25, 0.28)], ["light", Color(0.91, 0.86, 0.69)], ["accent", Color(0.74, 0.36, 0.19)], ["glass", Color(0.16, 0.40, 0.48)], ["scarf", Color(0.80, 0.30, 0.22)]]:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = load("res://shaders/explorer.gdshader") as Shader
		material.set_shader_parameter("pigment", entry[1])
		_materials[entry[0]] = material
	_body = Node3D.new()
	add_child(_body)
	_capsule(_body, Vector3(0, 1.07, 0), 0.23, 0.63, "cloth")
	_ring(_body, Vector3(0, 0.88, 0), 0.235, 0.10, "dark")
	_ellipsoid(_body, Vector3(0, 1.55, 0), Vector3(0.29, 0.29, 0.28), "light")
	_ellipsoid(_body, Vector3(0, 1.55, -0.239), Vector3(0.235, 0.16, 0.085), "dark")
	_ellipsoid(_body, Vector3(0, 1.57, -0.29), Vector3(0.195, 0.115, 0.045), "glass")
	_ellipsoid(_body, Vector3(-0.08, 1.61, -0.326), Vector3(0.075, 0.015, 0.009), "light")
	for side: float in [-1.0, 1.0]:
		_ellipsoid(_body, Vector3(side * 0.28, 1.54, 0), Vector3(0.045, 0.095, 0.095), "accent")
		var arm: Node3D = Node3D.new()
		arm.position = Vector3(side * 0.29, 1.27, 0)
		_body.add_child(arm)
		_arms.append(arm)
		_capsule(arm, Vector3(0, -0.18, 0), 0.085, 0.37, "cloth")
		_capsule(arm, Vector3(0, -0.36, -0.025), 0.09, 0.19, "dark")
		_capsule(arm, Vector3(0, -0.46, -0.03), 0.085, 0.17, "light")
		var leg: Node3D = Node3D.new()
		leg.position = Vector3(side * 0.13, 0.82, 0)
		add_child(leg)
		_legs.append(leg)
		_capsule(leg, Vector3(0, -0.24, 0), 0.10, 0.47, "cloth")
		_ellipsoid(leg, Vector3(0, -0.37, -0.08), Vector3(0.095, 0.13, 0.04), "accent")
		_capsule(leg, Vector3(0, -0.58, 0), 0.095, 0.36, "dark")
		_ellipsoid(leg, Vector3(0, -0.72, -0.065), Vector3(0.12, 0.105, 0.21), "dark")
		_ellipsoid(leg, Vector3(0, -0.78, -0.065), Vector3(0.125, 0.035, 0.215), "light")
		_capsule(_body, Vector3(side * 0.16, 1.16, 0.19), 0.035, 0.42, "accent")
	_capsule(_body, Vector3(0, 1.10, 0.26), 0.18, 0.49, "dark")
	_capsule(_body, Vector3(0, 1.13, 0.37), 0.13, 0.36, "cloth")
	_ring(_body, Vector3(0, 1.36, 0), 0.17, 0.09, "accent")
	_capsule(_body, Vector3(0.06, 1.12, -0.21), 0.04, 0.16, "accent")
	_ring(_body, Vector3(0, 1.30, 0), 0.21, 0.09, "scarf")
	for index: int in SCARF_SEGMENTS:
		var segment: Node3D = Node3D.new()
		_body.add_child(segment)
		_scarf.append(segment)
		var piece: BoxMesh = BoxMesh.new()
		# 越往末端越窄，末段略短，轮廓更像布条而不是木板。
		piece.size = Vector3(lerpf(0.17, 0.12, float(index) / SCARF_SEGMENTS), SCARF_LENGTH * 1.1, 0.024)
		_part(segment, piece, Vector3(0, -SCARF_LENGTH * 0.5, 0), Vector3.ONE, "scarf")
	_pose_scarf(0.0, Vector3.ZERO)


func _capsule(parent: Node3D, location: Vector3, radius_value: float, height: float, pigment: String) -> void:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius_value
	mesh.height = maxf(height, radius_value * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	_part(parent, mesh, location, Vector3.ONE, pigment)


func _ring(parent: Node3D, location: Vector3, radius_value: float, height: float, pigment: String) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius_value
	mesh.bottom_radius = radius_value
	mesh.height = height
	mesh.radial_segments = 16
	_part(parent, mesh, location, Vector3.ONE, pigment)


func _ellipsoid(parent: Node3D, location: Vector3, size: Vector3, pigment: String) -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	_part(parent, mesh, location, size, pigment)


func _part(parent: Node3D, mesh: Mesh, location: Vector3, size: Vector3, pigment: String) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = location
	visual.scale = size
	visual.material_override = _materials[pigment]
	parent.add_child(visual)


func animate(delta: float, local_velocity: Vector3, flying: bool, grounded: bool) -> void:
	var speed: float = Vector2(local_velocity.x, local_velocity.z).length()
	_phase += delta * minf(speed, 8.0) * 2.7
	var swing: float = sin(_phase) * minf(speed / 4.0, 1.3) * 0.48 if grounded and not flying else 0.0
	_body.position.y = absf(sin(_phase)) * minf(speed / 4.0, 1.0) * 0.025 if grounded and not flying else 0.0
	for index: int in 2:
		var side: float = -1.0 if index == 0 else 1.0
		_arms[index].rotation = Vector3(swing * side - (0.22 if flying else 0.06), 0, side * (0.28 if flying else 0.08))
		_legs[index].rotation.x = -swing * side + (0.16 if flying or not grounded else 0.0)
	_pose_scarf(delta, local_velocity)


func _pose_scarf(delta: float, local_velocity: Vector3) -> void:
	if _director == null and is_inside_tree():
		_director = get_tree().get_first_node_in_group("sky_director") as SkyDirector
	var wind: Vector3 = Vector3.ZERO
	if _director != null:
		wind = global_basis.inverse() * _director.wind_direction * _director.wind_strength
	# 迎面气流把围巾吹向身后；高速飞行时限制幅度，避免拉成一条直线。
	var target: Vector3 = (wind * 1.3 - local_velocity * 0.22).limit_length(2.4)
	_scarf_flow = _scarf_flow.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	_scarf_time += delta
	var strength: float = minf(_scarf_flow.length(), 1.0)
	var point: Vector3 = SCARF_ROOT
	for index: int in SCARF_SEGMENTS:
		var along: float = float(index + 1) / SCARF_SEGMENTS
		# 无风时贴着背包向下垂；越靠末端越容易被风带起，并有沿布条传递的波动。
		var direction: Vector3 = (Vector3(0.0, -1.0, 0.9) + _scarf_flow * (0.6 + along * 1.2)).normalized()
		var flutter: float = sin(_scarf_time * 7.5 - index * 0.85) * 0.32 * strength * along
		direction = direction.rotated(Vector3.RIGHT, flutter).rotated(Vector3.UP, flutter * 0.5)
		var next: Vector3 = point + direction * SCARF_LENGTH
		# 背包占据身后约 0.86 到 1.35 米的高度，顶部较薄；布条被推到背包外侧。
		var clearance: float = 0.52 if next.y < 1.29 else 0.38
		if next.y > 0.86 and next.y < 1.35 and next.z < clearance:
			next.z = clearance
			direction = (next - point).normalized()
			next = point + direction * SCARF_LENGTH
		var segment: Node3D = _scarf[index]
		segment.position = point
		var x_axis: Vector3 = Vector3.RIGHT - direction * direction.x
		if x_axis.length_squared() < 0.0001:
			x_axis = Vector3.FORWARD
		x_axis = x_axis.normalized()
		segment.basis = Basis(x_axis, -direction, x_axis.cross(-direction))
		point = next
