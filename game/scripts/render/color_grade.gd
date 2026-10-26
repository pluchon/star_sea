class_name ColorGrade
extends RefCounted

const SIZE: int = 32
const STEP: float = 1.0 / 64.0 # 小于此幅度的变化无需重新上传三维纹理。
var texture: ImageTexture3D
var _tables: Array[PackedByteArray] = []
var _identity: PackedByteArray = []
var _key: Vector4 = Vector4(-1, -1, -1, -1)
var _phase: Vector2i = Vector2i(-1, -1)
var _thread: Thread = Thread.new()


func _init(palette: RenderPalette) -> void:
	for period: Dictionary in palette.periods:
		var table: GradeLut = load("res://textures/grade/%s.res" % period["name"]) as GradeLut
		var bytes: PackedByteArray = []
		for slice: Image in table.slices:
			bytes.append_array(slice.get_data())
		_tables.append(bytes)
	_identity.resize(SIZE * SIZE * SIZE * 3)
	for blue: int in SIZE:
		for green: int in SIZE:
			for red: int in SIZE:
				var index: int = ((blue * SIZE + green) * SIZE + red) * 3
				_identity[index] = roundi(float(red) * 255 / (SIZE - 1))
				_identity[index + 1] = roundi(float(green) * 255 / (SIZE - 1))
				_identity[index + 2] = roundi(float(blue) * 255 / (SIZE - 1))
	texture = ImageTexture3D.new()
	texture.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, _slices(_tables[1]))


func update(phase: Vector3, cave: float, space: float) -> void:
	if _thread.is_started():
		if _thread.is_alive():
			return
		texture.update(_thread.wait_to_finish())
	var key: Vector4 = Vector4(phase.z, cave, space, 0)
	var pair: Vector2i = Vector2i(int(phase.x), int(phase.y))
	if pair == _phase and key.distance_to(_key) < STEP:
		return
	_key = key
	_phase = pair
	# 插值在后台完成；每帧只更新一份已有纹理，不分配渲染资源。
	_thread.start(_blend.bind(_tables[pair.x], _tables[pair.y], _tables[4], _identity, key))


static func _blend(a: PackedByteArray, b: PackedByteArray, cave: PackedByteArray, neutral: PackedByteArray, key: Vector4) -> Array[Image]:
	var result: PackedByteArray = []
	result.resize(a.size())
	for index: int in result.size():
		var value: float = lerpf(a[index], b[index], key.x)
		value = lerpf(value, cave[index], key.y)
		result[index] = roundi(lerpf(value, neutral[index], key.z))
	return _slices(result)


static func _slices(bytes: PackedByteArray) -> Array[Image]:
	var slices: Array[Image] = []
	var stride: int = SIZE * SIZE * 3
	for index: int in SIZE:
		slices.append(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes.slice(index * stride, (index + 1) * stride)))
	return slices


func finish() -> void:
	if _thread.is_started():
		texture.update(_thread.wait_to_finish())
