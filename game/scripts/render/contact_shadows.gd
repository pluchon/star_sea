class_name ContactShadows
extends Node3D

const RANGE: float = 80.0 # 仅为近处物件补接触暗部，单位米。
const LIMIT: int = 128 # 限制贴花数量，避免密集遗迹增加无界开销。
var _texture: GradientTexture2D
var _active: Dictionary = {}
var _elapsed: float = 0.0


func _ready() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.3, 1])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.26), Color(0, 0, 0, 0.17), Color.TRANSPARENT])
	_texture = GradientTexture2D.new()
	_texture.gradient = gradient
	_texture.width = 64
	_texture.height = 64
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(0.5, 1)


func _process(delta: float) -> void:
	var player: StarSeaPlayer = get_tree().current_scene.get_node_or_null("Player") as StarSeaPlayer
	# 动态物件逐帧跟随，静态物件的距离筛选分摊到低频更新。
	if player != null:
		if _active.has("explorer"):
			var explorer: Decal = _active["explorer"]
			explorer.global_transform = player.global_transform
			explorer.visible = player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor() and player.third_person
		if _active.has("ship"):
			var ship: Decal = _active["ship"]
			ship.global_transform = player.ship.global_transform
			ship.global_position -= player.ship.global_basis.y * StarSeaShip.FOOT_HEIGHT
			ship.visible = player.ship.state == StarSeaShip.State.PARKED
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var candidates: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("contact_shadow_sources"):
		var source: Node3D = node as Node3D
		var eye: Vector3 = source.to_local(camera.global_position)
		var records: Array = source.get_meta("contact_records")
		for index: int in records.size():
			var record: Dictionary = records[index]
			var transform_value: Transform3D = record["transform"]
			var distance_value: float = eye.distance_to(transform_value.origin)
			if distance_value < RANGE:
				candidates.append({"key": "%d:%d" % [source.get_instance_id(), index], "transform": source.global_transform * transform_value, "size": record["size"], "distance": distance_value})
	if player != null:
		if player.mode == StarSeaPlayer.Mode.WALK and player.is_on_floor() and player.third_person:
			candidates.append({"key": "explorer", "transform": player.global_transform, "size": Vector3(0.85, 0.9, 0.85), "distance": 0.0})
		if player.ship.state == StarSeaShip.State.PARKED:
			var ship_transform: Transform3D = player.ship.global_transform
			ship_transform.origin -= ship_transform.basis.y * StarSeaShip.FOOT_HEIGHT
			var gap: float = camera.global_position.distance_to(ship_transform.origin)
			if gap < RANGE:
				candidates.append({"key": "ship", "transform": ship_transform, "size": Vector3(3.3, 1.1, 6.8), "distance": gap})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	var wanted: Dictionary = {}
	for index: int in mini(candidates.size(), LIMIT):
		var record: Dictionary = candidates[index]
		var key: String = record["key"]
		wanted[key] = true
		if not _active.has(key):
			var decal: Decal = Decal.new()
			decal.texture_albedo = _texture
			decal.albedo_mix = 1.0
			decal.normal_fade = 0.8
			decal.distance_fade_enabled = true
			decal.distance_fade_begin = 60.0
			decal.distance_fade_length = 20.0
			add_child(decal)
			_active[key] = decal
		var decal: Decal = _active[key]
		decal.global_transform = record["transform"]
		decal.size = record["size"]
	for key: String in _active.keys():
		if not wanted.has(key):
			(_active[key] as Decal).queue_free()
			_active.erase(key)


static func register(source: Node3D, records: Array[Dictionary]) -> void:
	if records.is_empty():
		return
	source.set_meta("contact_records", records)
	source.add_to_group("contact_shadow_sources")
