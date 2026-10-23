class_name HydrologyData
extends Resource

const GRID: int = 384 # 每个立方体面的水系格网边长。
const BUCKET_GRID: int = 64 # 每面的索引桶边长。
const CARVE_GRID: int = 256 # 高度查询使用细索引，避免遍历整公里桶内的河段。
const RIVER_AREA: float = 3000000.0 # 河流最小汇水面积，平方米。
const LAKE_AREA: float = 120000.0 # 湖泊最小面积，平方米。
const LAKE_DEPTH: float = 4.0 # 湖泊最小深度，米。
const PATH: String = "res://data/dawn_world.res"

@export var version: int = 1
@export var planet_seed: int = 20261019
@export var planet_radius: float = 40000.0
@export var signature: String
@export var metadata: Dictionary
@export var river_points: PackedVector3Array
@export var river_levels: PackedFloat32Array
@export var river_widths: PackedFloat32Array
@export var river_flags: PackedByteArray
@export var river_starts: PackedInt32Array
@export var river_ends: PackedInt32Array
@export var river_joins: PackedInt32Array
@export var lake_levels: PackedFloat32Array
@export var lake_cells: PackedInt32Array
@export var lake_starts: PackedInt32Array
@export var bucket_offsets: PackedInt32Array
@export var bucket_segments: PackedInt32Array
@export var carve_offsets: PackedInt32Array
@export var carve_segments: PackedInt32Array
@export var volcanoes: Array[Dictionary]
@export var karst_pillars: PackedVector4Array
@export var karst_sizes: PackedVector2Array
@export var hot_springs: PackedVector4Array
@export var statistics: Dictionary
@export var civilization: CivilizationData


static func source_signature() -> String:
	# 源文件与所有烘焙算法共同签名；调整阈值或算法后必须重新烘焙。
	var text: String = ""
	for path: String in ["res://scripts/planet/terrain_noise.gd", "res://scripts/planet/terrain_features.gd", "res://scripts/planet/hydrology_data.gd", "res://scripts/tools/world_bake.gd", "res://data/dawn_layout.tres"]:
		text += path + "\n" + FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	for path: String in ["res://scripts/civilization/dawn_landforms.gd", "res://scripts/civilization/landform_layout.gd"]:
		text += path + "\n" + FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	for path: String in ["civilization_data", "civilization_siting", "civilization_terrain", "civilization_paths", "civilization_bake", "civilization_buildings"]:
		text += FileAccess.get_file_as_string("res://scripts/civilization/" + path + ".gd").replace("\r\n", "\n")
	text += FileAccess.get_file_as_string("res://scripts/civilization/beacon_bake.gd").replace("\r\n", "\n")
	for path: String in ["res://scripts/civilization/echo_anchors.gd", "res://scripts/player/landing_pads.gd", "res://scenes/main.tscn"]:
		text += FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	return text.md5_text()


static func direction_at(cell: int, size: int = GRID) -> Vector3:
	var face: int = cell / (size * size)
	var x: int = cell % size
	var y: int = (cell / size) % size
	return corner(face, (float(x) + 0.5) * 2.0 / size - 1.0, (float(y) + 0.5) * 2.0 / size - 1.0)


static func corner(face: int, u: float, v: float) -> Vector3:
	var axes: Array = PlanetTerrain.FACES[face]
	return (Vector3(axes[0]) + Vector3(axes[1]) * u + Vector3(axes[2]) * v).normalized()


static func cell_at(direction: Vector3, size: int = GRID) -> int:
	var face: int
	var absolute: Vector3 = direction.abs()
	var normal: Vector3
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		normal = Vector3.RIGHT if direction.x > 0.0 else Vector3.LEFT
	elif absolute.y >= absolute.z:
		normal = Vector3.UP if direction.y > 0.0 else Vector3.DOWN
	else:
		normal = Vector3.BACK if direction.z > 0.0 else Vector3.FORWARD
	for index: int in 6:
		if PlanetTerrain.FACES[index][0] == normal:
			face = index
			break
	var axes: Array = PlanetTerrain.FACES[face]
	var divisor: float = direction.dot(axes[0])
	var x: int = clampi(floori((direction.dot(axes[1]) / divisor + 1.0) * 0.5 * size), 0, size - 1)
	var y: int = clampi(floori((direction.dot(axes[2]) / divisor + 1.0) * 0.5 * size), 0, size - 1)
	return face * size * size + y * size + x


func lake_coverage() -> Dictionary:
	var result: Dictionary = {}
	for lake: int in lake_levels.size():
		for cursor: int in range(lake_starts[lake], lake_starts[lake + 1]):
			result[lake_cells[cursor]] = lake
	var original: Array = result.keys()
	for cell: int in original:
		var face: int = cell / (GRID * GRID)
		var x: int = cell % GRID
		var y: int = (cell / GRID) % GRID
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				var neighbor: int = cell_at(corner(face, (float(x + dx) + 0.5) * 2.0 / GRID - 1.0, (float(y + dy) + 0.5) * 2.0 / GRID - 1.0))
				if not result.has(neighbor):
					result[neighbor] = result[cell]
	return result
