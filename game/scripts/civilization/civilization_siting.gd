class_name CivilizationSiting
extends RefCounted

const SAMPLE_RADIUS: float = 250.0 # 选址平缓范围，米。
const MAX_WALKING_DISTANCE: float = 4800.0 # 普通步行四米每秒，主线第一段最多二十分钟。
const MIN_TOWN_DISTANCE: float = 3000.0 # 避开两公里出生保护区，并留出文明区整地范围。


static func ladder(noise: TerrainNoise) -> Dictionary:
	var spawn: Vector3 = noise.features.site["direction"]
	var forward: Vector3 = noise.features.site["forward"]
	for distance: int in range(12000, 25001, 250):
		for degrees: int in range(40, 121, 2):
			for sign_value: float in [-1.0, 1.0]:
				var heading: Vector3 = forward.rotated(spawn, deg_to_rad(degrees * sign_value))
				var direction: Vector3 = SurfaceSites.offset_direction(spawn, heading, distance, noise.radius)
				var height: float = noise.height(direction)
				if height < 150.0 or height > 700.0 or noise.water_surface(direction) > -INF or noise.river_distance(direction) < 40.0:
					continue
				if average_slope(noise, direction) >= 0.1:
					continue
				var eye: Vector3 = spawn * (noise.radius + noise.height(spawn) + 1.7)
				if not visible(noise, eye, direction * (noise.radius + height + 6200.0)):
					continue
				return {"direction": direction, "height": height, "forward": direction.direction_to(spawn).slide(direction).normalized(), "distance": float(distance), "bearing": degrees * sign_value}
	push_error("文明烘焙失败：没有满足地形、方位和视线要求的天梯位置。")
	return {}


static func town(noise: TerrainNoise, hydro: HydrologyData, tower: Dictionary, small_river: bool = false) -> Dictionary:
	var spawn: Vector3 = noise.features.site["direction"]
	var minimum_area: float = 10.0 if small_river else 40.0
	var minimum_width: float = 3.0 + 2.2 * sqrt(minimum_area)
	var search: Array[float] = []
	search.assign([0.12, 0.18] if small_river else [0.08, 0.12])
	for slope_limit: float in search:
		var choices: Array[Dictionary] = []
		for river: int in hydro.river_starts.size() - 1:
			for index: int in range(hydro.river_starts[river] + 1, hydro.river_starts[river + 1] - 1):
				var point: Vector3 = hydro.river_points[index]
				if hydro.river_widths[index] < minimum_width or hydro.river_levels[index] < 15 or hydro.river_levels[index] > 300 or point.dot(spawn) < cos((MAX_WALKING_DISTANCE + 160.0) / noise.radius) or point.dot(spawn) > cos((MIN_TOWN_DISTANCE - 160.0) / noise.radius):
					continue
				var along: Vector3 = hydro.river_points[index - 1].direction_to(hydro.river_points[index + 1]).slide(point).normalized()
				var side: Vector3 = along.cross(point).normalized()
				for bank: float in [-1.0, 1.0]:
					for shift: float in [-100.0, -50.0, 0.0, 50.0, 100.0]:
						for offset: float in [60.0, 90.0, 120.0]:
							var direction: Vector3 = (point * noise.radius + side * offset * bank + along * shift).normalized()
							var distance: float = spawn.angle_to(direction) * noise.radius
							if distance < MIN_TOWN_DISTANCE or distance > MAX_WALKING_DISTANCE:
								continue
							var nearest: Vector4 = noise.features.hydrology.nearest(direction)
							if nearest.x < 60.0 or nearest.x > 120.1 or nearest.w < 0.0 or nearest.z < minimum_width:
								continue
							var height: float = noise.height(direction)
							if height < 20.0 or height > 300.0 or noise.water_surface(direction, height) > -INF or noise.slope(direction, height) > slope_limit * 2.0:
								continue
							var owner: int = hydro.river_starts.bsearch(int(nearest.w), false) - 1
							choices.append({"direction": direction, "distance": distance, "river_index": int(nearest.w), "river": owner, "river_offset": nearest.x, "along": along, "bank": side * bank, "height": height})
		choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a["distance"]) - 3800.0) < absf(float(b["distance"]) - 3800.0))
		var walk_choices: Array[Dictionary] = []
		for choice: Dictionary in choices:
			var direction: Vector3 = choice["direction"]
			var slope: float = average_slope(noise, direction)
			if slope >= slope_limit:
				continue
			var eye: Vector3 = direction * (noise.radius + choice["height"] + 1.7)
			var tower_top: Vector3 = Vector3(tower["direction"]) * (noise.radius + float(tower["height"]) + 6200.0)
			if not visible(noise, eye, tower_top):
				continue
			var heights: Array[float] = [choice["height"]]
			for sample: int in 16:
				heights.append(noise.height(SurfaceSites.offset_direction(direction, choice["along"].rotated(direction, sample * TAU / 16), 120.0, noise.radius)))
			heights.sort()
			choice["level"] = heights[heights.size() / 2]
			if small_river and not _has_intake(hydro, choice):
				continue
			choice["slope"] = slope
			choice["slope_limit"] = slope_limit
			choice["minimum_area_km2"] = minimum_area
			choice["small_river_fallback"] = small_river
			# 先筛选合格河岸，再比较实际寻路长度；同一段河岸不重复计算。
			var duplicate: bool = false
			for tested: Dictionary in walk_choices:
				duplicate = duplicate or direction.distance_to(tested["direction"]) * noise.radius < 150.0
			if duplicate:
				continue
			var route: PackedVector3Array = CivilizationPaths.find(noise, spawn, direction, [], true)
			var length_value: float = CivilizationPaths.walk_length(noise, route)
			choice["walking_distance_m"] = length_value
			choice["walking_score"] = absf(length_value - 4200.0) + slope * 100.0
			choice["walking_route"] = route
			walk_choices.append(choice)
			if walk_choices.size() >= 12:
				break
		walk_choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["walking_score"] < b["walking_score"])
		for choice: Dictionary in walk_choices:
			if choice["walking_distance_m"] >= 3600.0 and choice["walking_distance_m"] <= MAX_WALKING_DISTANCE:
				return choice
	if small_river:
		push_error("文明烘焙失败：近处小河段仍无合格古城河岸。")
	else:
		print("文明选址：大河没有合格河岸，交由既有近处小河段方案继续。")
	return {}


static func _has_intake(hydro: HydrologyData, town_site: Dictionary) -> bool:
	var point: int = town_site["river_index"]
	var first: int = hydro.river_starts[town_site["river"]]
	var distance: float = 0.0
	for index: int in range(point - 1, first - 1, -1):
		distance += hydro.river_points[index].distance_to(hydro.river_points[index + 1]) * hydro.planet_radius
		if distance > 2000.0:
			return false
		if distance >= 800.0 and hydro.river_levels[index] >= float(town_site["level"]) + 12.0:
			return true
	return false


static func average_slope(noise: TerrainNoise, direction: Vector3) -> float:
	var heading: Vector3 = SurfaceSites.tangent_forward(direction)
	var total: float = 0.0
	for sample: int in 16:
		var point: Vector3 = SurfaceSites.offset_direction(direction, heading.rotated(direction, sample * TAU / 16), SAMPLE_RADIUS * (0.5 if sample % 2 == 0 else 1.0), noise.radius)
		total += noise.slope(point, noise.height(point))
	return total / 16.0


static func visible(noise: TerrainNoise, eye: Vector3, target: Vector3) -> bool:
	var steps: int = ceili(eye.distance_to(target) / 40.0)
	for sample: int in range(1, steps):
		var point: Vector3 = eye.lerp(target, sample / float(steps))
		if point.length() < noise.radius + noise.height(point.normalized()) + 0.5:
			return false
	return true


static func balcony_height(noise: TerrainNoise, tower: Dictionary, town_site: Dictionary) -> float:
	var up: Vector3 = tower["direction"]
	var origin: Vector3 = up * (noise.radius + float(tower["height"]) + 18)
	var town_up: Vector3 = town_site["direction"]
	var target: Vector3 = town_up * (noise.radius + noise.height(town_up) + 2)
	var toward: Vector3 = origin.direction_to(target).slide(up).normalized()
	for height: int in range(30, 6001, 5):
		if visible(noise, origin + toward * 60 + up * (height + 1.7), target):
			return float(height + 30)
	return -1.0
