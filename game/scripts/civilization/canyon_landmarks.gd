class_name CanyonLandmarks
extends Node3D

const DETAIL_RANGE: float = 4500.0
var overlook: Vector3
var boardwalk_gap: Vector3
var _planet: Planet
var _forms: DawnLandforms


func build(planet: Planet) -> void:
	_planet = planet
	_forms = planet.noise.features.landforms
	var layouts: Array[Dictionary] = []
	for index: int in 4:
		var segment: int = index * 2 + 2
		var up: Vector3 = _forms.canyon[segment]
		var heading: Vector3 = up.direction_to(_forms.canyon[segment + 1]).slide(up).normalized()
		_place_rock("canyon_arch_" + str(index % 3), up, heading, 0.0)
	for index: int in 16:
		var up: Vector3 = _forms.canyon[6]
		var heading: Vector3 = up.direction_to(_forms.canyon[7]).slide(up).normalized()
		up = SurfaceSites.offset_direction(up, heading, (index % 4 - 1.5) * 85.0, planet.radius)
		up = SurfaceSites.offset_direction(up, heading.cross(up).normalized(), 260.0 + index / 4 * 65.0, planet.radius)
		_place_rock("canyon_pillar_" + str(index % 7), up, heading, index * 0.73)
	var center: Vector3 = _forms.canyon[6]
	var forward: Vector3 = center.direction_to(_forms.canyon[7]).slide(center).normalized()
	var side: Vector3 = forward.cross(center).normalized()
	var vista_center: Vector3 = center.slerp(_forms.canyon[7], 0.5).normalized()
	var vista_heading: Vector3 = center.direction_to(_forms.canyon[7]).slide(vista_center).normalized()
	var vista_side: Vector3 = vista_heading.cross(vista_center).normalized()
	overlook = SurfaceSites.offset_direction(vista_center, vista_side, 1310.0, planet.radius)
	var destination: Vector3 = vista_center * (planet.surface_radius(vista_center) + 12.0)
	for step: int in range(0, 140):
		var candidate: Vector3 = SurfaceSites.offset_direction(vista_center, vista_side, 1550.0 - step * 5.0, planet.radius)
		var ground: float = planet.noise.height(candidate)
		if ground - planet.noise.height(vista_center) < 600.0:
			continue
		var eye: Vector3 = candidate * (planet.radius + ground + 1.75)
		var clear: bool = true
		for distance: int in range(1, 41):
			var point: Vector3 = eye.lerp(destination, distance / eye.distance_to(destination))
			if point.length() < planet.surface_radius(point.normalized()) + 0.2:
				clear = false
				break
		if not clear:
			continue
		for sample: int in range(1, 100):
			var point: Vector3 = eye.lerp(destination, sample / 100.0)
			if point.length() < planet.surface_radius(point.normalized()) + 0.5:
				clear = false
				break
		if clear:
			overlook = candidate
			break
	var frame: Transform3D = anchor(overlook, -vista_side)
	for index: int in 3:
		layouts.append({"piece": "column", "transform": frame * Transform3D(Basis.IDENTITY, Vector3((index - 1) * 4.5, 0, 8.0 if index == 1 else 4.0)), "moss": 0.15, "sand": 0.4})
	layouts.append({"piece": "stele", "transform": frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 3)), "moss": 0.1, "sand": 0.4})
	var segment_length: float = center.angle_to(_forms.canyon[7]) * planet.radius
	for index: int in 167:
		var progress: float = (10.0 + index * 12.0) / segment_length
		var path: Vector3 = center.slerp(_forms.canyon[7], progress).normalized()
		var heading: Vector3 = center.direction_to(_forms.canyon[7]).slide(path).normalized()
		var up: Vector3 = SurfaceSites.offset_direction(path, heading.cross(path).normalized(), 850.0, planet.radius)
		if index == 83:
			boardwalk_gap = up
			continue
		# 桥段跨度沿局部 X；将其对准路线，而不是让四米桥宽沿路。
		var placement: Transform3D = anchor(up, -heading.cross(up).normalized())
		placement.origin -= up * 6.0
		layouts.append({"piece": "bridge_span", "transform": placement, "moss": 0.12, "sand": 0.4})
	var builder: RuinBuilder = RuinBuilder.new()
	add_child(builder)
	builder.build(layouts)
	for node: Node in builder.get_children():
		if node is MultiMeshInstance3D:
			(node as MultiMeshInstance3D).visibility_range_end = DETAIL_RANGE


func anchor(up: Vector3, forward: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(forward.slide(up).normalized(), up), up * _planet.surface_radius(up))


func _place_rock(piece: String, up: Vector3, forward: Vector3, turn: float) -> void:
	var scene: Node3D = (load("res://models/landforms/" + piece + ".glb") as PackedScene).instantiate() as Node3D
	scene.transform = anchor(up, forward.rotated(up, turn))
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.visibility_range_end = DETAIL_RANGE
		for surface: int in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(surface)
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = load("res://shaders/canyon_rock.gdshader") as Shader
			material.set_shader_parameter("grass_cap", source.resource_name.to_lower() == "cloth")
			mesh.set_surface_override_material(surface, material)
	add_child(scene)
