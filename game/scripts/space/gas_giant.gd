extends Node3D


func _ready() -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 90000.0
	sphere.height = 180000.0
	sphere.radial_segments = 128
	sphere.rings = 64
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/gas_giant.gdshader") as Shader
	var globe: MeshInstance3D = MeshInstance3D.new()
	globe.mesh = sphere
	globe.material_override = material
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(globe)
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for segment: int in 257:
		var angle: float = TAU * float(segment) / 256.0
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * 130000.0)
		vertices.append(direction * 220000.0)
		uvs.append(Vector2(0.0, float(segment) / 256.0))
		uvs.append(Vector2(1.0, float(segment) / 256.0))
		if segment < 256:
			var start: int = segment * 2
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ring_mesh: ArrayMesh = ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ring_material: ShaderMaterial = ShaderMaterial.new()
	ring_material.shader = load("res://shaders/ring.gdshader") as Shader
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ring_material
	ring.rotation_degrees.z = 18.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
