class_name PackagedAssetChecks
extends RefCounted


static func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []
	for path: String in ["res://models/ruins/geometry.json", "res://models/ship/ship_geometry.json", "res://models/landforms/geometry.json"]:
		if not FileAccess.file_exists(path):
			failures.append("打包缺少备用网格数据：" + path)
	if not failures.is_empty():
		return {"passed": false, "failures": failures}
	var pieces: int = 0
	for piece: String in RuinMeshes.recipes():
		var model: Mesh = RuinKit.mesh(piece)
		var procedural: Mesh = RuinKit.mesh(piece, true)
		if model == null or procedural == null or model.get_aabb().size.distance_to(procedural.get_aabb().size) > 0.005:
			failures.append("打包构件的模型与备用网格不一致：" + piece)
		pieces += 1
	var ship_triangles: Array[int] = []
	for use_model: bool in [true, false]:
		var ship: Node3D = ShipMeshes.build(use_model)
		tree.root.add_child(ship)
		# 经过实际渲染帧再释放，让新材质的依赖更新完成，覆盖正常场景生命周期。
		await RenderingServer.frame_post_draw
		var count: int = 0
		for node: Node in ship.find_children("*", "MeshInstance3D", true, false):
			count += (node as MeshInstance3D).mesh.get_faces().size() / 3
		ship_triangles.append(count)
		ship.queue_free()
		await tree.process_frame
	if ship_triangles[0] != ship_triangles[1] or ship_triangles[0] > 4000:
		failures.append("打包飞船的两条制作路线不一致或超出面数预算。")
	var world: HydrologyData = load(HydrologyData.PATH) as HydrologyData
	if world == null or world.river_points.is_empty() or world.lake_levels.is_empty():
		failures.append("打包缺少有效的全球水系。")
	var rocks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/landforms/geometry.json")) as Dictionary
	for piece: String in rocks:
		var scene: Node = (load("res://models/landforms/" + piece + ".glb") as PackedScene).instantiate()
		var instances: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		if instances.size() != 1:
			failures.append("打包峡谷岩石没有单一网格：" + piece)
		else:
			var mesh: Mesh = (instances[0] as MeshInstance3D).mesh
			var record: Dictionary = rocks[piece]
			if mesh.get_faces().size() / 3 != int(record["triangles"]) or mesh.get_aabb().size.distance_to(RuinMeshes.vector(record["bounds_size"])) > 0.01:
				failures.append("打包峡谷岩石与同源记录不一致：" + piece)
		scene.free()
	return {"passed": failures.is_empty(), "failures": failures, "ruin_pieces": pieces, "ship_triangles": ship_triangles, "hydrology_loaded": world != null, "canyon_models": rocks.size()}
