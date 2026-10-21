class_name CivilizationSites
extends Node3D

var _planet: Planet
var _data: CivilizationData
var _near: RuinBuilder
var _near_placements: Array[Dictionary] = []
var _elapsed: float = 1.0


func _ready() -> void:
	_planet = get_parent() as Planet
	_data = _planet.noise.features.civilization.data
	var far: Array[Dictionary] = []
	var roads: Array[Dictionary] = []
	for placement: Dictionary in _data.placements:
		match placement.get("group", "town"):
			"monument": far.append(placement)
			"road": roads.append(placement)
			_: _near_placements.append(placement)
	for records: Array[Dictionary] in [far, roads]:
		var builder: RuinBuilder = RuinBuilder.new()
		add_child(builder)
		builder.build(records)
		if records == far:
			for node: Node in builder.get_children():
				if node is GeometryInstance3D:
					(node as GeometryInstance3D).visibility_range_end = 8000.0
	var surface: RoadSurface = RoadSurface.new()
	add_child(surface)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var local: Vector3 = _planet.to_local(camera.global_position)
	var center: Vector3 = _data.town["direction"]
	var distance: float = local.distance_to(center * (_planet.radius + float(_data.town["level"])))
	if distance < 3000.0 and _near == null:
		_near = RuinBuilder.new()
		add_child(_near)
		_near.build(_near_placements)
	elif distance > 4000.0 and _near != null:
		_near.queue_free()
		_near = null
