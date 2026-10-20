class_name VerificationMetrics
extends RefCounted


static func summarize(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	return {
		"mean": total / float(sorted.size()),
		"p95": sorted[clampi(ceili(float(sorted.size()) * 0.95) - 1, 0, sorted.size() - 1)],
		"p99": sorted[clampi(ceili(float(sorted.size()) * 0.99) - 1, 0, sorted.size() - 1)],
		"maximum": sorted.back(),
	}


static func write_json(path: String, contents: Dictionary) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(contents, "\t"))
	file.close()
	return OK


# 验收范围由入口指定，不改变正常游戏中的星球和场景。
static func dawn_only() -> bool:
	return OS.get_cmdline_user_args().has("--scope=dawn")


static func planets(tree: SceneTree) -> Array[Planet]:
	var result: Array[Planet] = []
	for node: Node in tree.get_nodes_in_group("planets"):
		var planet: Planet = node as Planet
		if not dawn_only() or planet.profile == 0:
			result.append(planet)
	return result
