extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var scene: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var details: SurfaceDetails = planet.get_node("SurfaceDetails") as SurfaceDetails
	var director: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	player.controls_enabled = false
	director.time_paused = true
	var deadline: int = Time.get_ticks_msec() + 120000
	while not details.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("植被运行检查等待分块超时。")
			quit(1)
			return
	var spawn_probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var probe_shape: SphereShape3D = SphereShape3D.new()
	probe_shape.radius = 0.7
	spawn_probe.shape = probe_shape
	spawn_probe.transform = Transform3D(Basis.IDENTITY, player.global_position + player.global_basis.y * 0.9)
	spawn_probe.collision_mask = 2
	var spawn_clear: bool = scene.get_world_3d().direct_space_state.intersect_shape(spawn_probe).is_empty()
	if not spawn_clear:
		_failures.append("出生点与植物或石块碰撞重叠。")
	var initial: Dictionary = _fingerprint(details)
	var original_local: Vector3 = player.global_position - planet.global_position
	var up: Vector3 = original_local.normalized()
	player.global_position += up * 5000.0
	(scene.get_node("FloatingOrigin") as FloatingOrigin)._physics_process(1.0 / 60.0)
	await process_frame
	player.place_at(planet.global_position + original_local, planet.site["forward"], up)
	for frame: int in 10:
		await process_frame
	if initial != _fingerprint(details):
		_failures.append("原点平移和返回后，已有植被变换改变。")
	# 在实际加载的树木旁检查物理，不以生成器返回变换代替碰撞验证。
	var nearest_tree: Vector3 = Vector3.INF
	var nearest_distance: float = INF
	for tile: Node3D in details._tiles.values():
		for transform: Transform3D in tile.get_meta("trunks"):
			var position_local: Vector3 = tile.position + transform.origin
			var distance: float = position_local.distance_to(original_local)
			if distance < nearest_distance:
				nearest_tree = position_local
				nearest_distance = distance
	if nearest_distance == INF:
		_failures.append("运行场景没有生成树木。")
	else:
		up = nearest_tree.normalized()
		var tangent: Vector3 = SurfaceSites.tangent_forward(up)
		player.place_at(planet.global_position + nearest_tree + tangent * 4.0 + up, tangent, up)
		details._refresh_colliders(nearest_tree)
		await physics_frame
		await physics_frame
	var collision_counts: Dictionary = {"tree": 0, "stone": 0}
	var tree_motion_blocked: bool = false
	for body: StaticBody3D in details._colliders.values():
		var kind: String = body.get_meta("ecology_kind")
		var collider: CollisionShape3D = body.get_child(0) as CollisionShape3D
		var center: Vector3 = collider.global_position
		if kind == "stone":
			center += body.global_basis.y * 0.3
		var side: Vector3 = body.global_basis.x.normalized()
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(center + side * 6.0, center - side * 6.0, 2)
		var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			_failures.append(kind + "的实体碰撞射线未命中。")
		else:
			collision_counts[kind] += 1
		if kind == "tree" and not tree_motion_blocked:
			player.global_position = body.global_position + side * 3.0 + body.global_basis.y * 2.0
			player.collision_mask = 2
			tree_motion_blocked = player.test_move(player.global_transform, -side * 6.0)
			player.collision_mask = 3
	if collision_counts["tree"] == 0 or collision_counts["stone"] == 0 or not tree_motion_blocked:
		_failures.append("树木、石块或角色阻挡检查不完整。")
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "tiles_checked": initial.size(), "spawn_clear": spawn_clear, "collision_ray_hits": collision_counts, "character_blocked_by_trunk": tree_motion_blocked, "floating_origin_preserved_instances": initial == _fingerprint(details)}
	VerificationMetrics.write_json("res://../test-output/p4/ecology_runtime_checks.json", report)
	print(JSON.stringify(report))
	scene.queue_free()
	for frame: int in 6:
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _fingerprint(details: SurfaceDetails) -> Dictionary:
	var result: Dictionary = {}
	for key: Vector4i in details._tiles:
		var tile: Node3D = details._tiles[key]
		result[key] = [tile.position, tile.get_meta("trunks"), tile.get_meta("rocks")]
	return result
