class_name RuinBuilder
extends Node3D

const CELL: float = 128.0 # 批次格子边长，米。
var _placements: Array[Dictionary] = []
var _colliders: Dictionary = {}
var _elapsed: float = 1.0


func build(placements: Array[Dictionary]) -> void:
	_placements = placements
	var groups: Dictionary = {}
	for placement: Dictionary in placements:
		var location: Transform3D = placement["transform"]
		var cell: Vector3i = Vector3i((location.origin / CELL).floor())
		var key: String = "%s/%s" % [placement["piece"], str(cell)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(placement)
	for records: Array in groups.values():
		var piece: String = records[0]["piece"]
		var source: Mesh = RuinKit.mesh(piece)
		var mesh: ArrayMesh = source.duplicate() as ArrayMesh
		for index: int in mesh.get_surface_count():
			var kind: int = int((source.surface_get_material(index) as ShaderMaterial).get_shader_parameter("kind"))
			mesh.surface_set_material(index, RuinKit.material(kind, true))
		var anchor: Vector3 = (records[0]["transform"] as Transform3D).origin
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = records.size()
		for index: int in records.size():
			var record: Dictionary = records[index]
			var transform_value: Transform3D = record["transform"]
			transform_value.origin -= anchor
			multi.set_instance_transform(index, transform_value)
			multi.set_instance_custom_data(index, Color(record.get("moss", 0.0), record.get("sand", 0.0), record.get("awake", 0.0), record.get("base_height", 0.0)))
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.position = anchor
		var size: float = source.get_aabb().size.length()
		instance.visibility_range_end = 250.0 if size < 4.0 else (1500.0 if size < 9.0 else 0.0)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size < 4.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(instance)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.4:
		return
	_elapsed = 0.0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var position_value: Vector3 = to_local(camera.global_position)
	for index: int in _placements.size():
		var record: Dictionary = _placements[index]
		var transform_value: Transform3D = record["transform"]
		var distance: float = position_value.distance_to(transform_value.origin)
		if distance > 200.0 and _colliders.has(index):
			(_colliders[index] as StaticBody3D).queue_free()
			_colliders.erase(index)
		elif distance < 150.0 and record.get("collision", true) and not _colliders.has(index):
			var body: StaticBody3D = StaticBody3D.new()
			body.transform = transform_value
			body.collision_layer = 2
			for shape_record: Dictionary in RuinKit.collision_records(record["piece"]):
				var collision: CollisionShape3D = CollisionShape3D.new()
				collision.shape = shape_record["shape"]
				collision.transform = shape_record["transform"]
				body.add_child(collision)
			add_child(body)
			_colliders[index] = body
