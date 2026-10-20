class_name ShipMeshes
extends RefCounted

const COLORS: Dictionary = {"hull": Color("e9e4d8"), "panel": Color("3b4148"), "stripe": Color("c9503c"), "glass": Color("47b8c6"), "engine": Color("ffb867")}


static func build(use_model: bool = true) -> Node3D:
	var result: Node3D
	if use_model and ResourceLoader.exists("res://models/ship/ship.glb"):
		result = (load("res://models/ship/ship.glb") as PackedScene).instantiate() as Node3D
		for node: Node in result.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = node as MeshInstance3D
			for index: int in instance.mesh.get_surface_count():
				var original: Material = instance.mesh.surface_get_material(index)
				instance.set_surface_override_material(index, material(original.resource_name.to_lower()))
		return result
	result = Node3D.new()
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string("res://models/ship/ship_geometry.json")) as Array
	for record: Dictionary in records:
		var builder: SurfaceTool = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points: Array = record["vertices"]
		for start: int in range(0, points.size(), 3):
			for corner: int in [2, 1, 0]:
				var raw: Array = points[start + corner]
				builder.add_vertex(Vector3(raw[0], raw[1], raw[2]))
		builder.generate_normals()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = record["name"]
		instance.mesh = builder.commit()
		instance.material_override = material(record["material"])
		result.add_child(instance)
	return result


static func material(kind: String) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = COLORS.get(kind, COLORS["hull"])
	result.roughness = 0.8
	if kind == "engine":
		result.emission_enabled = true
		result.emission = COLORS["engine"]
		result.emission_energy_multiplier = 1.4
	return result
