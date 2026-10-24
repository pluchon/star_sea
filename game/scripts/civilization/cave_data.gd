class_name CaveData
extends Resource

const PATH: String = "res://data/dawn_caves.res"
const BLOCK: float = 32.0 # 离线网格与运行时加载共用的分块边长，米。
const GATE_APRON_Z: float = -12.0 # 主入口平段外沿，与洞壁裁切共用，米。
@export var version: int = 1
@export var signature: String = ""
@export var networks: Array[Dictionary] = []
@export var chunks: Array[Dictionary] = []
@export var statistics: Dictionary = {}
var _indices: Array[Dictionary] = []


static func source_signature() -> String:
	var text: String = HydrologyData.source_signature()
	for name: String in ["cave_templates", "cave_bake", "cave_mesher", "cave_data"]:
		text += FileAccess.get_file_as_string("res://scripts/civilization/" + name + ".gd").replace("\r\n", "\n")
	return text.md5_text()


func prepare() -> void:
	# 只在发布到地形工作线程之前构建索引，此后保持只读。
	_indices.clear()
	for network: Dictionary in networks:
		var index: Dictionary = {}
		for primitive: Dictionary in network["primitives"]:
			var bounds: AABB = primitive["bounds"]
			var low: Vector3i = Vector3i((bounds.position / BLOCK).floor())
			var high: Vector3i = Vector3i((bounds.end / BLOCK).floor())
			for x: int in range(low.x, high.x + 1):
				for y: int in range(low.y, high.y + 1):
					for z: int in range(low.z, high.z + 1):
						var key: Vector3i = Vector3i(x, y, z)
						if not index.has(key):
							index[key] = []
						index[key].append(primitive)
		_indices.append(index)


func cave_at(position: Vector3) -> int:
	for id: int in networks.size():
		var network: Dictionary = networks[id]
		var p: Vector3 = Transform3D(network["frame"]).affine_inverse() * position
		var key: Vector3i = Vector3i((p / BLOCK).floor())
		if _indices[id].has(key) and field(p, _indices[id][key], null) < 0.4:
			for entrance: Dictionary in network["entrances"]:
				if entrance["kind"] == "skylight" and (position - Vector3(entrance["position"])).dot(entrance["up"]) > 0.5 and position.distance_to(entrance["position"]) < 12:
					return -1
			return id
	return -1


func in_hole(position: Vector3) -> bool:
	for id: int in networks.size():
		var network: Dictionary = networks[id]
		if position.distance_squared_to(Transform3D(network["frame"]).origin) > 1000000:
			continue
		for entrance: Dictionary in network["entrances"]:
			var delta: Vector3 = position - Vector3(entrance["position"])
			var up: Vector3 = entrance["up"]
			if entrance["kind"] == "skylight":
				var depth: float = delta.dot(up)
				if delta.slide(up).length_squared() < 17.64 and depth < 5 and depth > -float(entrance["depth"]) - 5:
					return true
			else:
				var normal: Vector3 = entrance["normal"]
				var across: Vector3 = normal.cross(up).normalized()
				if pow(delta.dot(across) / 6, 2) + pow(delta.dot(up) / 4.5, 2) + pow(delta.dot(normal) / 12, 2) < 1:
					var p: Vector3 = Transform3D(network["frame"]).affine_inverse() * position
					var key: Vector3i = Vector3i((p / BLOCK).floor())
					# 开洞只覆盖真实空腔，避免较宽的入口椭球切掉洞壁外侧地面。
					if _indices[id].has(key) and field(p + Vector3.UP * 0.3, _indices[id][key], null) < 0:
						return true
	return false


static func field(p: Vector3, primitives: Array, noise: FastNoiseLite) -> float:
	var result: float = INF
	var floor_value: float = -INF
	var floor_weight: float = 0.0
	var floor_sum: float = 0.0
	var carved: bool = false
	for primitive: Dictionary in primitives:
		var a: Vector3 = primitive["a"]
		var b: Vector3 = primitive["b"]
		var segment: Vector2 = Vector2(b.x - a.x, b.z - a.z)
		var offset: Vector2 = Vector2(p.x - a.x, p.z - a.z)
		var t: float = clampf(offset.dot(segment) / maxf(segment.length_squared(), 0.00001), 0, 1)
		var q: Vector3 = a.lerp(b, t)
		var horizontal: float = Vector2(p.x - q.x, p.z - q.z).length()
		var r: float = primitive["radius"]
		var h: float = primitive["height"]
		var d: float
		if primitive.get("shaft", false):
			q = Geometry3D.get_closest_point_to_segment(p, a, b)
			d = p.distance_to(q) - r
		else:
			var y: float = maxf(p.y - q.y - h * 0.5, 0)
			d = (Vector2(horizontal / r, y / (h * 0.5)).length() - 1) * r
			d = maxf(d, q.y - p.y)
		if not primitive.get("shaft", false):
			var score: float = maxf(horizontal - r, 0)
			# 影响在两米内归零，与离线块的候选包围盒保持一致，避免块边界采用不同地面。
			var weight: float = 1 - smoothstep(0, 2, score) if p.y > q.y - 2 and p.y < q.y + h + 2 else 0
			floor_weight += weight
			floor_sum += q.y * weight
		if d < result:
			carved = primitive["carved"]
		# 仅在交汇附近平滑并集；平地面最后统一截断，避免接缝形成凹坑。
		if is_finite(result):
			var blend: float = clampf(0.5 + 0.5 * (d - result) / 2.0, 0, 1)
			result = lerpf(d, result, blend) - 2.0 * blend * (1 - blend)
		else:
			result = d
	var roughness: float = noise.get_noise_3dv(p) * (0.08 if carved else 0.8) if noise != null else 0.0
	if floor_weight > 0:
		floor_value = floor_sum / floor_weight
	var floor_roughness: float = sin(p.x * 0.25) * sin(p.z * 0.21) * 0.08 if noise != null else 0.0
	return maxf(result + roughness, floor_value + floor_roughness - p.y)


func apply(direction: Vector3, radius: float, height: float) -> float:
	for network: Dictionary in networks:
		var frame: Transform3D = network["frame"]
		if direction.dot(frame.origin.normalized()) < 0.99997:
			continue
		# 外侧缓坡连接真实山坡，避免短台地在门前形成无法步行的陡坎。
		var p: Vector3 = frame.affine_inverse() * (direction * (radius + height))
		var approach: Dictionary = network.get("approach", {"length": 18.0, "slope": 0.0})
		var length_value: float = approach["length"]
		if p.z > 1 or p.z < -length_value - 16 or absf(p.x) > 56:
			continue
		var weight: float = (1 - smoothstep(32, 56, absf(p.x))) * smoothstep(-length_value - 16, -length_value, p.z) * (1 - smoothstep(-1, 1, p.z))
		# 平段先覆盖距离场端帽，角色才能从缓坡连续进入零高度洞底。
		var normal: Vector3 = frame.basis.y - frame.basis.z * float(approach["slope"]) if p.z < GATE_APRON_Z else frame.basis.y
		var origin: Vector3 = frame * Vector3(0, 0, GATE_APRON_Z)
		var plane_radius: float = origin.dot(normal) / direction.dot(normal)
		height = lerpf(height, plane_radius - radius, weight)
	return height


func valid_seen(value: Variant) -> bool:
	if not value is Array:
		return false
	var keys: Dictionary = {}
	for network: Dictionary in networks:
		for node: Dictionary in network["nodes"] + network.get("map_nodes", []):
			keys["%d:%s" % [network["id"], node["id"]]] = true
	var unique: Dictionary = {}
	for key: Variant in value:
		if not key is String or not keys.has(key) or unique.has(key):
			return false
		unique[key] = true
	return true
