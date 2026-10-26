extends SceneTree


func _initialize() -> void:
	var source_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source_path = argument.trim_prefix("--source=")
	if source_path.is_empty() or FileAccess.file_exists(SpawnWaterBake.PATH):
		push_error("保护水系只能从改动前资源初始化一次；必须传入 --source，且目标文件尚不存在。")
		quit(1)
		return
	var source: HydrologyData = load(source_path) as HydrologyData
	if source == null or int(source.statistics.get("grid_cells", 0)) != 6 * 384 * 384:
		push_error("保护水系来源必须是第一版 384 格水系。")
		quit(1)
		return
	var spawn: Vector3 = source.metadata["site"]["direction"]
	var excluded: Dictionary = {}
	for river: int in source.river_starts.size() - 1:
		var near: bool = false
		for index: int in range(source.river_starts[river], source.river_starts[river + 1]):
			near = near or spawn.angle_to(source.river_points[index]) * source.planet_radius < SpawnWaterBake.MARGIN
		if not near:
			excluded[river] = true
	var result: HydrologyData = HydrologyData.new()
	result.river_starts.append(0)
	SpawnWaterBake._append_rivers(result, source, excluded)
	result.lake_starts.append(0)
	for lake: int in source.lake_levels.size():
		var near: bool = false
		for cursor: int in range(source.lake_starts[lake], source.lake_starts[lake + 1]):
			near = near or spawn.angle_to(HydrologyData.direction_at(source.lake_cells[cursor], 384)) * source.planet_radius < SpawnWaterBake.MARGIN
		if not near:
			continue
		for cursor: int in range(source.lake_starts[lake], source.lake_starts[lake + 1]):
			var cell: int = source.lake_cells[cursor]
			var face: int = cell / (384 * 384)
			var x: int = cell % 384
			var y: int = (cell / 384) % 384
			for dx: int in 2:
				for dy: int in 2:
					result.lake_cells.append(face * HydrologyData.GRID * HydrologyData.GRID + (y * 2 + dy) * HydrologyData.GRID + x * 2 + dx)
		result.lake_levels.append(source.lake_levels[lake])
		result.lake_starts.append(result.lake_cells.size())
	result.metadata = {"source_sha256": FileAccess.get_sha256(source_path), "source_commit": "e5401e8", "source_grid": 384, "preserved_radius_m": 2000.0, "selection_margin_m": SpawnWaterBake.MARGIN}
	# 原道路整地也属于出生区外观；只保留邻近路段，避免保存整套旧文明摆设。
	result.civilization = CivilizationData.new()
	result.civilization.town = source.civilization.town.duplicate(true)
	result.civilization.ladder = source.civilization.ladder.duplicate(true)
	for road: Dictionary in source.civilization.roads:
		var points: PackedVector3Array = road["points"]
		var first: int = -1
		var last: int = -1
		for index: int in points.size():
			if spawn.angle_to(points[index]) * source.planet_radius < SpawnWaterBake.MARGIN:
				first = maxi(0, index - 1) if first < 0 else first
				last = mini(points.size() - 1, index + 1)
		if first < 0:
			continue
		var clipped: Dictionary = {"name": road["name"], "width": road["width"]}
		for property: String in ["points", "levels", "terrain_levels", "wear"]:
			if road.has(property):
				clipped[property] = road[property].slice(first, last + 1)
		result.civilization.roads.append(clipped)
	var error: Error = ResourceSaver.save(result, SpawnWaterBake.PATH, ResourceSaver.FLAG_COMPRESS)
	print("保护水系：", result.river_starts.size() - 1, " 条河，", result.lake_levels.size(), " 个湖，保存结果 ", error)
	quit(0 if error == OK else 1)
