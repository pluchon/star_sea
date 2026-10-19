class_name TerrainNoise
extends RefCounted

const MAX_HEIGHT: float = 2600.0

var radius: float
var profile: int = 0
var _continent: FastNoiseLite
var _mountain: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _moisture: FastNoiseLite
var _groves: FastNoiseLite
var _drainage: FastNoiseLite


func _init(planet_seed: int, planet_radius: float, terrain_profile: int = 0) -> void:
	radius = planet_radius
	profile = terrain_profile
	_continent = _make(planet_seed, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 14000.0, FastNoiseLite.FRACTAL_FBM, 4)
	_mountain = _make(planet_seed + 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 5200.0, FastNoiseLite.FRACTAL_RIDGED, 4)
	_mountain.fractal_gain = 0.42
	_hills = _make(planet_seed + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 700.0, FastNoiseLite.FRACTAL_FBM, 3)
	_detail = _make(planet_seed + 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 90.0, FastNoiseLite.FRACTAL_FBM, 2)
	_moisture = _make(planet_seed + 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 3400.0, FastNoiseLite.FRACTAL_FBM, 3)
	_groves = _make(planet_seed + 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 280.0, FastNoiseLite.FRACTAL_FBM, 2)
	_drainage = _make(planet_seed + 6, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 2100.0, FastNoiseLite.FRACTAL_FBM, 3)


func _make(planet_seed: int, noise_type: FastNoiseLite.NoiseType, frequency: float, fractal: FastNoiseLite.FractalType, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = planet_seed
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise


# 网格、碰撞、贴地保护共用高度函数，避免表面位置出现差异。
func height(direction: Vector3) -> float:
	var point: Vector3 = direction * radius
	var continent: float = _continent.get_noise_3dv(point)
	var land: float = smoothstep(-0.35, 0.0, continent)
	var mountain_mask: float = smoothstep(0.10, 0.60, continent)
	var ridge: float = (_mountain.get_noise_3dv(point) + 1.0) * 0.5
	var mountain: float = pow(ridge, 1.65) * mountain_mask * 2100.0
	var upland: float = smoothstep(-0.02, 0.60, continent) * 340.0
	var foothills: float = absf(_hills.get_noise_3dv(point * 0.28)) * 260.0 * smoothstep(-0.12, 0.28, continent)
	var hills: float = _hills.get_noise_3dv(point) * 75.0 * land
	var detail: float = _detail.get_noise_3dv(point) * 1.8
	if profile == 1:
		# 沙丘沿固定风向排列，底部圆缓、背风面较陡；台地单独受大陆尺度控制。
		var phase: float = point.dot(Vector3(0.73, 0.21, 0.65)) / 180.0 + _hills.get_noise_3dv(point * 0.3) * 2.0
		var dunes: float = pow(0.5 + sin(phase) * 0.5, 2.4) * 38.0
		var plateau: float = smoothstep(0.04, 0.48, continent) * 1100.0
		return 45.0 + plateau + mountain * 0.45 + dunes + detail * 0.4
	if profile == 2:
		# 冰原保留宽阔盆地，以相互连接的山脊区分于海岸和沙丘。
		var basin: float = smoothstep(-0.25, 0.42, continent)
		return 24.0 + basin * 400.0 + pow(ridge, 2.0) * basin * 1900.0 + hills * 0.35 + detail * 0.5
	# 高地沟谷使用连续等值线下切，海岸与低地不受影响；三种地形查询仍共用本函数。
	var valley: float = 1.0 - smoothstep(0.015, 0.13, absf(_drainage.get_noise_3dv(point)))
	var erosion: float = valley * smoothstep(150.0, 900.0, mountain + upland) * 120.0
	return lerpf(-420.0, 40.0, land) + upland + mountain + foothills + hills + detail - erosion


func moisture(direction: Vector3) -> float:
	return clampf(0.52 + _moisture.get_noise_3dv(direction * radius) * 1.1, 0.0, 1.0)


func temperature(direction: Vector3, elevation: float) -> float:
	return clampf(1.05 - absf(direction.y) * 0.72 - maxf(elevation, 0.0) / 2800.0, 0.0, 1.0)


func woodland(direction: Vector3) -> float:
	return smoothstep(-0.22, 0.28, _groves.get_noise_3dv(direction * radius))


func slope(direction: Vector3, elevation: float) -> float:
	var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
	var right: Vector3 = tangent.cross(direction)
	var a: float = height((direction * radius + tangent * 4.0).normalized()) - elevation
	var b: float = height((direction * radius + right * 4.0).normalized()) - elevation
	return sqrt(a * a + b * b) / 4.0
