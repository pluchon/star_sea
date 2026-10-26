extends SceneTree


func _initialize() -> void:
	var folder: String = "res://../test-output/terrain/baked/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--terrain-input="):
			folder = argument.trim_prefix("--terrain-input=").trim_suffix("/") + "/"
	var data: DawnHeightfield = DawnHeightfield.new()
	data.metadata = JSON.parse_string(FileAccess.get_file_as_string(folder + "metadata.json"))
	# 耗时只留在自测报告；相同输入必须生成相同的游戏资源。
	data.metadata.erase("seconds")
	data.metadata.erase("total_seconds")
	data.grid = int(data.metadata["grid"])
	var patch: Dictionary = data.metadata["spawn_patch"]
	data.spawn = Vector3(patch["direction"][0], patch["direction"][1], patch["direction"][2])
	data.spawn_forward = Vector3(patch["forward"][0], patch["forward"][1], patch["forward"][2])
	data.spawn_right = Vector3(patch["right"][0], patch["right"][1], patch["right"][2])
	data.spawn_size = int(patch["size"])
	data.spawn_step = float(patch["step"])
	data.spawn_heights = FileAccess.get_file_as_bytes(folder + "spawn-original.u16")
	if data.spawn_heights.size() != data.spawn_size * data.spawn_size * 2 or FileAccess.get_sha256(folder + "spawn-original.u16") != patch["sha256"]:
		push_error("出生区高度数据长度或签名不正确。")
		quit(1)
		return
	for face: int in 6:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(folder + "height-%d.u16" % face)
		if bytes.size() != (data.grid + 4) * (data.grid + 4) * 2:
			push_error("高度场面数据长度不正确：%d" % face)
			quit(1)
			return
		data.faces.append(bytes)
		var collapsed: PackedByteArray = FileAccess.get_file_as_bytes(folder + "collapse-%d.u8" % face)
		if collapsed.size() != (data.grid / 4) * (data.grid / 4):
			push_error("坍塌遮罩长度不正确：%d" % face)
			quit(1)
			return
		data.collapse.append(collapsed)
	_reconcile_collapse(data)
	data.metadata["packing_sha256"] = FileAccess.get_sha256("res://scripts/tools/terrain_pack.gd")
	var error: Error = ResourceSaver.save(data, DawnHeightfield.PATH, ResourceSaver.FLAG_COMPRESS)
	print("高度场保存：%s，%d 字节" % [error_string(error), FileAccess.get_file_as_bytes(DawnHeightfield.PATH).size()])
	quit(0 if error == OK else 1)


# 遮罩也要共享立方体棱上的样本，避免岩层偏移在跨面时产生跳变。
func _reconcile_collapse(data: DawnHeightfield) -> void:
	var size: int = data.grid / 4
	var nodes: Dictionary = {}
	var seen: Dictionary = {}
	for face: int in 6:
		for edge: int in 4:
			for index: int in size:
				var x: int = index if edge < 2 else (0 if edge == 2 else size - 1)
				var y: int = (0 if edge == 0 else size - 1) if edge < 2 else index
				var node: int = face * size * size + y * size + x
				if seen.has(node):
					continue
				seen[node] = true
				var direction: Vector3 = HydrologyData.corner(face, x * 2.0 / (size - 1) - 1.0, y * 2.0 / (size - 1) - 1.0)
				var uv: Vector3 = data.coordinates(direction)
				var shared_x: int = roundi((uv.x - 2) / (data.grid - 1) * (size - 1))
				var shared_y: int = roundi((uv.y - 2) / (data.grid - 1) * (size - 1))
				var shared: int = int(uv.z) * size * size + shared_y * size + shared_x
				if not nodes.has(shared):
					nodes[shared] = []
				nodes[shared].append(node)
	var updates: Array[Dictionary] = [{}, {}, {}, {}, {}, {}]
	for copies: Array in nodes.values():
		var sum: float = 0.0
		for node: int in copies:
			sum += data.collapse[node / (size * size)][node % (size * size)]
		var value: int = roundi(sum / copies.size())
		for node: int in copies:
			updates[node / (size * size)][node % (size * size)] = value
	for face: int in 6:
		var bytes: PackedByteArray = data.collapse[face].duplicate()
		for offset: int in updates[face]:
			bytes[offset] = updates[face][offset]
		data.collapse[face] = bytes
