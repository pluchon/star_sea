class_name TerrainFeatures
extends RefCounted

# 高度、地图、碰撞与植被共同读取离线水系；运行时不改变共享地形数据。
const HALF_SIZE: float = 9000.0
static var _cache: Dictionary = {}
static var _cache_mutex: Mutex = Mutex.new()
var radius: float
var site: Dictionary
var center: Vector3
var axis_u: Vector3
var axis_v: Vector3
var volcano: Vector2 = Vector2.INF
var volcano_height: float = 760.0
var volcano_radius: float = 2000.0
var crater_radius: float = 280.0
var crater_depth: float = 115.0
var volcano_base: float = 0.0
var landmarks: Array[Dictionary] = []
var hydrology: GlobalHydrology
var landforms: DawnLandforms
var protected_spawn: Vector3
var civilization: CivilizationTerrain
var protected_civilization: CivilizationTerrain
var caves: CaveData


static func for_noise(noise: TerrainNoise) -> TerrainFeatures:
	var key: String = "%d/%.1f" % [noise.planet_seed, noise.radius]
	_cache_mutex.lock()
	var features: TerrainFeatures = _cache.get(key) as TerrainFeatures
	if features == null:
		features = TerrainFeatures.new()
		features.radius = noise.radius
		var data: HydrologyData = load(HydrologyData.PATH) as HydrologyData
		if data == null or data.version != HydrologyData.VERSION or int(data.statistics.get("grid_cells", 0)) != 6 * HydrologyData.GRID * HydrologyData.GRID or data.planet_seed != noise.planet_seed or not is_equal_approx(data.planet_radius, noise.radius):
			_cache_mutex.unlock()
			push_error("全球水系数据缺失或版本不兼容，请执行 tools/Bake-World.ps1。")
			(Engine.get_main_loop() as SceneTree).quit(1)
			return features
		features.site = data.metadata["site"]
		features.protected_spawn = features.site["direction"]
		var protected: HydrologyData = load(SpawnWaterBake.PATH) as HydrologyData
		features.protected_civilization = CivilizationTerrain.new(protected.civilization, noise.radius)
		features.center = data.metadata["center"]
		features.axis_u = data.metadata["axis_u"]
		features.axis_v = data.metadata["axis_v"]
		features.volcano = data.metadata["volcano"]
		features.volcano_base = data.metadata["volcano_base"]
		features.landmarks.assign(data.metadata["landmarks"])
		features.landforms = DawnLandforms.new(data.metadata.get("landforms", {}), noise.radius)
		features.hydrology = GlobalHydrology.new(data, noise.radius)
		if data.civilization != null:
			features.civilization = CivilizationTerrain.new(data.civilization, noise.radius)
		if ResourceLoader.exists(CaveData.PATH):
			features.caves = load(CaveData.PATH) as CaveData
			features.caves.prepare()
		_cache[key] = features
	_cache_mutex.unlock()
	return features


func plane(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(axis_u), direction.dot(axis_v)) * radius


func direction_at(point: Vector2) -> Vector3:
	var lateral: Vector3 = (axis_u * point.x + axis_v * point.y) / radius
	return (lateral + center * sqrt(maxf(1.0 - lateral.length_squared(), 0.0))).normalized()


# 此范围只用于火山标记与上升气流，全球地形和水系查询不受此范围限制。
func contains(direction: Vector3) -> bool:
	if direction.dot(center) < 0.94:
		return false
	var point: Vector2 = plane(direction)
	return absf(point.x) <= HALF_SIZE and absf(point.y) <= HALF_SIZE


func apply(direction: Vector3, base: float) -> float:
	var height: float = base
	# 出发地两公里内不受新地貌影响；热路径直接判断，避免额外的曲线查询。
	if landforms != null and direction.dot(protected_spawn) < 0.99875026:
		height = landforms.height(direction, base)
	height = hydrology.carve(direction, height)
	var old_height: float = height
	var protected_weight: float = 1.0
	if protected_civilization != null and direction.dot(protected_spawn) > DawnHeightfield.SPAWN_ALIGNMENT:
		protected_weight = smoothstep(DawnHeightfield.SPAWN_CORE, DawnHeightfield.SPAWN_BLEND_END, direction.distance_to(protected_spawn) * radius)
		old_height = protected_civilization.apply(direction, height, hydrology)
	if civilization != null:
		height = civilization.apply(direction, height, hydrology)
	if protected_weight < 1.0:
		height = lerpf(old_height, height, protected_weight)
	return caves.apply(direction, radius, height) if caves != null else height


func in_hole(position: Vector3) -> bool:
	return caves != null and caves.in_hole(position)


func ground_height(direction: Vector3, base: float) -> float:
	return landforms.height(direction, base) if landforms != null else base


func surface_marks(direction: Vector3, elevation: float, slope: float) -> Color:
	return landforms.surface_marks(direction, elevation, slope) if landforms != null else Color(0, 0, 0, 0)


func water_surface(direction: Vector3) -> float:
	return hydrology.water_surface(direction)


func water_body(direction: Vector3) -> String:
	return hydrology.water_body(direction)


func river_distance(direction: Vector3) -> float:
	var nearest: Vector4 = hydrology.nearest(direction)
	return nearest.x - nearest.z if nearest.w >= 0.0 else INF


func in_clearing(direction: Vector3) -> bool:
	if civilization != null and civilization.in_clearing(direction):
		return true
	if not contains(direction):
		return false
	var point: Vector2 = plane(direction)
	for landmark: Dictionary in landmarks:
		if point.distance_to(landmark["point"]) < landmark["clearance"]:
			return true
	return false


func height_at(noise: TerrainNoise, point: Vector2) -> float:
	var direction: Vector3 = direction_at(point)
	return apply(direction, noise.base_height(direction))


func updraft_at(direction: Vector3, altitude: float) -> float:
	var lift: float = 0.0
	if civilization != null and altitude >= 18.0 and altitude < 100.0:
		for tower: Dictionary in civilization.data.beacons:
			if direction.distance_to(tower["direction"]) * radius < 18.0:
				lift = maxf(lift, 4.5 * (1.0 - maxf(altitude - 25.0, 0.0) / 75.0))
	if landforms != null and altitude >= 0.0 and altitude < 150.0:
		if landforms.nearest(direction).x < 600.0:
			lift = 4.0 * (1.0 - altitude / 150.0)
		var canyon: Vector3 = landforms.nearest(direction, true)
		if canyon.x < DawnLandforms.CANYON_HALF_WIDTH and canyon.x > DawnLandforms.CANYON_HALF_WIDTH - 150.0:
			lift = maxf(lift, 4.0 * (1.0 - altitude / 150.0))
	if altitude >= 0.0 and altitude < 200.0 and contains(direction) and plane(direction).distance_to(volcano) < crater_radius:
		lift = maxf(lift, 5.0 * (1.0 - altitude / 200.0))
	return lift
