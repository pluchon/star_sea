class_name SurfaceSites
extends RefCounted


static func tangent_forward(up: Vector3) -> Vector3:
	var reference: Vector3 = Vector3.FORWARD
	if absf(reference.dot(up)) > 0.9:
		reference = Vector3.RIGHT
	return (reference - up * reference.dot(up)).normalized()


static func offset_direction(up: Vector3, tangent: Vector3, distance: float, radius: float) -> Vector3:
	var angle: float = distance / radius
	return (up * cos(angle) + tangent * sin(angle)).normalized()


static func find(noise: TerrainNoise) -> Dictionary:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 20261019
	for candidate: int in 4000:
		var y: float = random.randf_range(-1.0, 1.0)
		var angle: float = random.randf_range(0.0, TAU)
		var horizontal: float = sqrt(maxf(1.0 - y * y, 0.0))
		var up: Vector3 = Vector3(horizontal * cos(angle), y, horizontal * sin(angle))
		var height: float = noise.height(up)
		if height < 20.0 or height > 200.0:
			continue
		var forward: Vector3 = tangent_forward(up)
		var right: Vector3 = forward.cross(up).normalized()
		var flat_ground: bool = true
		for tangent: Vector3 in [forward, -forward, right, -right]:
			var adjacent_height: float = noise.height(offset_direction(up, tangent, 10.0, noise.radius))
			if absf(adjacent_height - height) > 1.2:
				flat_ground = false
		if not flat_ground:
			continue
		var shore_direction: Vector3 = Vector3.ZERO
		var shore_forward: Vector3 = Vector3.ZERO
		for heading: int in 16:
			var bearing: float = TAU * float(heading) / 16.0
			var tangent: Vector3 = forward * cos(bearing) + right * sin(bearing)
			for distance_step: int in range(1, 13):
				var direction: Vector3 = offset_direction(up, tangent, float(distance_step) * 25.0, noise.radius)
				if noise.height(direction) <= 0.0:
					var low: float = float(distance_step - 1) * 25.0
					var high: float = float(distance_step) * 25.0
					for refinement: int in 12:
						var midpoint: float = (low + high) * 0.5
						if noise.height(offset_direction(up, tangent, midpoint, noise.radius)) > 0.0:
							low = midpoint
						else:
							high = midpoint
					# 排除内陆浅洼，海岸前方应保持至少一公里的开阔水面。
					var open_water: bool = true
					for sea_distance: float in [350.0, 800.0, 1500.0]:
						if noise.height(offset_direction(up, tangent, low + sea_distance, noise.radius)) > -15.0:
							open_water = false
					if not open_water:
						continue
					shore_direction = offset_direction(up, tangent, maxf(low - 4.0, 0.0), noise.radius)
					shore_forward = (tangent - shore_direction * tangent.dot(shore_direction)).normalized()
					break
			if shore_direction != Vector3.ZERO:
				break
		if shore_direction == Vector3.ZERO:
			continue
		for heading: int in 16:
			var bearing: float = TAU * float(heading) / 16.0
			var tangent: Vector3 = forward * cos(bearing) + right * sin(bearing)
			for distance_step: int in range(1, 17):
				var mountain_direction: Vector3 = offset_direction(up, tangent, float(distance_step) * 500.0, noise.radius)
				var mountain_height: float = noise.height(mountain_direction)
				var distance: float = float(distance_step) * 500.0
				var apparent_elevation: float = atan2(mountain_height - height - distance * distance / (2.0 * noise.radius), distance)
				if mountain_height > 1200.0 and apparent_elevation > deg_to_rad(3.0) and apparent_elevation < deg_to_rad(18.0):
					if not _clear_view(noise, up, tangent, height) or not _visible_peak(noise, up, tangent, height, mountain_height, distance):
						break
					return {
						"direction": up,
						"forward": tangent,
						"height_m": height,
						"mountain_direction": mountain_direction,
						"mountain_height_m": mountain_height,
						"mountain_distance_m": float(distance_step) * 500.0,
						"shore_direction": shore_direction,
						"shore_forward": shore_forward,
						"candidate_index": candidate,
					}
	return {}


static func _clear_view(noise: TerrainNoise, up: Vector3, forward: Vector3, height: float) -> bool:
	# 远峰符合高度条件仍可能被近处山坡挡住，观景位置同时约束视野内的近山。
	for angle: float in [-0.4, -0.2, 0.0, 0.2, 0.4]:
		var tangent: Vector3 = forward.rotated(up, angle)
		for distance: float in [250.0, 500.0, 1000.0, 2000.0, 4000.0]:
			var direction: Vector3 = offset_direction(up, tangent, distance, noise.radius)
			var elevation: float = atan2(noise.height(direction) - height - distance * distance / (2.0 * noise.radius), distance)
			if elevation > deg_to_rad(22.0):
				return false
	return true


static func _visible_peak(noise: TerrainNoise, up: Vector3, forward: Vector3, height: float, peak: float, distance: float) -> bool:
	var eye: float = height + 1.62
	var rise: float = (peak - eye - distance * distance / (2.0 * noise.radius)) / distance
	var steps: int = ceili(distance / 200.0)
	for step: int in range(1, steps):
		var along: float = distance * float(step) / float(steps)
		var direction: Vector3 = offset_direction(up, forward, along, noise.radius)
		var sightline: float = eye + rise * along + along * along / (2.0 * noise.radius)
		if noise.height(direction) > sightline:
			return false
	return true


static func find_inland(noise: TerrainNoise) -> Dictionary:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 20261019 + noise.profile
	for candidate: int in 2000:
		var up: Vector3 = Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0)).normalized()
		var height: float = noise.height(up)
		if height < 35.0 or height > 350.0:
			continue
		var forward: Vector3 = tangent_forward(up)
		var right: Vector3 = forward.cross(up)
		if absf(noise.height(offset_direction(up, forward, 10.0, noise.radius)) - height) > 1.8:
			continue
		if absf(noise.height(offset_direction(up, right, 10.0, noise.radius)) - height) > 1.8:
			continue
		for heading: int in 16:
			var tangent: Vector3 = forward.rotated(up, TAU * float(heading) / 16.0)
			var target: Vector3 = offset_direction(up, tangent, 4000.0, noise.radius)
			var peak: float = noise.height(target)
			if peak > height + 500.0 and _clear_view(noise, up, tangent, height):
				return {"direction": up, "forward": tangent, "height_m": height, "mountain_height_m": peak, "mountain_distance_m": 4000.0, "candidate_index": candidate}
	return {}
