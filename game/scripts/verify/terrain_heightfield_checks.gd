class_name TerrainHeightfieldChecks
extends RefCounted


static func run(noise: TerrainNoise) -> Dictionary:
	var failures: Array[String] = []
	var field: DawnHeightfield = noise.heightfield
	if field.grid != 2048:
		failures.append("正式高度场必须使用每面 2048 格网。")
	var drainage: Dictionary = field.metadata.get("drainage", {})
	if drainage.is_empty() or int(drainage.get("generated_uphill_edges", -1)) != 0 or int(drainage.get("generated_land_roots", -1)) != 0:
		failures.append("生成区缺少逐格汇水记录，或存在封闭的陆地出水链。")
	var seams: Dictionary = _seams(field)
	if seams["height_m"] > 0.5 or seams["normal_degrees"] > 3.0 or seams["edge_pairs"] != 12:
		failures.append("高度场立方体接缝超过高度或法线容差。")
	var source: TerrainIntent = TerrainIntent.new()
	var spawn: Vector3 = noise.features.site["direction"]
	var forward: Vector3 = noise.features.site["forward"]
	var right: Vector3 = forward.cross(spawn).normalized()
	var spawn_error: float = 0.0
	var spawn_samples: int = 0
	for x: int in range(-250, 251):
		for y: int in range(-250, 251):
			if x * x + y * y > 62500:
				continue
			var point: Vector3 = (spawn * noise.radius + right * x * 8.0 + forward * y * 8.0).normalized()
			spawn_samples += 1
			spawn_error = maxf(spawn_error, absf(noise.base_height(point) - source.original_height(point)))
	if spawn_error > 1.0:
		failures.append("出发地两公里内高度偏差超过一米。")
	var final_spawn_error: Variant = null
	var original_path: String = "res://../test-output/terrain/original.json"
	if FileAccess.file_exists(original_path):
		final_spawn_error = 0.0
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(original_path))
		for record: Dictionary in original["samples"]:
			var values: Array = record["direction"]
			var point: Vector3 = Vector3(values[0], values[1], values[2])
			final_spawn_error = maxf(float(final_spawn_error), absf(noise.height(point) - float(record["height"])))
		if float(final_spawn_error) > 1.0:
			failures.append("保护区最终高度与改动前实测相差超过一米。")
	var land_samples: int = 0
	var steep_samples: int = 0
	var histogram: PackedInt32Array = []
	histogram.resize(18)
	var points: PackedVector3Array = []
	for index: int in 20000:
		var y: float = 1.0 - 2.0 * (index + 0.5) / 20000.0
		var angle: float = index * 2.39996322973
		var point: Vector3 = Vector3(cos(angle) * sqrt(1.0 - y * y), y, sin(angle) * sqrt(1.0 - y * y))
		points.append(point)
		var height: float = noise.base_height(point)
		var exceptional: bool = noise.features.landforms.nearest(point, true).x < 2300.0
		for peak: Dictionary in noise.features.landforms.metadata["peaks"]:
			exceptional = exceptional or point.distance_to(peak["direction"]) * noise.radius < 2200.0
		if height > 0 and not exceptional:
			land_samples += 1
			var a: float = noise.base_height((point * noise.radius + SurfaceSites.tangent_forward(point) * 4.0).normalized()) - height
			var b: float = noise.base_height((point * noise.radius + SurfaceSites.tangent_forward(point).cross(point) * 4.0).normalized()) - height
			if sqrt(a * a + b * b) / 4.0 > 1.0:
				steep_samples += 1
			if height >= 300 and height < 2600:
				histogram[int(fposmod(height, 180.0) / 10.0)] += 1
	var steep_ratio: float = float(steep_samples) / maxi(land_samples, 1)
	if steep_ratio >= 0.02:
		failures.append("峡谷与名峰之外超过四十五度的陆地面积比例达到 %.3f%%。" % (steep_ratio * 100))
	var total: int = 0
	var maximum_bin: int = 0
	for count: int in histogram:
		total += count
		maximum_bin = maxi(maximum_bin, count)
	var spike: float = float(maximum_bin) / maxf(float(total) / histogram.size(), 1)
	if spike > 1.5:
		failures.append("高度直方图存在一百八十米周期的明显尖峰。")
	var durations: Array[float] = []
	var checksum: float = 0.0
	for repeat: int in 6:
		var started: int = Time.get_ticks_usec()
		for point: Vector3 in points:
			checksum += noise.height(point)
		if repeat > 0:
			durations.append(float(Time.get_ticks_usec() - started) / points.size())
	durations.sort()
	var baseline: Variant = null
	var baseline_path: String = "res://../test-output/terrain/height-before.json"
	if FileAccess.file_exists(baseline_path):
		baseline = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))["median_us"]
		if durations[2] > float(baseline):
			failures.append("高度查询慢于本机改动前基线。")
	return {"passed": failures.is_empty(), "failures": failures, "seams": seams, "spawn_samples": spawn_samples, "spawn_error_m": spawn_error, "spawn_final_error_m": final_spawn_error, "land_samples": land_samples, "steep_samples": steep_samples, "steep_ratio": steep_ratio, "histogram_180m": histogram, "histogram_peak_ratio": spike, "query_us": durations[2], "baseline_us": baseline, "checksum": checksum, "metadata": field.metadata}


static func _normal(field: DawnHeightfield, point: Vector3, forward: Vector3, right: Vector3) -> Vector3:
	var a: float = field.sample((point * 40000.0 + forward * 2.0).normalized()) - field.sample((point * 40000.0 - forward * 2.0).normalized())
	var b: float = field.sample((point * 40000.0 + right * 2.0).normalized()) - field.sample((point * 40000.0 - right * 2.0).normalized())
	return (point - forward * a / 4.0 - right * b / 4.0).normalized()


static func _seams(field: DawnHeightfield) -> Dictionary:
	var height_error: float = 0.0
	var normal_angle: float = 0.0
	var pairs: Dictionary = {}
	for face: int in 6:
		for edge: int in 4:
			for sample: int in range(1, 65):
				var along: float = sample / 33.0 - 1.0
				var u: float = along if edge < 2 else (-1.0 if edge == 2 else 1.0)
				var v: float = (-1.0 if edge == 0 else 1.0) if edge < 2 else along
				var offset: Vector3 = Vector3(PlanetTerrain.FACES[face][2 if edge < 2 else 1]) * 0.000001
				var point: Vector3 = HydrologyData.corner(face, u, v)
				var a: Vector3 = (point + offset).normalized()
				var b: Vector3 = (point - offset).normalized()
				var fa: int = int(field.coordinates(a).z)
				var fb: int = int(field.coordinates(b).z)
				pairs[Vector2i(mini(fa, fb), maxi(fa, fb))] = true
				height_error = maxf(height_error, absf(field.sample(a) - field.sample(b)))
				var forward: Vector3 = SurfaceSites.tangent_forward(point)
				var right: Vector3 = forward.cross(point).normalized()
				var na: Vector3 = _normal(field, a, forward, right)
				var nb: Vector3 = _normal(field, b, forward, right)
				normal_angle = maxf(normal_angle, rad_to_deg(na.angle_to(nb)))
	return {"height_m": height_error, "normal_degrees": normal_angle, "edge_pairs": pairs.size(), "samples": 6 * 4 * 64}
