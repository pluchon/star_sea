class_name TerrainMapData
extends RefCounted


static func direction_at(uv: Vector2) -> Vector3:
	var longitude: float = (uv.x - 0.5) * TAU
	var latitude: float = (0.5 - uv.y) * PI
	return Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))


static func coordinates(direction: Vector3) -> Vector2:
	var up: Vector3 = direction.normalized()
	return Vector2(atan2(up.z, up.x) / TAU + 0.5, 0.5 - asin(clampf(up.y, -1.0, 1.0)) / PI)


static func north(up: Vector3) -> Vector3:
	var tangent: Vector3 = Vector3.UP - up * up.y
	return tangent.normalized() if tangent.length_squared() > 0.00001 else SurfaceSites.tangent_forward(up)


static func generate(noise: TerrainNoise, size: Vector2i, center: Vector3 = Vector3.ZERO, span: float = 1600.0) -> Dictionary:
	# 每个像素两个通道：海拔，以及河湖的水深（不在河湖里为零）。
	var heights: PackedFloat32Array = []
	heights.resize(size.x * size.y * 2)
	var northward: Vector3 = north(center) if center != Vector3.ZERO else Vector3.UP
	var eastward: Vector3 = center.cross(northward)
	var minimum: float = INF
	var maximum: float = -INF
	for row: int in size.y:
		for column: int in size.x:
			var uv: Vector2 = (Vector2(column, row) + Vector2.ONE * 0.5) / Vector2(size)
			var direction: Vector3 = direction_at(uv)
			if center != Vector3.ZERO:
				var tangent: Vector3 = eastward * (uv.x - 0.5) * span + northward * (0.5 - uv.y) * span
				var distance: float = tangent.length()
				direction = SurfaceSites.offset_direction(center, tangent / maxf(distance, 0.0001), distance, noise.radius)
			var height: float = noise.height(direction)
			heights[(row * size.x + column) * 2] = height
			heights[(row * size.x + column) * 2 + 1] = maxf(noise.water_surface(direction, height) - height, 0.0)
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	var image: Image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGF, heights.to_byte_array())
	return {"image": image, "center": center, "span": span, "minimum": minimum, "maximum": maximum}
