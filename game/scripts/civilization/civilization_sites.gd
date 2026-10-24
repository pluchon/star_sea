class_name CivilizationSites
extends Node3D

var _planet: Planet
var _data: CivilizationData
var _near: RuinBuilder
var _near_placements: Array[Dictionary] = []
var _elapsed: float = 1.0
var _rooms: Array[Dictionary] = []


func _ready() -> void:
	_planet = get_parent() as Planet
	_data = _planet.noise.features.civilization.data
	for house: Dictionary in _data.town.get("houses", []):
		if float(house["state"]) < 0.7:
			continue
		var up: Vector3 = house["direction"]
		var forward: Vector3 = up.direction_to(_data.town["direction"]).slide(up).normalized()
		var frame: Transform3D = Transform3D(Basis.looking_at(forward, up), up * _planet.surface_radius(up))
		_rooms.append({"frame": frame.affine_inverse(), "half": Vector3(3, 4, 5) if int(house["style"]) == 1 else Vector3(4.5, 5, 4.5)})
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
	# 观景环超过三公里时近景已经卸载，保留同源墙体与穹顶作为聚落轮廓。
	var town_outline: Array[Dictionary] = []
	for record: Dictionary in _near_placements:
		if record["piece"] in ["wall", "wall_broken", "wall_low", "wall_low_broken", "door_arch", "dome_broken", "floor_slab", "floor_slab_broken"]:
			var distant: Dictionary = record.duplicate()
			distant["collision"] = false
			town_outline.append(distant)
	var far_town: RuinBuilder = RuinBuilder.new()
	far_town.name = "FarTown"
	add_child(far_town)
	far_town.build(town_outline)
	for node: Node in far_town.get_children():
		if node is GeometryInstance3D:
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			geometry.visibility_range_begin = 1300
			geometry.visibility_range_end = 30000
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func indoors(local: Vector3) -> bool:
	for room: Dictionary in _rooms:
		var at: Vector3 = Transform3D(room["frame"]) * local
		var half: Vector3 = room["half"]
		if absf(at.x) < half.x and absf(at.z) < half.z and at.y > 0 and at.y < half.y:
			return true
	var ladder: Vector3 = LandingPads.frame(_planet).affine_inverse() * local
	return (absf(ladder.x) < 14 and absf(ladder.z + 60) < 18 and ladder.y > 0 and ladder.y < 32) or (absf(ladder.y - LandingPads.balcony_height(_planet)) < 4 and Vector2(ladder.x, ladder.z).length() < 60)


func ruin_proximity(local: Vector3) -> float:
	var distance: float = INF
	for site: Dictionary in [_data.town, _data.ladder]:
		var up: Vector3 = site["direction"]
		distance = minf(distance, local.distance_to(up * _planet.surface_radius(up)))
	if _planet.noise.features.caves != null:
		for entrance: Dictionary in _planet.noise.features.caves.networks[0]["entrances"]:
			distance = minf(distance, local.distance_to(entrance["position"]))
	return 1 - smoothstep(80, 260, distance)
