class_name VersionContext
extends RefCounted

const SPACING: float = 2.0 # 可行走面的采样间距，米。
var tree: SceneTree
var scene: Node3D
var planet: Planet
var player: StarSeaPlayer
var director: SkyDirector
var output: String
var _settled_at: Vector3 = Vector3.INF


func open(owner: SceneTree, directory: String) -> void:
	tree = owner
	output = directory
	scene = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	tree.root.add_child(scene)
	tree.current_scene = scene
	planet = scene.get_node("Universe/PlanetDawn") as Planet
	player = scene.get_node("Player") as StarSeaPlayer
	director = scene.get_node("SkyDirector") as SkyDirector
	player.controls_enabled = false
	director.time_paused = true
	(scene.get_node("HUD") as CanvasLayer).visible = false
	tree.root.mode = Window.MODE_WINDOWED
	tree.root.borderless = true
	tree.root.size = Vector2i(1920, 1080)
	tree.root.scaling_3d_scale = 1.0
	tree.root.unfocusable = true
	tree.root.mouse_passthrough = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func settle() -> bool:
	var deadline: int = Time.get_ticks_msec() + 120000
	var stable: int = 0
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var terrain: PlanetTerrain = planet.get_node("Terrain") as PlanetTerrain
		var details: SurfaceDetails = planet.get_node("SurfaceDetails") as SurfaceDetails
		var caves: CaveSystem = planet.get_node("CaveSystem") as CaveSystem
		var waters: InlandWaters = planet.get_node("InlandWaters") as InlandWaters
		var camera_offset: Vector3 = player.camera.global_position - planet.global_position
		var altitude: float = camera_offset.length() - planet.surface_radius(camera_offset.normalized())
		var details_ready: bool = altitude >= 2200 or details.is_settled()
		stable = stable + 1 if terrain.is_settled() and details_ready and caves.is_settled() and waters.is_settled() else 0
		if stable >= 30:
			_settled_at = local_position()
			return true
	return false


func place(local: Vector3, forward: Vector3) -> bool:
	player.simulated_forward = false
	player.controls_enabled = false
	player.place_at(planet.to_global(local + local.normalized() * 0.08), forward, local.normalized())
	player.mode = StarSeaPlayer.Mode.WALK
	# 网格试验之间允许放置；通关机器人只在新旅程的出生点初始化一次。
	if not _settled_at.is_finite() or local.distance_to(_settled_at) > 25:
		if not await settle():
			return false
	await tree.physics_frame
	var up: Vector3 = local.normalized()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(planet.to_global(local + up * 1.19), planet.to_global(local - up * 2), player.collision_mask, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and Vector3(hit["normal"]).dot(up) > 0.7:
		player.place_at(Vector3(hit["position"]) + up * 0.05, forward, up)
	player.controls_enabled = true
	for tick: int in 12:
		await tree.physics_frame
	return true


func local_position() -> Vector3:
	return player.global_position - planet.global_position


func capture(name: String) -> String:
	var path: String = output.path_join(name + ".png")
	if DisplayServer.get_name() == "headless":
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await RenderingServer.frame_post_draw
	if tree.root.get_texture().get_image().save_png(path) != OK:
		return ""
	return path


func close() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
	scene.queue_free()
	for frame: int in 6:
		await tree.process_frame


static func surface(noise: TerrainNoise, direction: Vector3) -> Vector3:
	return direction * (noise.radius + noise.height(direction))


static func regions(noise: TerrainNoise) -> Array[Dictionary]:
	var data: CivilizationData = noise.features.civilization.data
	var result: Array[Dictionary] = []
	result.append(_disc("spawn", surface(noise, noise.features.site["direction"]), noise.features.site["forward"], 300.0))
	result.append(_disc("town", surface(noise, data.town["direction"]), data.town["along"], 150.0))
	for index: int in data.roads.size():
		var road: Dictionary = data.roads[index]
		var points: PackedVector3Array = []
		for direction: Vector3 in road["points"]:
			points.append(surface(noise, direction))
		result.append({"id": "road_%d" % index, "kind": "strip", "points": points, "width": road["width"], "source": "CivilizationData.roads"})
	for index: int in data.bridges.size():
		var bridge: Dictionary = data.bridges[index]
		var center: Vector3 = Vector3(bridge["direction"]) * (noise.radius + float(bridge["level"]))
		result.append(_rect("bridge_%d" % index, center, bridge["across"], Vector2(bridge["length"], 6)))
	var cave: Dictionary = noise.features.caves.networks[0]
	for node: Dictionary in cave["nodes"]:
		if node["id"] in ["foyer", "hall"]:
			result.append(_disc("cave_" + str(node["id"]), node["position"], Transform3D(cave["frame"]).basis.z, node["radius"]))
	for index: int in data.beacons.size():
		var frame: Transform3D = BeaconTowers.tower_frame(data.beacons[index], noise.radius)
		result.append(_disc("beacon_%d" % index, frame.origin, -frame.basis.z, 12))
		for record: Dictionary in BeaconTowers.pieces(data.beacons[index], noise.radius):
			if not str(record["piece"]).begins_with("tower_stair"):
				continue
			var stair_frame: Transform3D = record["transform"]
			for shape_index: int in RuinKit.collision_records(record["piece"]).size():
				var shape: Dictionary = RuinKit.collision_records(record["piece"])[shape_index]
				var bounds: AABB = (shape["shape"] as Shape3D).get_debug_mesh().get_aabb()
				var center: Vector3 = stair_frame * Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
				result.append(_rect("stair_%d_%s_%d" % [index, str(stair_frame.origin), shape_index], center, stair_frame.basis.z, Vector2(bounds.size.z, bounds.size.x)))
	var ladder_up: Vector3 = data.ladder["direction"]
	var ladder_center: Vector3 = ladder_up * (noise.radius + float(data.ladder["height"]) + 18)
	var ladder_forward: Vector3 = data.ladder["forward"]
	result.append(_disc("ladder_base", ladder_center, ladder_forward, 190))
	result.append(_disc("ladder_ring", ladder_center + ladder_up * float(data.ladder["balcony_height"]), ladder_forward, 60, 45))
	result.append(_disc("break_platform", ladder_center + ladder_up * LandingPads.HEIGHT, ladder_forward, 45))
	var ending: Transform3D = data.echo_anchors["dawn_ending"]
	result.append(_rect("gangway", ending.origin + ending.basis.z * (LandingPads.BRIDGE_END - LandingPads.BRIDGE_START) * 0.5, ending.basis.z, Vector2(LandingPads.BRIDGE_END - LandingPads.BRIDGE_START, 8)))
	# 主线道路周围的河岸和入海口由水系末端派生，避免固定世界坐标。
	var water: HydrologyData = noise.features.hydrology.data
	for river: int in water.river_starts.size() - 1:
		var end: int = water.river_starts[river + 1] - 1
		if water.river_levels[end] > 0.3:
			continue
		var point: Vector3 = surface(noise, water.river_points[end])
		if point.distance_to(surface(noise, data.town["direction"])) < 3000 or point.distance_to(surface(noise, noise.features.site["direction"])) < 3000:
			result.append(_disc("mouth_%d" % river, point, SurfaceSites.tangent_forward(point.normalized()), maxf(20, water.river_widths[end] * 2)))
	return result


static func _disc(id: String, center: Vector3, forward: Vector3, radius: float, inner: float = 0) -> Dictionary:
	return {"id": id, "kind": "disc", "center": center, "forward": forward, "radius": radius, "inner": inner, "source": "baked"}


static func _rect(id: String, center: Vector3, forward: Vector3, size: Vector2) -> Dictionary:
	return {"id": id, "kind": "rect", "center": center, "forward": forward, "size": size, "source": "baked"}


static func points(region: Dictionary, noise: TerrainNoise) -> PackedVector3Array:
	var result: PackedVector3Array = []
	if region["kind"] == "strip":
		var route: PackedVector3Array = region["points"]
		for index: int in route.size() - 1:
			var length_value: float = route[index].distance_to(route[index + 1])
			var steps: int = maxi(1, ceili(length_value / SPACING))
			var forward: Vector3 = route[index].direction_to(route[index + 1])
			for step: int in steps:
				var at: Vector3 = route[index].lerp(route[index + 1], float(step) / steps)
				var side: Vector3 = forward.cross(at.normalized()).normalized()
				for lane: int in range(-floori(float(region["width"]) / SPACING / 2), floori(float(region["width"]) / SPACING / 2) + 1):
					result.append(surface(noise, (at + side * lane * SPACING).normalized()))
		return result
	var center: Vector3 = region["center"]
	var up: Vector3 = center.normalized()
	var forward: Vector3 = Vector3(region["forward"]).slide(up).normalized()
	var side: Vector3 = forward.cross(up).normalized()
	var size: Vector2 = region.get("size", Vector2.ONE * float(region.get("radius", 0)) * 2)
	for x: int in range(-floori(size.x / 2 / SPACING), floori(size.x / 2 / SPACING) + 1):
		for z: int in range(-floori(size.y / 2 / SPACING), floori(size.y / 2 / SPACING) + 1):
			var radial: float = Vector2(x, z).length() * SPACING
			if region["kind"] == "disc" and (radial > float(region["radius"]) or radial < float(region["inner"])):
				continue
			var point: Vector3 = center + (forward * x + side * z) * SPACING
			if not str(region["id"]).begins_with("cave_") and str(region["id"]) not in ["ladder_ring", "break_platform", "gangway"] and not str(region["id"]).begins_with("bridge_") and not str(region["id"]).begins_with("stair_"):
				point = surface(noise, point.normalized())
			result.append(point)
	return result
