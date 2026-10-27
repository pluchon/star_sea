class_name PlacementChecks
extends RefCounted


static func run(additional_sources: Array[Dictionary] = []) -> Dictionary:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000)
	var data: CivilizationData = noise.features.civilization.data
	var sources: Array[Dictionary] = data.placements.duplicate()
	for tower: Dictionary in data.beacons:
		sources.append_array(BeaconTowers.pieces(tower, noise.radius))
	for network: Dictionary in noise.features.caves.networks:
		for prop: Dictionary in network["props"]:
			var source: Dictionary = prop.duplicate()
			source["underground"] = true
			sources.append(source)
	sources.append_array(additional_sources)
	var landmarks: Landmarks = Landmarks.new()
	landmarks.build(noise)
	for body: Node in landmarks.get_children():
		for node: Node in body.get_children():
			if not node is MeshInstance3D:
				continue
			var collisions: Array[Dictionary] = []
			for child: Node in body.get_children():
				if child is CollisionShape3D:
					collisions.append({"shape": (child as CollisionShape3D).shape, "transform": (child as CollisionShape3D).transform})
			sources.append({"piece": str(body.name), "transform": (body as Node3D).transform * (node as Node3D).transform, "mesh": (node as MeshInstance3D).mesh, "collisions": collisions})
	var vegetation: Dictionary = _vegetation_sources(noise)
	sources.append_array(vegetation["sources"])
	var records: Array[Dictionary] = []
	var findings: Array[Dictionary] = []
	var buckets: Dictionary = {}
	var large: Array[int] = []
	var supports: Array[Dictionary] = []
	for index: int in sources.size():
		var source: Dictionary = sources[index]
		var transform_value: Transform3D = source["transform"]
		var mesh: Mesh = source["mesh"] if source.has("mesh") else RuinKit.mesh(source["piece"])
		var box: AABB = mesh.get_aabb()
		var world_box: AABB = transform_value * box
		var record: Dictionary = {"id": index, "name": source["piece"], "mesh": mesh, "underground": source.get("underground", false), "transform": transform_value, "box": box, "world_box": world_box, "intentional_stack": source.get("intentional_stack", false)}
		records.append(record)
		var low: Vector3i = Vector3i((world_box.position / 16).floor())
		var high: Vector3i = Vector3i((world_box.end / 16).floor())
		if (high.x - low.x + 1) * (high.y - low.y + 1) * (high.z - low.z + 1) > 4096:
			large.append(index)
			low = Vector3i.ONE
			high = Vector3i.ZERO
		for x: int in range(low.x, high.x + 1):
			for y: int in range(low.y, high.y + 1):
				for z: int in range(low.z, high.z + 1):
					var key: Vector3i = Vector3i(x, y, z)
					if not buckets.has(key):
						buckets[key] = []
					buckets[key].append(index)
		var bottom: Vector3 = transform_value * Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var top: Vector3 = transform_value * Vector3(box.get_center().x, box.end.y, box.get_center().z)
		var ground: float = noise.radius + noise.height(bottom.normalized())
		var gap: float = bottom.length() - ground
		if gap > 0.1:
			supports.append(record)
		if not source.get("underground", false) and top.length() < noise.radius + noise.height(top.normalized()):
			findings.append(_finding("buried", record, {"position": top}))
		var collisions: Array[Dictionary] = []
		collisions.assign(source["collisions"] if source.has("collisions") else RuinKit.collision_records(source["piece"]))
		if box.size.y > 0.5 and (collisions.is_empty() or not bool(source.get("collision", true))):
			findings.append(_finding("missing_collision", record, {"height_m": box.size.y}))
		for collision: Dictionary in collisions:
			var shape: Shape3D = collision["shape"]
			var at: Transform3D = collision.get("transform", Transform3D.IDENTITY)
			var collision_box: AABB = at * shape.get_debug_mesh().get_aabb()
			if not box.grow(0.2).encloses(collision_box):
				findings.append(_finding("oversized_collision", record, {"visual_bounds": box, "collision_bounds": collision_box}))
	var visited: Dictionary = {}
	# 超大天梯主体不展开为数亿个空间格子，逐一与现有物件做包围盒筛选。
	for index: int in large:
		for other: int in records.size():
			if index != other and AABB(records[index]["world_box"]).intersects(records[other]["world_box"]):
				var key: Vector3i = Vector3i(-index - 1, -other - 1, -1)
				buckets[key] = [index, other]
	for values: Array in buckets.values():
		for first: int in values:
			for second: int in values:
				if second <= first:
					continue
				var key: Vector2i = Vector2i(first, second)
				if visited.has(key):
					continue
				visited[key] = true
				var a: Dictionary = records[first]
				var b: Dictionary = records[second]
				if not AABB(a["world_box"]).intersects(b["world_box"]) or a["intentional_stack"] or b["intentional_stack"]:
					continue
				var penetration: float = _penetration(a, b)
				var flat: bool = _ground_piece(a) and _ground_piece(b)
				var planar: float = _planar_overlap(a, b) if flat else 0.0
				if (flat and planar > 0.05) or penetration > 0.1:
					var mesh_overlap: float = _surface_overlap(a, b) if flat else 0.0
					findings.append({"type": "ground_overlap" if flat else "intersection_candidate", "objects": [first, second], "names": [a["name"], b["name"]], "position": Transform3D(a["transform"]).origin, "penetration_m": penetration, "planar_overlap_m": planar, "mesh_overlap_lower_bound_m": mesh_overlap, "method": "oriented_bounds_SAT_and_top_triangles" if flat else "oriented_bounds_SAT", "requires_mesh_review": not flat or mesh_overlap <= 0.05})
				if _coplanar(a, b):
					findings.append({"type": "coplanar_faces", "objects": [first, second], "names": [a["name"], b["name"]], "position": Transform3D(a["transform"]).origin, "method": "top_bounds_projection", "requires_mesh_review": true})
	for record: Dictionary in supports:
		if not _supported(record, records, buckets, large, noise):
			findings.append(_finding("floating", record, {"position": Transform3D(record["transform"]).origin, "support_distance_exceeds_m": 0.1}))
	landmarks.free()
	return {"passed": findings.is_empty(), "placements": records.size(), "candidate_pairs": visited.size(), "findings": findings, "scope": "文明构件、塔、洞内构件、地标、天梯独立模型及主线附近植被石块", "vegetation_tiles": vegetation["tiles"], "coverage_complete": not additional_sources.is_empty(), "narrow_phase": "地面重叠补充实际朝上三角形的交集宽度下界，未确认项及一般穿插保留为包围盒候选，要求结合截图复核", "tolerances_m": {"ground_overlap": 0.05, "penetration": 0.1, "ground_gap": 0.1, "collision_extra": 0.2}}


static func _ground_piece(record: Dictionary) -> bool:
	if AABB(record["box"]).size.y > 0.6:
		return false
	for prefix: String in ["floor", "plaza", "road", "terrace", "step"]:
		if str(record["name"]).begins_with(prefix):
			return true
	return false


static func _supported(record: Dictionary, records: Array[Dictionary], buckets: Dictionary, large: Array[int], noise: TerrainNoise) -> bool:
	var mesh: Mesh = record["mesh"]
	var bounds: AABB = record["box"]
	var transform_value: Transform3D = record["transform"]
	var samples: Dictionary = {}
	for vertex: Vector3 in mesh.get_faces():
		if vertex.y <= bounds.position.y + 0.03:
			samples[vertex.snapped(Vector3.ONE * 0.01)] = true
	for vertex: Vector3 in samples:
		var point: Vector3 = transform_value * vertex
		var up: Vector3 = point.normalized()
		if not record["underground"] and point.length() - noise.radius - noise.height(up) <= 0.1:
			return true
		var candidates: Array = large.duplicate()
		var cell: Vector3i = Vector3i((point / 16).floor())
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				for dz: int in range(-1, 2):
					candidates.append_array(buckets.get(cell + Vector3i(dx, dy, dz), []))
		var seen: Dictionary = {}
		for index: int in candidates:
			if index == int(record["id"]) or seen.has(index):
				continue
			seen[index] = true
			var target: Dictionary = records[index]
			if not AABB(target["world_box"]).grow(0.11).has_point(point):
				continue
			var inverse: Transform3D = Transform3D(target["transform"]).affine_inverse()
			var origin: Vector3 = inverse * (point + up * 0.02)
			var direction: Vector3 = inverse.basis * -up
			if AABB(target["box"]).grow(0.02).intersects_ray(origin, direction) == null:
				continue
			var faces: PackedVector3Array = (target["mesh"] as Mesh).get_faces()
			for face: int in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, faces[face], faces[face + 1], faces[face + 2])
				if hit is Vector3 and (Transform3D(target["transform"]) * Vector3(hit)).distance_to(point) <= 0.1:
					return true
		if record["underground"]:
			var cave: CaveData = noise.features.caves
			for network: Dictionary in cave.networks:
				var local: Vector3 = Transform3D(network["frame"]).affine_inverse() * point
				var below: Vector3 = Transform3D(network["frame"]).basis.inverse() * -up * 0.1
				if CaveData.field(local + below, network["primitives"], null) >= 0:
					return true
	return false


static func _vegetation_sources(noise: TerrainNoise) -> Dictionary:
	var tiles: Dictionary = {}
	var centers: PackedVector3Array = []
	var data: CivilizationData = noise.features.civilization.data
	centers.append(noise.features.site["direction"])
	centers.append(data.town["direction"])
	centers.append(data.ladder["direction"])
	for tower: Dictionary in data.beacons:
		centers.append(tower["direction"])
	for road: Dictionary in data.roads:
		var points: PackedVector3Array = road["points"]
		for index: int in range(0, points.size(), 4):
			centers.append(points[index])
	for center: Vector3 in centers:
		for divisions: int in [SurfaceDetails.NEAR_DIVISIONS, SurfaceDetails.FOREST_DIVISIONS]:
			for key: Vector3i in SurfaceGrid.nearby(center, noise.radius, 70, divisions):
				tiles[Vector4i(divisions, key.x, key.y, key.z)] = true
	var sources: Array[Dictionary] = []
	var meshes: Dictionary = {}
	for kind: String in ["stone", "broadleaf", "pine", "shrub", "fern", "reeds", "mushrooms"]:
		meshes[kind] = SurfaceDetails.mesh_for_kind(kind)
	for key: Vector4i in tiles:
		var generated: Dictionary = SurfaceDetails.generate(noise, key, 20261019, noise.features.site["direction"])
		for kind: String in meshes:
			var mesh: Mesh = meshes[kind]
			for transform_value: Transform3D in generated[kind]:
				transform_value.origin += Vector3(generated["center"])
				var near: bool = false
				for center: Vector3 in centers:
					if transform_value.origin.normalized().distance_to(center) * noise.radius <= 70:
						near = true
						break
				if not near:
					continue
				var collisions: Array[Dictionary] = []
				if kind == "stone":
					collisions.append({"shape": mesh.create_convex_shape(), "transform": Transform3D.IDENTITY})
				elif kind in ["broadleaf", "pine"]:
					var shape: CapsuleShape3D = CapsuleShape3D.new()
					shape.radius = 0.38
					shape.height = 6
					collisions.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3.UP * 3)})
				sources.append({"piece": kind, "transform": transform_value, "mesh": mesh, "collisions": collisions})
	return {"sources": sources, "tiles": tiles.size()}


static func _finding(kind: String, record: Dictionary, details: Dictionary) -> Dictionary:
	var value: Dictionary = {"type": kind, "object": record["id"], "name": record["name"], "position": Transform3D(record["transform"]).origin}
	value.merge(details)
	return value


static func _corners(record: Dictionary) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for index: int in 8:
		result.append(Transform3D(record["transform"]) * AABB(record["box"]).get_endpoint(index))
	return result


static func _penetration(a: Dictionary, b: Dictionary) -> float:
	var first: PackedVector3Array = _corners(a)
	var second: PackedVector3Array = _corners(b)
	var basis_a: Basis = Transform3D(a["transform"]).basis.orthonormalized()
	var basis_b: Basis = Transform3D(b["transform"]).basis.orthonormalized()
	var axes: Array[Vector3] = [basis_a.x, basis_a.y, basis_a.z, basis_b.x, basis_b.y, basis_b.z]
	for axis_a: Vector3 in [basis_a.x, basis_a.y, basis_a.z]:
		for axis_b: Vector3 in [basis_b.x, basis_b.y, basis_b.z]:
			if axis_a.cross(axis_b).length_squared() > 0.00001:
				axes.append(axis_a.cross(axis_b).normalized())
	var minimum: float = INF
	for axis: Vector3 in axes:
		var low_a: float = INF
		var high_a: float = -INF
		var low_b: float = INF
		var high_b: float = -INF
		for point: Vector3 in first:
			low_a = minf(low_a, point.dot(axis))
			high_a = maxf(high_a, point.dot(axis))
		for point: Vector3 in second:
			low_b = minf(low_b, point.dot(axis))
			high_b = maxf(high_b, point.dot(axis))
		minimum = minf(minimum, minf(high_a, high_b) - maxf(low_a, low_b))
	return minimum


static func _planar_overlap(a: Dictionary, b: Dictionary) -> float:
	var basis_a: Basis = Transform3D(a["transform"]).basis.orthonormalized()
	var first: PackedVector3Array = _corners(a)
	var second: PackedVector3Array = _corners(b)
	var minimum: float = INF
	for axis: Vector3 in [basis_a.x, basis_a.z, Transform3D(b["transform"]).basis.x.normalized(), Transform3D(b["transform"]).basis.z.normalized()]:
		var low_a: float = INF
		var high_a: float = -INF
		var low_b: float = INF
		var high_b: float = -INF
		for point: Vector3 in first:
			low_a = minf(low_a, point.dot(axis))
			high_a = maxf(high_a, point.dot(axis))
		for point: Vector3 in second:
			low_b = minf(low_b, point.dot(axis))
			high_b = maxf(high_b, point.dot(axis))
		minimum = minf(minimum, minf(high_a, high_b) - maxf(low_a, low_b))
	return minimum


static func _coplanar(a: Dictionary, b: Dictionary) -> bool:
	var ta: Transform3D = a["transform"]
	var tb: Transform3D = b["transform"]
	if ta.basis.y.normalized().dot(tb.basis.y.normalized()) < 0.9999:
		return false
	var top_a: Vector3 = ta * Vector3(0, AABB(a["box"]).end.y, 0)
	var top_b: Vector3 = tb * Vector3(0, AABB(b["box"]).end.y, 0)
	return absf((top_a - top_b).dot(ta.basis.y.normalized())) < 0.002 and _planar_overlap(a, b) > 0.05


static func _surface_overlap(a: Dictionary, b: Dictionary) -> float:
	var frame: Transform3D = a["transform"]
	frame.basis = frame.basis.orthonormalized()
	var inverse: Transform3D = frame.affine_inverse()
	var first: Array[Dictionary] = _top_triangles(a, inverse)
	var second: Array[Dictionary] = _top_triangles(b, inverse)
	var width: float = 0
	for triangle_a: Dictionary in first:
		for triangle_b: Dictionary in second:
			if not Rect2(triangle_a["bounds"]).intersects(triangle_b["bounds"]):
				continue
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(triangle_a["points"], triangle_b["points"]):
				var minimum: float = INF
				for edge: int in polygon.size():
					var tangent: Vector2 = polygon[(edge + 1) % polygon.size()] - polygon[edge]
					if tangent.length_squared() < 0.00000001:
						continue
					var axis: Vector2 = tangent.orthogonal().normalized()
					var low: float = INF
					var high: float = -INF
					for point: Vector2 in polygon:
						low = minf(low, point.dot(axis))
						high = maxf(high, point.dot(axis))
					minimum = minf(minimum, high - low)
				if is_finite(minimum):
					width = maxf(width, minimum)
	return width


static func _top_triangles(record: Dictionary, inverse: Transform3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var transform_value: Transform3D = inverse * Transform3D(record["transform"])
	var faces: PackedVector3Array = (record["mesh"] as Mesh).get_faces()
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = transform_value * faces[index]
		var b: Vector3 = transform_value * faces[index + 1]
		var c: Vector3 = transform_value * faces[index + 2]
		var normal: Vector3 = -(b - a).cross(c - a)
		if normal.length_squared() < 0.00000001 or normal.normalized().y < 0.7:
			continue
		var points: PackedVector2Array = [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]
		var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points:
			bounds = bounds.expand(point)
		result.append({"points": points, "bounds": bounds})
	return result
