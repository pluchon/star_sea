class_name AssetModelChecks
extends RefCounted

const SNAP: float = 0.0001 # 合并导出时按法线、材质拆开的同位置顶点。


static func run() -> Dictionary:
	var files: PackedStringArray = []
	_collect("res://models", files)
	var reports: Array[Dictionary] = []
	var failed: int = 0
	# 野外石头没有 glb；必须检查实际运行时网格及各个细节层级。
	var stone: ArrayMesh = SurfaceDetails.mesh_for_kind("stone")
	var stone_arrays: Array = stone.surface_get_arrays(0)
	var ranges: Array = [stone_arrays[Mesh.ARRAY_INDEX]]
	var start: int = int(stone.get_meta("triangles")) * 3
	for triangles: int in stone.get_meta("lod_triangles"):
		var indices: PackedInt32Array = []
		for index: int in range(start, start + triangles * 3):
			indices.append(index)
		ranges.append(indices)
		start += triangles * 3
	for level: int in ranges.size():
		var arrays: Array = stone_arrays.duplicate()
		arrays[Mesh.ARRAY_INDEX] = ranges[level]
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var report: Dictionary = inspect(mesh, "runtime://surface/stone", "LOD%d" % level)
		reports.append(report)
		failed += int(not report["passed"])
	for path: String in files:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			reports.append({"file": path, "passed": false, "error": "模型无法导入"})
			failed += 1
			continue
		var scene: Node = packed.instantiate()
		var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			meshes.push_front(scene)
		for node: Node in meshes:
			var instance: MeshInstance3D = node as MeshInstance3D
			var report: Dictionary = inspect(instance.mesh, path, str(node.name))
			reports.append(report)
			if not report["passed"]:
				failed += 1
		scene.free()
	return {"passed": failed == 0 and not reports.is_empty(), "files": files.size(), "meshes": reports.size(), "failed_meshes": failed, "results": reports, "winding": "Godot clockwise, outward signed volume = -sum(a dot (b cross c))/6", "centroid_test": "逐面质心方向同时记录；凹面可能朝向整体质心，不能单独据此反转法线"}


static func _collect(directory: String, files: PackedStringArray) -> void:
	for child: String in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(child), files)
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() in ["glb", "gltf"]:
			files.append(directory.path_join(file))


static func inspect(mesh: Mesh, path: String, label: String) -> Dictionary:
	var failures: Array[String] = []
	var edges: Dictionary = {}
	var triangles: PackedVector3Array = mesh.get_faces()
	var volume: float = 0
	var degenerate: int = 0
	var reversed_normals: int = 0
	var inward_centroid: int = 0
	var missing_colors: bool = false
	var center: Vector3 = mesh.get_aabb().get_center()
	var closed: bool = _closed_kind(path + "/" + label)
	var parents: Array[int] = []
	var volumes: Array[float] = []
	for triangle: int in triangles.size() / 3:
		parents.append(triangle)
	for index: int in range(0, triangles.size(), 3):
		var a: Vector3 = triangles[index]
		var b: Vector3 = triangles[index + 1]
		var c: Vector3 = triangles[index + 2]
		var normal: Vector3 = -(b - a).cross(c - a)
		if normal.length_squared() < 0.0000000001:
			degenerate += 1
		var part_volume: float = -a.dot(b.cross(c)) / 6
		volume += part_volume
		volumes.append(part_volume)
		if normal.dot((a + b + c) / 3 - center) < -0.00001:
			inward_centroid += 1
		for corner: int in 3:
			var first: Vector3 = triangles[index + corner].snapped(Vector3.ONE * SNAP)
			var last: Vector3 = triangles[index + (corner + 1) % 3].snapped(Vector3.ONE * SNAP)
			var key: String = str(first) + "/" + str(last) if first < last else str(last) + "/" + str(first)
			if not edges.has(key):
				edges[key] = {"count": 0, "orientation": 0, "triangle": index / 3}
			var edge: Dictionary = edges[key]
			edge["count"] += 1
			edge["orientation"] += 1 if first < last else -1
			parents[_root(parents, index / 3)] = _root(parents, edge["triangle"])
	var open_edges: int = 0
	var nonmanifold: int = 0
	var inconsistent_edges: int = 0
	for edge: Dictionary in edges.values():
		var count: int = edge["count"]
		open_edges += int(count == 1)
		nonmanifold += int(count > 2)
		inconsistent_edges += int(count == 2 and edge["orientation"] != 0)
	var components: Dictionary = {}
	for triangle: int in volumes.size():
		var component: int = _root(parents, triangle)
		components[component] = float(components.get(component, 0)) + volumes[triangle]
	var inward_components: int = 0
	for value: float in components.values():
		inward_components += int(value <= 0.00000001)
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		missing_colors = missing_colors or colors.size() != vertices.size()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for index: int in range(0, count, 3):
			var ids: Array = [indices[index], indices[index + 1], indices[index + 2]] if not indices.is_empty() else [index, index + 1, index + 2]
			var geometric: Vector3 = -(vertices[ids[1]] - vertices[ids[0]]).cross(vertices[ids[2]] - vertices[ids[0]])
			if normals.size() != vertices.size() or geometric.dot(normals[ids[0]] + normals[ids[1]] + normals[ids[2]]) < -0.00001:
				reversed_normals += 1
	var budget: int = _budget(path, mesh.get_aabb().size.length())
	if closed and open_edges > 0:
		failures.append("封闭物体存在开放边")
	if closed and volume <= 0:
		failures.append("封闭物体有符号体积非正")
	if closed and inward_components > 0:
		failures.append("封闭物体含体积非正的独立部分")
	if nonmanifold > 0:
		failures.append("非流形边或重复面")
	if inconsistent_edges > 0:
		failures.append("共边三角形朝向不一致")
	if reversed_normals > 0:
		failures.append("顶点法线与三角形外法线不一致")
	if degenerate > 0:
		failures.append("退化三角形")
	if missing_colors:
		failures.append("缺少环境遮蔽和边缘磨损顶点色")
	if triangles.size() / 3 > budget:
		failures.append("面数超过分类预算")
	return {"file": path, "mesh": label, "passed": failures.is_empty(), "failures": failures, "closed_required": closed, "open_edges": open_edges, "nonmanifold_edges": nonmanifold, "inconsistent_edge_winding": inconsistent_edges, "signed_volume": volume, "component_signed_volumes": components.values(), "inward_centroid_faces": inward_centroid, "reversed_normals": reversed_normals, "degenerate": degenerate, "triangles": triangles.size() / 3, "budget": budget, "vertex_colors": not missing_colors}


static func _root(parents: Array[int], index: int) -> int:
	var at: int = index
	while parents[at] != at:
		parents[at] = parents[parents[at]]
		at = parents[at]
	return at


static func _closed_kind(label: String) -> bool:
	for token: String in ["stone", "rock", "wall", "column", "statue", "rubble", "slab", "step", "arch", "pillar"]:
		if label.to_lower().contains(token):
			return true
	return false


static func _budget(path: String, size: float) -> int:
	if path.contains("statue"):
		return 5000
	if path.contains("explorer") or path.contains("echo"):
		return 3000
	if path.contains("rubble"):
		return 900
	if path.contains("vine"):
		return 3000
	return 300 if size < 2 else (1800 if size < 8 else 4000)
