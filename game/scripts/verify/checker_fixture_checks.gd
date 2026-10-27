extends SceneTree


func _initialize() -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	var arrays: Array = box.surface_get_arrays(0)
	var colors: PackedColorArray = []
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(Color(0.8, 0, 0.5, 1))
	arrays[Mesh.ARRAY_COLOR] = colors
	var closed: ArrayMesh = ArrayMesh.new()
	closed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var good: Dictionary = AssetModelChecks.inspect(closed, "fixture://stone", "closed_cube")
	var missing_arrays: Array = arrays.duplicate(true)
	missing_arrays[Mesh.ARRAY_INDEX] = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).slice(3)
	var missing: ArrayMesh = ArrayMesh.new()
	missing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, missing_arrays)
	var hole: Dictionary = AssetModelChecks.inspect(missing, "fixture://stone", "missing_triangle")
	var reversed_arrays: Array = arrays.duplicate(true)
	var indices: PackedInt32Array = reversed_arrays[Mesh.ARRAY_INDEX]
	for index: int in range(0, indices.size(), 3):
		var value: int = indices[index]
		indices[index] = indices[index + 2]
		indices[index + 2] = value
	reversed_arrays[Mesh.ARRAY_INDEX] = indices
	var reversed_mesh: ArrayMesh = ArrayMesh.new()
	reversed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, reversed_arrays)
	var inverted: Dictionary = AssetModelChecks.inspect(reversed_mesh, "fixture://stone", "inverted_cube")
	var mixed_arrays: Array = reversed_arrays.duplicate(true)
	var mixed_vertices: PackedVector3Array = mixed_arrays[Mesh.ARRAY_VERTEX]
	var mixed_normals: PackedVector3Array = mixed_arrays[Mesh.ARRAY_NORMAL]
	for index: int in mixed_vertices.size():
		mixed_vertices[index] = mixed_vertices[index] * 0.5 + Vector3.RIGHT * 2
		mixed_normals[index] = -mixed_normals[index]
	mixed_arrays[Mesh.ARRAY_VERTEX] = mixed_vertices
	mixed_arrays[Mesh.ARRAY_NORMAL] = mixed_normals
	var mixed_mesh: ArrayMesh = ArrayMesh.new()
	mixed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mixed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mixed_arrays)
	var mixed: Dictionary = AssetModelChecks.inspect(mixed_mesh, "fixture://stone", "one_inverted_component")
	var passed: bool = good["passed"] and int(hole["open_edges"]) == 3 and not hole["passed"] and float(inverted["signed_volume"]) < 0 and int(inverted["reversed_normals"]) == 12 and not inverted["passed"]
	passed = passed and not mixed["passed"] and float(mixed["signed_volume"]) > 0 and int(mixed["reversed_normals"]) == 0
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(2, 0.4, 2)
	var floor_a: Dictionary = {"mesh": floor_mesh, "transform": Transform3D.IDENTITY}
	var floor_b: Dictionary = {"mesh": floor_mesh, "transform": Transform3D(Basis.IDENTITY, Vector3(1.7, 0, 0))}
	var overlap: float = PlacementChecks._surface_overlap(floor_a, floor_b)
	floor_b["transform"] = Transform3D(Basis.IDENTITY, Vector3(2.2, 0, 0))
	var separate: float = PlacementChecks._surface_overlap(floor_a, floor_b)
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 2
	ring_mesh.outer_radius = 3
	var ring: Dictionary = {"mesh": ring_mesh, "transform": Transform3D.IDENTITY}
	var ring_hole: float = PlacementChecks._surface_overlap(ring, floor_a)
	passed = passed and overlap > 0.05 and separate == 0 and ring_hole == 0
	var report: Dictionary = {"passed": passed, "closed_cube": good, "missing_triangle": hole, "inverted_cube": inverted, "mixed_components": mixed, "placement_calibration": {"overlapping_slabs_width_m": overlap, "separate_slabs_width_m": separate, "slab_inside_ring_hole_width_m": ring_hole}}
	VerificationMetrics.write_json("res://../test-output/version/checker-fixtures.json", report)
	print(JSON.stringify(report))
	quit(0 if passed else 1)
