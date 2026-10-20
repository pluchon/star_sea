class_name LandformLayout
extends RefCounted

const RIDGE_STEP: float = 7000.0 # 十段构成约七十公里的山脉。
const CANYON_STEP: float = 2200.0 # 十二段构成约二十六公里的峡谷。


static func generate(noise: TerrainNoise, layout: Dictionary) -> Dictionary:
	var spawn: Vector3 = layout["site"]["direction"]
	var mountain: Vector3 = layout["site"]["mountain_direction"]
	var toward: Vector3 = spawn.direction_to(mountain).slide(mountain).normalized()
	var side: Vector3 = toward.cross(mountain).normalized()
	var ridge: PackedVector3Array = [mountain]
	for sign_value: float in [-1.0, 1.0]:
		var position: Vector3 = mountain
		var heading: Vector3 = side * sign_value
		for index: int in 5:
			var best: Vector3 = Vector3.ZERO
			var best_score: float = -INF
			for candidate: int in 17:
				var turn: float = (candidate - 8) * 0.075
				var direction: Vector3 = SurfaceSites.offset_direction(position, heading.rotated(position, turn), RIDGE_STEP, noise.radius)
				var land: float = noise.base_height(direction)
				for coast: int in 8:
					var probe: Vector3 = SurfaceSites.offset_direction(direction, SurfaceSites.tangent_forward(direction).rotated(direction, coast * TAU / 8), 4000.0, noise.radius)
					land = minf(land, noise.base_height(probe))
				var score: float = minf(land, 500.0) - absf(turn) * 90.0
				if direction.distance_to(spawn) * noise.radius < 6000.0:
					score -= 10000.0
				if score > best_score:
					best_score = score
					best = direction
			heading = position.direction_to(best).slide(best).normalized()
			position = best
			if sign_value < 0:
				ridge.insert(0, best)
			else:
				ridge.append(best)
	var result: Dictionary = {"version": 2, "spawn": spawn, "ridge": ridge, "peaks": [], "passes": []}
	var length: float = 0.0
	for index: int in ridge.size():
		if index > 0:
			length += ridge[index - 1].angle_to(ridge[index]) * noise.radius
		if index in [2, 5, 8]:
			result["peaks"].append({"direction": ridge[index], "right": side.slide(ridge[index]).normalized(), "forward": toward.slide(ridge[index]).normalized(), "height": 3950.0 if index == 5 else 3650.0, "shape": "horn" if index == 5 else ("twins" if index == 2 else "mesa")})
		if index in [3, 6, 9]:
			var along: Vector3 = ridge[index - 1].direction_to(ridge[index + 1]).slide(ridge[index]).normalized()
			result["passes"].append({"direction": ridge[index], "distance": length, "ground": noise.base_height(ridge[index]), "along": along, "across": along.cross(ridge[index]).normalized()})
	# 从出发地侧方选高原，使峡谷与主山脉的方位相差至少六十度。
	var best_path: PackedVector3Array = []
	var best_score: float = INF
	for bearing: int in range(6, 27):
		var heading: Vector3 = toward.rotated(spawn, bearing * TAU / 32)
		for distance: float in [11000.0, 14000.0, 17000.0, 20000.0, 23000.0]:
			var center: Vector3 = SurfaceSites.offset_direction(spawn, heading, distance, noise.radius)
			var tangent: Vector3 = heading.cross(center).normalized()
			for orientation: float in [-1.0, 1.0]:
				var path: PackedVector3Array = []
				var score: float = 0.0
				for index: int in 13:
					var step: float = (index - 6) * CANYON_STEP * orientation
					var point: Vector3 = SurfaceSites.offset_direction(center, tangent, step, noise.radius)
					point = SurfaceSites.offset_direction(point, heading, sin(index * 1.4) * 1100.0, noise.radius)
					path.append(point)
					var ground: float = noise.base_height(point)
					score += absf(ground - lerpf(850.0, 100.0, index / 12.0))
					score += pow(maxf(0.0, ground - 960.0), 2) * 2.0
					if index < 10:
						score += pow(maxf(0.0, 450.0 - ground), 2)
				if score < best_score:
					best_score = score
					best_path = path
	result["canyon"] = best_path
	result["canyon_source_level"] = maxf(15.0, noise.base_height(best_path[0]))
	result["river_cave_entrance"] = best_path[7]
	return result
