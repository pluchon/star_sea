class_name RuinKit
extends RefCounted

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _collisions: Dictionary = {}


static func mesh(piece: String, procedural: bool = false) -> Mesh:
	var key: String = piece + ("/procedural" if procedural else "/model")
	if _meshes.has(key):
		return _meshes[key]
	var path: String = "res://models/ruins/" + piece + ".glb"
	var result: Mesh
	if not procedural and ResourceLoader.exists(path):
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var instances: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			instances.push_front(scene)
		if instances.size() > 1:
			result = _combined_mesh(scene, instances)
		elif not instances.is_empty():
			result = (instances[0] as MeshInstance3D).mesh.duplicate() as Mesh
			for index: int in result.get_surface_count():
				var original: Material = result.surface_get_material(index)
				var kind: int = RuinMeshes.KINDS.find(original.resource_name.to_lower())
				(result as ArrayMesh).surface_set_material(index, material(maxi(kind, 0)))
		scene.free()
	if result == null:
		result = RuinMeshes.mesh(piece)
	_meshes[key] = result
	return result


static func _combined_mesh(scene: Node3D, instances: Array[Node]) -> ArrayMesh:
	var result: ArrayMesh = ArrayMesh.new()
	for kind: int in 4:
		var builder: SurfaceTool = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var populated: bool = false
		for node: Node in instances:
			var instance: MeshInstance3D = node as MeshInstance3D
			var transform_value: Transform3D = instance.transform
			var parent: Node = instance.get_parent()
			while parent != null and parent != scene:
				if parent is Node3D:
					transform_value = (parent as Node3D).transform * transform_value
				parent = parent.get_parent()
			for surface: int in instance.mesh.get_surface_count():
				var source: Material = instance.mesh.surface_get_material(surface)
				if RuinMeshes.KINDS.find(source.resource_name.to_lower()) == kind:
					builder.append_from(instance.mesh, surface, transform_value)
					populated = true
		if populated:
			builder.set_material(material(kind))
			builder.commit(result)
	return result


static func material(kind: int, batched: bool = false) -> ShaderMaterial:
	var key: int = kind + (4 if batched else 0)
	if not _materials.has(key):
		var result: ShaderMaterial = ShaderMaterial.new()
		result.shader = load("res://shaders/ruin_solid.gdshader" if kind in [0, 1] else "res://shaders/ruin.gdshader") as Shader
		result.set_shader_parameter("kind", kind)
		result.set_shader_parameter("batched", batched)
		result.set_shader_parameter("stone_texture", load("res://textures/painted/stone.svg"))
		_materials[key] = result
	return _materials[key]


static func collision_records(piece: String) -> Array[Dictionary]:
	if not _collisions.has(piece):
		_collisions[piece] = RuinMeshes.collision_records(piece)
	return _collisions[piece]


static func collision(piece: String) -> Array[Shape3D]:
	var result: Array[Shape3D] = []
	for record: Dictionary in collision_records(piece):
		result.append(record["shape"])
	return result
