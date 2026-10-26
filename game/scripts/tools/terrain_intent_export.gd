extends SceneTree

const SIZE: int = 512
const PATCH_SIZE: int = 769
const PATCH_STEP: float = 8.0
const OUTPUT: String = "res://../test-output/terrain/intent/"
var _noise: TerrainNoise
var _source: TerrainIntent


func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var started: int = Time.get_ticks_msec()
	_source = TerrainIntent.new()
	_noise = _source._noise
	var layout: HydrologyData = load("res://data/dawn_layout.tres") as HydrologyData
	var metadata: Dictionary = layout.metadata.duplicate(true)
	metadata.erase("climbs")
	var forms: DawnLandforms = DawnLandforms.new(metadata["landforms"], _noise.radius, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for face: int in 6:
		var heights: PackedFloat32Array = []
		var masks: PackedFloat32Array = []
		for y: int in SIZE:
			for x: int in SIZE:
				var direction: Vector3 = HydrologyData.corner(face, float(x) * 2.0 / (SIZE - 1) - 1.0, float(y) * 2.0 / (SIZE - 1) - 1.0)
				heights.append(_source.low_frequency(direction))
				var near: Vector3 = forms.nearest(direction)
				var canyon: Vector3 = forms.nearest(direction, true)
				masks.append(1.0 - smoothstep(0.0, 9000.0, near.x))
				masks.append(1.0 - smoothstep(110.0, 2200.0, canyon.x))
				var lateral: Vector3 = (Vector3(metadata["axis_u"]) * float(metadata["volcano"].x) + Vector3(metadata["axis_v"]) * float(metadata["volcano"].y)) / _noise.radius
				var volcano_direction: Vector3 = (Vector3(metadata["center"]) * sqrt(1.0 - lateral.length_squared()) + lateral).normalized()
				masks.append(1.0 - smoothstep(0.0, 2200.0, direction.distance_to(volcano_direction) * _noise.radius))
				masks.append(1.0 - smoothstep(2000.0, 3000.0, direction.distance_to(metadata["site"]["direction"]) * _noise.radius))
		FileAccess.open(OUTPUT + "base-%d.f32" % face, FileAccess.WRITE).store_buffer(heights.to_byte_array())
		FileAccess.open(OUTPUT + "masks-%d.f32" % face, FileAccess.WRITE).store_buffer(masks.to_byte_array())
		print("意图导出：面 %d/6" % (face + 1))
	var patch: PackedFloat32Array = []
	var spawn: Vector3 = metadata["site"]["direction"]
	var forward: Vector3 = metadata["site"]["forward"]
	var right: Vector3 = forward.cross(spawn).normalized()
	for y: int in PATCH_SIZE:
		for x: int in PATCH_SIZE:
			var direction: Vector3 = (spawn * _noise.radius + right * (x - PATCH_SIZE / 2) * PATCH_STEP + forward * (y - PATCH_SIZE / 2) * PATCH_STEP).normalized()
			patch.append(_source.original_height(direction))
	FileAccess.open(OUTPUT + "spawn-original.f32", FileAccess.WRITE).store_buffer(patch.to_byte_array())
	metadata["grid"] = SIZE
	metadata["radius"] = _noise.radius
	metadata["seed"] = _noise.planet_seed
	metadata["spawn_patch"] = {"size": PATCH_SIZE, "step": PATCH_STEP, "forward": forward, "right": right}
	metadata["export_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	# 时间不参与内容哈希；所有几何、噪声参数与输入数组均由烘焙工具签名。
	FileAccess.open(OUTPUT + "layout.json", FileAccess.WRITE).store_string(JSON.stringify(_json(metadata), "  "))
	print("意图导出完成：%.2f 秒" % metadata["export_seconds"])
	quit()


func _json(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _json(value[key])
		return result
	if value is Array or value is PackedVector3Array or value is PackedFloat32Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json(item))
		return result
	return value
