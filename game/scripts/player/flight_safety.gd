class_name FlightSafety
extends RefCounted

const CLEARANCE: float = 1.2
const CONTACT_TOLERANCE: float = 0.05
const SAMPLE_DISTANCE: float = 8.0


static func sweep(tree: SceneTree, start: Vector3, finish: Vector3) -> Dictionary:
	var movement: Vector3 = finish - start
	var distance: float = movement.length()
	var direction: Vector3 = movement / maxf(distance, 0.000001)
	var earliest: float = distance + 1.0
	var result: Dictionary = {}
	for node: Node in tree.get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		var tower: Dictionary = _tower_sweep(planet, start, finish)
		if not tower.is_empty():
			var hit_distance: float = start.distance_to(tower["position"])
			if hit_distance < earliest:
				earliest = hit_distance
				result = tower
		var relative: Vector3 = start - planet.global_position
		var bound: float = planet.radius + TerrainNoise.MAX_HEIGHT + CLEARANCE + SAMPLE_DISTANCE
		var along: float = relative.dot(direction)
		var closest: Vector3 = relative + direction * clampf(-along, 0.0, distance)
		if closest.length() > bound:
			continue
		var discriminant: float = bound * bound - (relative - direction * along).length_squared()
		if discriminant < 0.0:
			continue
		var entry: float = maxf(0.0, -along - sqrt(discriminant))
		var exit: float = minf(minf(distance, earliest), -along + sqrt(discriminant))
		if entry > exit:
			continue
		var previous: float = entry
		var steps: int = maxi(1, ceili((exit - entry) / SAMPLE_DISTANCE))
		for step: int in steps + 1:
			var travel: float = lerpf(entry, exit, float(step) / steps)
			var point: Vector3 = relative + direction * travel
			# 球面位置存储为单精度，接触后的毫米级舍入不能使后续起飞一直命中起点。
			if _height(planet, point) >= CLEARANCE - CONTACT_TOLERANCE:
				previous = travel
				continue
			# 对整段位移寻找首次接触，避免高速穿过山体或整颗星球后落在另一侧。
			var low: float = previous
			var high: float = travel
			for iteration: int in 12:
				var middle: float = (low + high) * 0.5
				if _height(planet, relative + direction * middle) < CLEARANCE:
					high = middle
				else:
					low = middle
			point = relative + direction * low
			var up: Vector3 = point.normalized()
			if up.is_zero_approx():
				up = Vector3.UP
			earliest = low
			result = {"position": planet.global_position + up * (planet.surface_radius(up) + CLEARANCE), "up": up}
			break
	return result


static func _tower_sweep(planet: Planet, start: Vector3, finish: Vector3) -> Dictionary:
	if planet.profile != 0 or planet.noise.features.civilization == null:
		return {}
	var frame: Transform3D = planet.global_transform * LandingPads.frame(planet)
	var a: Vector3 = frame.affine_inverse() * start
	var b: Vector3 = frame.affine_inverse() * finish
	var bound: float = SkyLadderMeshes.radius_at(0) + 15
	if AABB(Vector3(-bound, 0, -bound), Vector3(bound * 2, 6200, bound * 2)).intersects_segment(a, b) == null:
		return {}
	var steps: int = maxi(1, ceili(a.distance_to(b) / SAMPLE_DISTANCE))
	for index: int in steps + 1:
		var t: float = float(index) / steps
		var point: Vector3 = a.lerp(b, t)
		if point.y < 0 or point.y > 6200 or Vector2(point.x, point.z).length() >= SkyLadderMeshes.radius_at(point.y) + 15:
			continue
		var low: float = maxf(0, t - 1.0 / steps)
		var high: float = t
		for iteration: int in 14:
			var mid: float = (low + high) * 0.5
			var sample: Vector3 = a.lerp(b, mid)
			if Vector2(sample.x, sample.z).length() < SkyLadderMeshes.radius_at(sample.y) + 15:
				high = mid
			else:
				low = mid
		var contact: Vector3 = a.lerp(b, low)
		var normal: Vector3 = frame.basis * Vector3(contact.x, 0, contact.z).normalized()
		return {"position": frame * contact, "up": frame.basis.y, "normal": normal, "tower": true}
	return {}


static func _height(planet: Planet, point: Vector3) -> float:
	if point.length_squared() < 1.0:
		return -planet.radius
	return point.length() - planet.surface_radius(point.normalized())
