class_name DawnHeightfield
extends Resource

const PATH: String = "res://data/dawn_terrain.res"
const RADIUS: float = 40000.0
const SPAWN_CORE: float = 2020.0
const SPAWN_BLEND_END: float = 2200.0
# 二点二公里圆弧的余弦，热路径先排除保护区以外的查询。
const SPAWN_ALIGNMENT: float = 0.99848788
static var _shared: DawnHeightfield
static var _mutex: Mutex = Mutex.new()
@export var version: int = 2
@export var grid: int = 2048
@export var minimum: float = -500.0
@export var maximum: float = 4300.0
@export var metadata: Dictionary
@export var faces: Array[PackedByteArray] = []
@export var collapse: Array[PackedByteArray] = []
@export var spawn: Vector3
@export var spawn_forward: Vector3
@export var spawn_right: Vector3
@export var spawn_size: int
@export var spawn_step: float
@export var spawn_heights: PackedByteArray


static func shared() -> DawnHeightfield:
	_mutex.lock()
	if _shared == null:
		_shared = load(PATH) as DawnHeightfield
	_mutex.unlock()
	return _shared


func coordinates(direction: Vector3) -> Vector3:
	var absolute: Vector3 = direction.abs()
	var face: int
	var u: float
	var v: float
	if absolute.y >= absolute.x and absolute.y >= absolute.z:
		face = 0 if direction.y > 0 else 1
		u = direction.x / absolute.y
		v = -direction.z / absolute.y if face == 0 else direction.z / absolute.y
	elif absolute.x >= absolute.z:
		face = 2 if direction.x > 0 else 3
		u = -direction.z / absolute.x if face == 2 else direction.z / absolute.x
		v = direction.y / absolute.x
	else:
		face = 4 if direction.z > 0 else 5
		u = direction.x / absolute.z if face == 4 else -direction.x / absolute.z
		v = direction.y / absolute.z
	return Vector3((u + 1.0) * 0.5 * (grid - 1) + 2.0, (v + 1.0) * 0.5 * (grid - 1) + 2.0, face)


# 两格边框已经从相邻立方体面重采样；查询不会修改资源或创建缓存。
func sample(direction: Vector3) -> float:
	# 全局格距约三十一米，无法保留出生区原有的小尺度细节；局部使用八米原始采样。
	var alignment: float = direction.dot(spawn)
	if alignment > SPAWN_ALIGNMENT and not spawn_heights.is_empty():
		var distance: float = direction.distance_to(spawn) * RADIUS
		var scale: float = RADIUS / (alignment * spawn_step)
		var px: float = direction.dot(spawn_right) * scale + (spawn_size - 1) * 0.5
		var py: float = direction.dot(spawn_forward) * scale + (spawn_size - 1) * 0.5
		var original: float = _interpolate(spawn_heights, spawn_size, px, py)
		if distance <= SPAWN_CORE:
			return original
		return lerpf(original, _global_sample(direction), smoothstep(SPAWN_CORE, SPAWN_BLEND_END, distance))
	return _global_sample(direction)


func _global_sample(direction: Vector3) -> float:
	var uv: Vector3 = coordinates(direction)
	return _interpolate(faces[int(uv.z)], grid + 4, uv.x, uv.y)


func _interpolate(bytes: PackedByteArray, stride: int, px: float, py: float) -> float:
	var x: int = floori(px)
	var y: int = floori(py)
	var dx: float = px - x
	var dy: float = py - y
	# 四行共用横向权重，避免热路径反复计算三次多项式。
	var wx: Vector4 = Vector4(dx * (-0.5 + dx * (1.0 - 0.5 * dx)), 1.0 + dx * dx * (-2.5 + 1.5 * dx), dx * (0.5 + dx * (2.0 - 1.5 * dx)), dx * dx * (-0.5 + 0.5 * dx))
	var wy: Vector4 = Vector4(dy * (-0.5 + dy * (1.0 - 0.5 * dy)), 1.0 + dy * dy * (-2.5 + 1.5 * dy), dy * (0.5 + dy * (2.0 - 1.5 * dy)), dy * dy * (-0.5 + 0.5 * dy))
	var offset: int = ((y - 1) * stride + x - 1) * 2
	var a: float = wx.dot(Vector4(bytes.decode_u16(offset), bytes.decode_u16(offset + 2), bytes.decode_u16(offset + 4), bytes.decode_u16(offset + 6)))
	offset += stride * 2
	var b: float = wx.dot(Vector4(bytes.decode_u16(offset), bytes.decode_u16(offset + 2), bytes.decode_u16(offset + 4), bytes.decode_u16(offset + 6)))
	offset += stride * 2
	var c: float = wx.dot(Vector4(bytes.decode_u16(offset), bytes.decode_u16(offset + 2), bytes.decode_u16(offset + 4), bytes.decode_u16(offset + 6)))
	offset += stride * 2
	var d: float = wx.dot(Vector4(bytes.decode_u16(offset), bytes.decode_u16(offset + 2), bytes.decode_u16(offset + 4), bytes.decode_u16(offset + 6)))
	return minimum + wy.dot(Vector4(a, b, c, d)) * ((maximum - minimum) / 65535.0)


func collapse_at(direction: Vector3) -> float:
	var uv: Vector3 = coordinates(direction)
	var size: int = grid / 4
	var px: float = (uv.x - 2.0) / (grid - 1) * (size - 1)
	var py: float = (uv.y - 2.0) / (grid - 1) * (size - 1)
	var x: int = clampi(floori(px), 0, size - 2)
	var y: int = clampi(floori(py), 0, size - 2)
	var bytes: PackedByteArray = collapse[int(uv.z)]
	var a: float = lerpf(bytes[y * size + x], bytes[y * size + x + 1], px - x)
	var b: float = lerpf(bytes[(y + 1) * size + x], bytes[(y + 1) * size + x + 1], px - x)
	return lerpf(a, b, py - y) / 255.0
