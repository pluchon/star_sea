class_name CaveMesher
extends RefCounted

const STEP: float = 0.5 # 回声洞的开凿段需要半米精度，整网共用网格以免异级接缝。
const CELLS: int = 64 # 每块三十二米；多计算一圈单元，共享边界的顶点完全相同。
const CORNERS: Array[Vector3i] = [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(1,1,0), Vector3i(0,0,1), Vector3i(1,0,1), Vector3i(0,1,1), Vector3i(1,1,1)]
const EDGES: Array[Vector2i] = [Vector2i(0,1), Vector2i(2,3), Vector2i(4,5), Vector2i(6,7), Vector2i(0,2), Vector2i(1,3), Vector2i(4,6), Vector2i(5,7), Vector2i(0,4), Vector2i(1,5), Vector2i(2,6), Vector2i(3,7)]
var _noise: FastNoiseLite = FastNoiseLite.new()


func generate(data: CaveData, terrain: TerrainNoise) -> void:
	_noise.seed = 20261029
	_noise.frequency = 1.0 / 6.0
	data.prepare()
	var triangles: int = 0
	for id: int in data.networks.size():
		var network: Dictionary = data.networks[id]
		var keys: Array = data._indices[id].keys()
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x if a.x != b.x else (a.y < b.y if a.y != b.y else a.z < b.z))
		for key: Vector3i in keys:
			var origin: Vector3 = Vector3(key) * CaveData.BLOCK
			var bounds: AABB = AABB(origin - Vector3.ONE, Vector3.ONE * (CaveData.BLOCK + 2))
			var nearby: Array[Dictionary] = []
			for primitive: Dictionary in network["primitives"]:
				if bounds.intersects(primitive["bounds"]):
					nearby.append(primitive)
			var chunk: Dictionary = _chunk(origin, nearby, network["entrances_local"], terrain, network["frame"])
			if not chunk.is_empty():
				chunk["network"] = id
				chunk["key"] = key
				data.chunks.append(chunk)
				triangles += (chunk["indices"] as PackedInt32Array).size() / 3
			if data.chunks.size() % 16 == 0:
				print("洞穴网格：%d 块，%d 三角形" % [data.chunks.size(), triangles])
	data.statistics["chunks"] = data.chunks.size()
	data.statistics["triangles"] = triangles


func _chunk(origin: Vector3, primitives: Array[Dictionary], entrances: PackedVector3Array, terrain: TerrainNoise, frame: Transform3D) -> Dictionary:
	const N: int = CELLS + 2
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(N * N * N)
	for z: int in N:
		for y: int in N:
			for x: int in N:
				var p: Vector3 = origin + Vector3(x - 1, y - 1, z - 1) * STEP
				samples[x + N * (y + N * z)] = CaveData.field(p, primitives, _noise)
	var ids: PackedInt32Array = PackedInt32Array()
	ids.resize(N * N * N)
	ids.fill(-1)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var cells: PackedVector3Array = PackedVector3Array()
	for z: int in N - 1:
		for y: int in N - 1:
			for x: int in N - 1:
				var values: PackedFloat32Array = PackedFloat32Array()
				var mask: int = 0
				for c: Vector3i in CORNERS:
					var value: float = samples[x + c.x + N * (y + c.y + N * (z + c.z))]
					mask = mask * 2 + int(value < 0)
					values.append(value)
				if mask == 0 or mask == 255:
					continue
				var point: Vector3 = Vector3.ZERO
				var crossings: int = 0
				for edge: Vector2i in EDGES:
					if (values[edge.x] < 0) == (values[edge.y] < 0):
						continue
					var weight: float = values[edge.x] / (values[edge.x] - values[edge.y])
					point += Vector3(CORNERS[edge.x]).lerp(Vector3(CORNERS[edge.y]), weight)
					crossings += 1
				point = origin + (Vector3(x - 1, y - 1, z - 1) + point / crossings) * STEP
				var gradient: Vector3 = Vector3(
					CaveData.field(point + Vector3.RIGHT * 0.1, primitives, _noise) - CaveData.field(point - Vector3.RIGHT * 0.1, primitives, _noise),
					CaveData.field(point + Vector3.UP * 0.1, primitives, _noise) - CaveData.field(point - Vector3.UP * 0.1, primitives, _noise),
					CaveData.field(point + Vector3.BACK * 0.1, primitives, _noise) - CaveData.field(point - Vector3.BACK * 0.1, primitives, _noise))
				ids[x + N * (y + N * z)] = vertices.size()
				vertices.append(point - origin)
				cells.append(origin / STEP + Vector3(x - 1, y - 1, z - 1))
				normals.append(-gradient.normalized())
				var distance: float = INF
				for entrance: Vector3 in entrances:
					distance = minf(distance, point.distance_to(entrance))
				var carved: float = 0.0
				var wet: float = 0.0
				var closest: float = INF
				for primitive: Dictionary in primitives:
					var d: float = point.distance_to(Geometry3D.get_closest_point_to_segment(point, primitive["a"], primitive["b"])) - float(primitive["radius"])
					if d < closest:
						closest = d
						carved = float(primitive["carved"])
						wet = float(primitive.get("wet", false))
				var openness: float = clampf(-CaveData.field(point - gradient.normalized() * 1.5, primitives, _noise) / 1.5, 0.25, 1)
				colors.append(Color(openness, wet, clampf(distance / 60, 0, 1), carved))
	var indices: PackedInt32Array = PackedInt32Array()
	var stride: Array[int] = [1, N, N * N]
	for z: int in range(1, CELLS + 1):
		for y: int in range(1, CELLS + 1):
			for x: int in range(1, CELLS + 1):
				var at: int = x + N * (y + N * z)
				for axis: int in 3:
					if (samples[at] < 0) == (samples[at + stride[axis]] < 0):
						continue
					var u: int = stride[(axis + 1) % 3]
					var v: int = stride[(axis + 2) % 3]
					var quad: Array[int] = [ids[at], ids[at - u], ids[at - u - v], ids[at - v]]
					if quad.has(-1):
						continue
					var normal: Vector3 = normals[quad[0]] + normals[quad[1]] + normals[quad[2]] + normals[quad[3]]
					if (vertices[quad[1]] - vertices[quad[0]]).cross(vertices[quad[2]] - vertices[quad[0]]).dot(normal) > 0:
						quad.reverse()
					indices.append_array(PackedInt32Array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]))
	var clipped: Dictionary = _surface_clip(origin, frame, terrain, vertices, normals, colors, cells, indices)
	vertices = clipped["vertices"]
	normals = clipped["normals"]
	colors = clipped["colors"]
	cells = clipped["cells"]
	indices = clipped["indices"]
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(indices.size())
	for index: int in indices.size():
		faces[index] = vertices[indices[index]]
	return {} if indices.is_empty() else {"origin": origin, "vertices": vertices, "cells": cells, "normals": normals, "colors": colors, "indices": indices, "faces": faces, "bounds": AABB(origin, Vector3.ONE * CaveData.BLOCK)}


func _surface_clip(origin: Vector3, frame: Transform3D, terrain: TerrainNoise, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, cells: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	# 距离场必须延伸到地表外才能开口，但洞壁网格不能在井口上方形成封闭圆筒。
	var offsets: PackedFloat32Array = PackedFloat32Array()
	for vertex: Vector3 in vertices:
		var world: Vector3 = frame * (vertex + origin)
		offsets.append(world.length() - terrain.radius - terrain.height(world.normalized()) - 0.2)
	var result: PackedInt32Array = PackedInt32Array()
	for start: int in range(0, indices.size(), 3):
		var triangle: Array[int] = [indices[start], indices[start + 1], indices[start + 2]]
		var inside: int = int(offsets[triangle[0]] <= 0) + int(offsets[triangle[1]] <= 0) + int(offsets[triangle[2]] <= 0)
		if inside == 0:
			continue
		if inside == 3:
			result.append_array(PackedInt32Array(triangle))
			continue
		var polygon: Array[int] = []
		for corner: int in 3:
			var a: int = triangle[(corner + 2) % 3]
			var b: int = triangle[corner]
			if (offsets[a] <= 0) != (offsets[b] <= 0):
				var low: float = 0
				var high: float = 1
				for iteration: int in 12:
					var t: float = (low + high) * 0.5
					var p: Vector3 = vertices[a].lerp(vertices[b], t)
					var world: Vector3 = frame * (p + origin)
					var distance: float = world.length() - terrain.radius - terrain.height(world.normalized()) - 0.2
					if (distance <= 0) == (offsets[a] <= 0):
						low = t
					else:
						high = t
				var weight: float = (low + high) * 0.5
				var point: Vector3 = vertices[a].lerp(vertices[b], weight)
				polygon.append(vertices.size())
				vertices.append(point)
				normals.append(normals[a].lerp(normals[b], weight).normalized())
				colors.append(colors[a].lerp(colors[b], weight))
				cells.append(((point + origin) * 1000).round() + Vector3.ONE * 1000000)
			if offsets[b] <= 0:
				polygon.append(b)
		for corner: int in range(1, polygon.size() - 1):
			result.append_array(PackedInt32Array([polygon[0], polygon[corner], polygon[corner + 1]]))
	return {"vertices": vertices, "normals": normals, "colors": colors, "cells": cells, "indices": result}
