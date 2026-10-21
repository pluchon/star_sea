class_name CaveMapView
extends Control

var system: CaveSystem
var player: StarSeaPlayer
var large: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if system == null:
		return
	var planet: Planet = system.get_parent() as Planet
	var id: int = system.data.cave_at(planet.to_local(player.global_position))
	if id < 0:
		return
	var network: Dictionary = system.data.networks[id]
	var frame: Transform3D = network["frame"]
	var point: Vector3 = frame.affine_inverse() * planet.to_local(player.global_position)
	var span: float = 380.0 if large else 170.0
	var scale_value: float = minf(size.x, size.y) / span
	var center: Vector2 = Vector2(point.x, point.z)
	if large:
		center = Vector2(60, 110)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.035, 0.60 if large else 1.0))
	for edge: Dictionary in network["edges"]:
		var points: Array = edge.get("map_points", [network["nodes"][edge["a"]], network["nodes"][edge["b"]]])
		for index: int in points.size() - 1:
			var a: Dictionary = points[index]
			var b: Dictionary = points[index + 1]
			if not system.seen.has("%d:%s" % [id, a["id"]]) or not system.seen.has("%d:%s" % [id, b["id"]]):
				continue
			var start: Vector3 = a["local"]
			var end: Vector3 = b["local"]
			var color: Color = Color(0.38, 0.44, 0.46).darkened(clampf(-minf(start.y, end.y) / 90, 0, 0.4))
			draw_line(_screen(start, center, scale_value), _screen(end, center, scale_value), color, maxf(float(edge["width"]) * scale_value, 2), true)
	for node: Dictionary in network["nodes"]:
		if not system.seen.has("%d:%s" % [id, node["id"]]):
			continue
		var at: Vector2 = _screen(node["local"], center, scale_value)
		if node["kind"] == "chamber":
			draw_circle(at, float(node["radius"]) * scale_value, Color(0.46, 0.48, 0.45), true, -1, true)
		elif node["kind"] in ["entrance", "shaft_top"]:
			draw_arc(at, 5, 0.4, TAU - 0.4, 18, Color(0.90, 0.76, 0.47), 2, true)
	var position_value: Vector2 = _screen(point, center, scale_value)
	var heading: Vector3 = frame.basis.inverse() * planet.global_basis.inverse() * -player.camera.global_basis.z
	var direction: Vector2 = Vector2(heading.x, heading.z).normalized()
	var side: Vector2 = Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([position_value + direction * 8, position_value - direction * 5 + side * 4, position_value - direction * 5 - side * 4]), Color(0.95, 0.80, 0.46))


func _screen(point: Vector3, center: Vector2, scale_value: float) -> Vector2:
	return size * 0.5 + (Vector2(point.x, point.z) - center) * scale_value
