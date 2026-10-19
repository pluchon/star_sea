class_name SurfaceGrid
extends RefCounted


# 分块编号只依赖球面方向；浮动原点、离开区域和跨立方体面均不改变种子。
static func cell_at(up: Vector3, divisions: int) -> Vector3i:
	var face: int = 0
	var maximum: float = -INF
	for index: int in PlanetTerrain.FACES.size():
		var alignment: float = up.dot(PlanetTerrain.FACES[index][0])
		if alignment > maximum:
			maximum = alignment
			face = index
	var axes: Array = PlanetTerrain.FACES[face]
	var uv: Vector2 = (Vector2(up.dot(axes[1]), up.dot(axes[2])) / maximum + Vector2.ONE) * 0.5 * divisions
	return Vector3i(face, clampi(floori(uv.x), 0, divisions - 1), clampi(floori(uv.y), 0, divisions - 1))


static func direction(key: Vector3i, divisions: int, fraction: Vector2 = Vector2(0.5, 0.5)) -> Vector3:
	var axes: Array = PlanetTerrain.FACES[key.x]
	var u: float = (float(key.y) + fraction.x) / divisions * 2.0 - 1.0
	var v: float = (float(key.z) + fraction.y) / divisions * 2.0 - 1.0
	return ((axes[0] as Vector3) + (axes[1] as Vector3) * u + (axes[2] as Vector3) * v).normalized()


static func nearby(up: Vector3, radius: float, distance: float, divisions: int) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	var extent: float = distance / radius
	for face: int in PlanetTerrain.FACES.size():
		var axes: Array = PlanetTerrain.FACES[face]
		var facing: float = up.dot(axes[0])
		if facing < 0.35:
			continue
		var center: Vector2 = Vector2(up.dot(axes[1]), up.dot(axes[2])) / facing
		var reach: float = extent * 3.2
		var low: Vector2i = Vector2i(((center - Vector2.ONE * reach) + Vector2.ONE) * 0.5 * divisions)
		var high: Vector2i = Vector2i(((center + Vector2.ONE * reach) + Vector2.ONE) * 0.5 * divisions)
		for y: int in range(maxi(0, low.y), mini(divisions - 1, high.y) + 1):
			for x: int in range(maxi(0, low.x), mini(divisions - 1, high.x) + 1):
				var key: Vector3i = Vector3i(face, x, y)
				var separation: float = direction(key, divisions).distance_to(up) * radius
				if separation < distance + radius * 1.5 / divisions:
					keys.append(key)
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return direction(a, divisions).distance_squared_to(up) < direction(b, divisions).distance_squared_to(up))
	return keys
