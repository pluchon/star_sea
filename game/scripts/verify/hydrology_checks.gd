extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var failures: Array[String] = []
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0)
	var data: HydrologyData = noise.features.hydrology.data
	if data.signature != HydrologyData.source_signature():
		failures.append("烘焙签名与当前源文件不一致。")
	var monotonic: bool = true
	var disconnected: int = 0
	var shared_points: Dictionary = {}
	for river: int in data.river_starts.size() - 1:
		for index: int in range(data.river_starts[river], data.river_starts[river + 1]):
			var key: Vector3i = Vector3i((data.river_points[index] * noise.radius * 0.5).round())
			if not shared_points.has(key):
				shared_points[key] = river
			elif int(shared_points[key]) != river:
				shared_points[key] = -1
	for river: int in data.river_starts.size() - 1:
		var start: int = data.river_starts[river]
		var end: int = data.river_starts[river + 1] - 1
		for index: int in range(start + 1, end + 1):
			if data.river_levels[index] > data.river_levels[index - 1] + 0.001:
				monotonic = false
		var direction: Vector3 = data.river_points[end]
		var ground: float = noise.base_height(direction)
		if noise.features.contains(direction):
			ground = noise.features.with_volcano(noise.features.plane(direction), ground)
		var key: Vector3i = Vector3i((direction * noise.radius * 0.5).round())
		if ground >= 0.0 and noise.features.hydrology.lake_surface(direction) == -INF and shared_points.get(key, river) != -1:
			disconnected += 1
	if not monotonic:
		failures.append("河流水位沿下游升高。")
	if disconnected > 0:
		failures.append("%d 条河的末端没有连接海洋、湖泊或其他河流。" % disconnected)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 20261020
	var dry_centers: int = 0
	for sample: int in 2000:
		var index: int = random.randi_range(0, data.river_points.size() - 1)
		if noise.height(data.river_points[index]) >= data.river_levels[index] - 0.02:
			dry_centers += 1
	if dry_centers > 0:
		failures.append("%d 个河道中心未低于水位。" % dry_centers)
	var spawn: Vector3 = noise.features.site["direction"]
	var spawn_distance: float = noise.river_distance(spawn)
	if noise.water_surface(spawn) > -INF or spawn_distance < 60.0:
		failures.append("出发地受到全球水系影响。")
	var nearest_waterfall: float = INF
	for index: int in data.river_flags.size():
		if data.river_flags[index] & 1:
			nearest_waterfall = minf(nearest_waterfall, spawn.distance_to(data.river_points[index]) * noise.radius)
	if float(data.statistics["river_km"]) < 1500.0 or data.lake_levels.size() < 100 or int(data.statistics["waterfalls"]) < 20 or nearest_waterfall > 20000.0:
		failures.append("全球水系规模或附近瀑布数量未达到规格。")
	var directions: PackedVector3Array = []
	var forward: Vector3 = noise.features.site["forward"]
	for index: int in 10000:
		directions.append(SurfaceSites.offset_direction(spawn, forward.rotated(spawn, random.randf_range(0.0, TAU)), random.randf_range(0.0, 1000.0), noise.radius))
	var started: int = Time.get_ticks_usec()
	var checksum: float = 0.0
	for iteration: int in 10:
		for direction: Vector3 in directions:
			checksum += noise.height(direction)
	var average: float = float(Time.get_ticks_usec() - started) / 100000.0
	if average > 6.0:
		failures.append("高度查询平均耗时 %.3f 微秒，超过 6 微秒。" % average)
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "statistics": data.statistics, "disconnected_rivers": disconnected, "dry_centers": dry_centers, "nearest_waterfall_m": nearest_waterfall, "spawn_river_distance_m": spawn_distance, "height_query_us": average, "checksum": checksum}
	VerificationMetrics.write_json("res://../test-output/wanderer/hydrology_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
