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


static func for_noise(noise: TerrainNoise) -> TerrainFeatures:
	var key: String = "%d/%.1f" % [noise.planet_seed, noise.radius]
	_cache_mutex.lock()
	var features: TerrainFeatures = _cache.get(key) as TerrainFeatures
	if features == null:
		features = TerrainFeatures.new()
		features.radius = noise.radius
		var data: HydrologyData = load(HydrologyData.PATH) as HydrologyData
		if data == null or data.version != 1 or data.planet_seed != noise.planet_seed or not is_equal_approx(data.planet_radius, noise.radius):
			_cache_mutex.unlock()
			push_error("全球水系数据缺失或版本不兼容，请执行 tools/Bake-World.ps1。")
			(Engine.get_main_loop() as SceneTree).quit(1)
			return features
		features.site = data.metadata["site"]
		features.center = data.metadata["center"]
		features.axis_u = data.metadata["axis_u"]
		features.axis_v = data.metadata["axis_v"]
		features.volcano = data.metadata["volcano"]
		features.volcano_base = data.metadata["volcano_base"]
		features.landmarks.assign(data.metadata["landmarks"])
		features.hydrology = GlobalHydrology.new(data, noise.radius)
		_cache[key] = features
	_cache_mutex.unlock()
	return features


func plane(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(axis_u), direction.dot(axis_v)) * radius


func direction_at(point: Vector2) -> Vector3:
	var lateral: Vector3 = (axis_u * point.x + axis_v * point.y) / radius
	return (lateral + center * sqrt(maxf(1.0 - lateral.length_squared(), 0.0))).normalized()


# 此范围只用于保留样板区火山，全球水系查询不受此范围限制。
func contains(direction: Vector3) -> bool:
	if direction.dot(center) < 0.94:
		return false
	var point: Vector2 = plane(direction)
	return absf(point.x) <= HALF_SIZE and absf(point.y) <= HALF_SIZE


func apply(direction: Vector3, base: float) -> float:
	var height: float = with_volcano(plane(direction), base) if contains(direction) else base
	return hydrology.carve(direction, height)


func with_volcano(point: Vector2, base: float) -> float:
	if volcano == Vector2.INF:
		return base
	var offset: Vector2 = point - volcano
	var distance: float = offset.length()
	if distance >= volcano_radius:
		return base
	# 山脚以内逐渐把地面压到火山中心的高度，山体和火山口都建在这个平面上。
	var ground: float = lerpf(base, volcano_base, smoothstep(volcano_radius, volcano_radius * 0.45, distance))
	if distance < crater_radius:
		# 火山口是一个碗形洼地，边缘保留一道略高的口沿。
		var bowl: float = 1.0 - pow(distance / crater_radius, 2.0)
		return ground + volcano_height - crater_depth * bowl + 6.0 * smoothstep(0.7, 1.0, distance / crater_radius)
	var slope: float = (volcano_radius - distance) / (volcano_radius - crater_radius)
	var cone: float = volcano_height * pow(slope, 1.45) + 6.0 * smoothstep(0.85, 1.0, slope)
	# 山腰的放射状冲沟，越靠山顶越明显，避免锥体像一个光滑的圆锥。
	var angle: float = atan2(offset.y, offset.x)
	var gully: float = 0.5 + 0.5 * sin(angle * 13.0 + sin(angle * 5.0) * 2.2)
	return ground + cone * (1.0 - 0.035 * gully * slope)



func water_surface(direction: Vector3) -> float:
	return hydrology.water_surface(direction)


func water_body(direction: Vector3) -> String:
	return hydrology.water_body(direction)


func river_distance(direction: Vector3) -> float:
	var nearest: Vector4 = hydrology.nearest(direction)
	return nearest.x - nearest.z if nearest.w >= 0.0 else INF


func in_clearing(direction: Vector3) -> bool:
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
