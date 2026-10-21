class_name RoadSurface
extends Node3D

const CHUNK_POINTS: int = 100 # 一段约一公里。
var _planet: Planet
var _data: CivilizationData
var _chunks: Dictionary = {}
var _elapsed: float = 1.0


func _ready() -> void:
	_planet = get_parent().get_parent() as Planet
	_data = _planet.noise.features.civilization.data


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var local: Vector3 = _planet.to_local(camera.global_position)
	for road_index: int in _data.roads.size():
		var points: PackedVector3Array = _data.roads[road_index]["points"]
		for first: int in range(0, points.size() - 1, CHUNK_POINTS):
			var last: int = mini(points.size() - 1, first + CHUNK_POINTS)
			var key: Vector2i = Vector2i(road_index, first)
			var near: bool = false
			for index: int in range(first, last + 1, 10):
				near = near or local.distance_to(points[index] * (_planet.radius + _planet.noise.height(points[index]))) < 2000.0
			if near and not _chunks.has(key):
				_chunks[key] = _build(_data.roads[road_index], first, last)
			elif not near and _chunks.has(key):
				(_chunks[key] as Node3D).queue_free()
				_chunks.erase(key)


func _build(road: Dictionary, first: int, last: int) -> MeshInstance3D:
	var points: PackedVector3Array = road["points"]
	var anchor: Vector3 = points[first] * _planet.radius
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uv: PackedVector2Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	var width: float = float(road["width"]) + 0.4
	for index: int in range(first, last + 1):
		var forward: Vector3 = points[maxi(index - 1, 0)].direction_to(points[mini(index + 1, points.size() - 1)]).slide(points[index]).normalized()
		var side: Vector3 = forward.cross(points[index]).normalized()
		for sign_value: float in [-1.0, 1.0]:
			var direction: Vector3 = SurfaceSites.offset_direction(points[index], side, sign_value * width * 0.5, _planet.radius)
			vertices.append(direction * (_planet.radius + _planet.noise.height(direction) + 0.04) - anchor)
			normals.append(direction)
			uv.append(Vector2((sign_value + 1.0) * width * 0.5, index * 10.0))
			colors.append(Color(road["wear"][index], 0, 0, 1))
		if index > first and not _on_bridge(points[index]):
			var base: int = (index - first - 1) * 2
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	if not indices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = anchor
	instance.material_override = load("res://shaders/road_material.tres") as Material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _on_bridge(direction: Vector3) -> bool:
	for bridge: Dictionary in _data.bridges:
		var delta: Vector3 = (direction - Vector3(bridge["direction"])) * _planet.radius
		var x: Vector3 = bridge["across"]
		var z: Vector3 = x.cross(bridge["direction"]).normalized()
		if absf(delta.dot(x)) < float(bridge.get("length", 72.0)) * 0.5 + 2.0 and absf(delta.dot(z)) < 4:
			return true
	return false
