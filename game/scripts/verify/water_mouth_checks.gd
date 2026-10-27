class_name WaterMouthChecks
extends RefCounted


static func run() -> Dictionary:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000)
	var data: HydrologyData = noise.features.hydrology.data
	var planet: Planet = Planet.new()
	planet.noise = noise
	var chunks: WaterChunks = WaterChunks.new()
	chunks.build(planet, data)
	var indices: Dictionary = {}
	var mouths: Array[Dictionary] = []
	var failures: int = 0
	for river: int in data.river_starts.size() - 1:
		var start: int = data.river_starts[river]
		var end: int = data.river_starts[river + 1] - 1
		if data.river_levels[end] > 2 or noise.height(data.river_points[end]) > 0.3:
			continue
		var direction: Vector3 = data.river_points[end]
		var crossing: int = -1
		for segment: int in range(start, end):
			if data.river_levels[segment] >= 0 and data.river_levels[segment + 1] <= 0:
				crossing = segment
		if crossing >= 0:
			var weight: float = data.river_levels[crossing] / maxf(data.river_levels[crossing] - data.river_levels[crossing + 1], 0.00001)
			direction = data.river_points[crossing].slerp(data.river_points[crossing + 1], weight).normalized()
		var segment_index: int = crossing if crossing >= 0 else maxi(start, end - 1)
		var forward: Vector3 = (data.river_points[segment_index + 1] - data.river_points[segment_index]).slide(direction).normalized()
		var side: Vector3 = forward.cross(direction).normalized()
		var runs: Array[int] = [0, 0]
		var longest: float = 0
		var duplicate: int = 0
		var covered: int = 0
		var seam_levels: Array[float] = _levels_at(direction, chunks, indices)
		var gap: float = INF
		for level: float in seam_levels:
			gap = minf(gap, absf(level))
		var samples: Array[Dictionary] = []
		for distance: int in range(-20, 21):
			var at: Vector3 = SurfaceSites.offset_direction(direction, forward, distance, noise.radius)
			var nearest: Vector4 = noise.features.hydrology.nearest(at)
			var width: float = nearest.z * 1.15 if nearest.w >= 0 else data.river_widths[end] * 1.15
			for bank_index: int in 2:
				var sign_value: float = -1 if bank_index == 0 else 1
				var bank: Vector3 = SurfaceSites.offset_direction(at, side, sign_value * (width + 1), noise.radius)
				var outer: Vector3 = SurfaceSites.offset_direction(bank, side, sign_value, noise.radius)
				var steep: bool = absf(noise.height(bank) - noise.height(outer)) > 1.5
				runs[bank_index] = runs[bank_index] + 1 if steep else 0
				longest = maxf(longest, runs[bank_index])
			var levels: Array[float] = _levels_at(at, chunks, indices)
			var ground: float = noise.height(at)
			var visible: Array[float] = []
			for level: float in levels:
				if level >= ground - 0.03:
					visible.append(level)
			if not levels.is_empty() and visible.is_empty():
				covered += 1
			# 海面着色器按同一球面求交；河面即使恰好为零，也会形成第二层。
			var ocean_visible: bool = ground < -0.03
			if visible.size() + int(ocean_visible) > 1:
				duplicate += 1
			samples.append({"distance_m": distance, "ground_m": ground, "river_mesh_levels_m": levels, "ocean_visible": ocean_visible, "visible_layers": visible.size() + int(ocean_visible)})
		var passed: bool = gap <= 0.3 and longest <= 3 and covered == 0 and duplicate == 0
		failures += int(not passed)
		mouths.append({"river": river, "passed": passed, "position": direction * noise.radius, "sea_gap_m": gap if is_finite(gap) else null, "missing_seam_mesh": not is_finite(gap), "longest_steep_bank_m": longest, "covered_or_disconnected_samples": covered, "overlapping_water_samples": duplicate, "samples": samples})
	chunks.free()
	planet.free()
	return {"passed": failures == 0 and not mouths.is_empty(), "mouths": mouths, "failed_mouths": failures, "coverage_complete": true, "surface_source": "WaterChunks._generate 的实际河面三角形；water.gdshader 的零海平面球面", "tolerances": {"seam_m": 0.3, "bank_slope": 1.5, "maximum_cliff_run_m": 3}}


static func _levels_at(direction: Vector3, chunks: WaterChunks, indices: Dictionary) -> Array[float]:
	var bucket: int = HydrologyData.cell_at(direction, HydrologyData.BUCKET_GRID)
	var size: int = HydrologyData.BUCKET_GRID
	var face: int = bucket / (size * size)
	var x: int = bucket % size
	var y: int = (bucket / size) % size
	var neighbors: Dictionary = {}
	var result: Array[float] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			var neighbor: Vector3 = HydrologyData.corner(face, (float(x + dx) + 0.5) * 2 / size - 1, (float(y + dy) + 0.5) * 2 / size - 1)
			neighbors[HydrologyData.cell_at(neighbor, size)] = true
	for neighbor: int in neighbors:
		for level: float in _levels_in_bucket(direction, chunks, indices, neighbor):
			var unique: bool = true
			for existing: float in result:
				unique = unique and absf(existing - level) > 0.005
			if unique:
				result.append(level)
	return result


static func _levels_in_bucket(direction: Vector3, chunks: WaterChunks, indices: Dictionary, bucket: int) -> Array[float]:
	if not indices.has(bucket):
		indices[bucket] = _index(chunks._generate(bucket))
	var index: Dictionary = indices[bucket]
	var position: Vector3 = direction * chunks._radius
	var at: Vector3 = Basis(index["basis"]).inverse() * (position - Vector3(index["origin"]))
	var cell: Vector2i = Vector2i(floori(at.x / 16), floori(at.z / 16))
	var candidates: Dictionary = {}
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			for triangle: int in index["cells"].get(cell + Vector2i(dx, dz), []):
				candidates[triangle] = true
	var result: Array[float] = []
	var faces: PackedVector3Array = index["faces"]
	var origin: Vector3 = position + direction * 30 - Vector3(index["origin"])
	for triangle: int in candidates:
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, -direction, faces[triangle], faces[triangle + 1], faces[triangle + 2])
		if not hit is Vector3:
			continue
		var level: float = (Vector3(hit) + Vector3(index["origin"])).length() - chunks._radius
		var unique: bool = true
		for existing: float in result:
			unique = unique and absf(existing - level) > 0.005
		if unique:
			result.append(level)
	return result


static func _index(arrays: Dictionary) -> Dictionary:
	var faces: PackedVector3Array = []
	for kind: String in ["rivers", "falls"]:
		if not arrays[kind].is_empty():
			faces.append_array(arrays[kind][Mesh.ARRAY_VERTEX])
	var origin: Vector3 = arrays["origin"]
	var basis_value: Basis = Basis.looking_at(SurfaceSites.tangent_forward(origin.normalized()), origin.normalized())
	var inverse: Basis = basis_value.inverse()
	var cells: Dictionary = {}
	for triangle: int in range(0, faces.size(), 3):
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		for corner: int in 3:
			var at: Vector3 = inverse * faces[triangle + corner]
			low = low.min(Vector2(at.x, at.z))
			high = high.max(Vector2(at.x, at.z))
		for x: int in range(floori(low.x / 16), floori(high.x / 16) + 1):
			for z: int in range(floori(low.y / 16), floori(high.y / 16) + 1):
				var key: Vector2i = Vector2i(x, z)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(triangle)
	return {"faces": faces, "cells": cells, "basis": basis_value, "origin": origin}
