class_name TerrainNoise
extends RefCounted

const MAX_HEIGHT: float = 4300.0

var radius: float
var profile: int = 0
var planet_seed: int = 0
# 晨的河道、文明区与洞穴；其他星球为空。
var features: TerrainFeatures
var heightfield: DawnHeightfield
var _continent: FastNoiseLite
var _mountain: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _moisture: FastNoiseLite
var _groves: FastNoiseLite
var _drainage: FastNoiseLite
var _geology: FastNoiseLite


func _init(planet_seed_value: int, planet_radius: float, terrain_profile: int = 0, include_features: bool = true, include_heightfield: bool = true) -> void:
	radius = planet_radius
	profile = terrain_profile
	planet_seed = planet_seed_value
	_continent = _make(planet_seed_value, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 14000.0, FastNoiseLite.FRACTAL_FBM, 4)
	_mountain = _make(planet_seed_value + 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 5200.0, FastNoiseLite.FRACTAL_RIDGED, 4)
	_mountain.fractal_gain = 0.42
	_hills = _make(planet_seed_value + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 700.0, FastNoiseLite.FRACTAL_FBM, 3)
	_detail = _make(planet_seed_value + 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 90.0, FastNoiseLite.FRACTAL_FBM, 2)
	_moisture = _make(planet_seed_value + 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 3400.0, FastNoiseLite.FRACTAL_FBM, 3)
	_groves = _make(planet_seed_value + 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 280.0, FastNoiseLite.FRACTAL_FBM, 2)
	_drainage = _make(planet_seed_value + 6, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 2100.0, FastNoiseLite.FRACTAL_FBM, 3)
	_geology = _make(planet_seed_value + 7, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 4800.0, FastNoiseLite.FRACTAL_FBM, 3)
	if profile == 0 and include_heightfield:
		heightfield = DawnHeightfield.shared()
		assert(heightfield != null, "晨高度场缺失，请执行 tools/Bake-Terrain.py。")
	if profile == 0 and include_features:
		features = TerrainFeatures.for_noise(self)


func _make(seed_value: int, noise_type: FastNoiseLite.NoiseType, frequency: float, fractal: FastNoiseLite.FractalType, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise


# 网格、碰撞、贴地保护共用高度函数，避免表面位置出现差异。
func height(direction: Vector3) -> float:
	var base: float = base_height(direction)
	return features.apply(direction, base) if features != null else base


# 基础高度不含河道、文明区和洞穴；晨的大尺度地貌已经烘焙。
func base_height(direction: Vector3) -> float:
	if profile == 0:
		var detail: float = _detail.get_noise_3dv(direction * radius) * 0.35
		# 八米保护样本已包含原有细节，不在出生区重复增加噪声。
		if direction.dot(heightfield.spawn) > DawnHeightfield.SPAWN_ALIGNMENT:
			detail *= smoothstep(DawnHeightfield.SPAWN_CORE, DawnHeightfield.SPAWN_BLEND_END, direction.distance_to(heightfield.spawn) * radius)
		return heightfield.sample(direction) + detail
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
	return 0.0


func landform(direction: Vector3) -> String:
	var elevation: float = height(direction)
	var point: Vector3 = direction * radius
	var geology: float = _geology.get_noise_3dv(point) * 0.5 + 0.5
	if elevation < 0.0:
		return "海洋"
	var water: String = water_body(direction)
	if not water.is_empty():
		return water
	if features != null and features.volcano != Vector2.INF and features.contains(direction) and features.plane(direction).distance_to(features.volcano) < features.volcano_radius * 0.75:
		return "火山"
	if elevation < 12.0:
		return "沙滩"
	if elevation > 1600.0:
		return "雪岭"
	if elevation > 500.0 and absf(_drainage.get_noise_3dv(point)) < 0.07:
		return "峡谷"
	if elevation > 300.0 and geology > 0.58:
		return "台地"
	if elevation > 700.0:
		return "山地"
	if elevation < 150.0 and moisture(direction) > 0.70:
		return "湿润低地"
	if elevation < 300.0 and geology < 0.33:
		return "盆地"
	return "丘陵" if elevation > 180.0 else "平原"


func moisture(direction: Vector3) -> float:
	return clampf(0.52 + _moisture.get_noise_3dv(direction * radius) * 1.1, 0.0, 1.0)


func biome(direction: Vector3) -> String:
	var elevation: float = height(direction)
	return DawnBiomes.classify(elevation, temperature(direction, elevation), moisture(direction), woodland(direction))


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


# 河面或湖面水位；不在样板区的河湖里时返回负无穷。
func water_surface(direction: Vector3, elevation: float = INF) -> float:
	var level: float = features.water_surface(direction) if features != null else -INF
	if level > -INF:
		var ground: float = height(direction) if elevation == INF else elevation
		return level if ground < level else -INF
	return -INF


func water_body(direction: Vector3) -> String:
	return features.water_body(direction) if features != null and water_surface(direction) > -INF else ""


func river_distance(direction: Vector3) -> float:
	return features.river_distance(direction) if features != null else INF
