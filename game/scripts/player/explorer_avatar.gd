class_name ExplorerAvatar
extends Node3D

var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _body: Node3D
var _phase: float = 0.0
var _materials: Dictionary = {}


func _ready() -> void:
	for entry: Array in [["cloth", Color(0.72, 0.79, 0.67)], ["dark", Color(0.15, 0.25, 0.28)], ["light", Color(0.91, 0.86, 0.69)], ["accent", Color(0.74, 0.36, 0.19)], ["glass", Color(0.16, 0.40, 0.48)]]:
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
