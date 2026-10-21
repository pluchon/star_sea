class_name CaveTemplates
extends RefCounted


static func echo() -> Dictionary:
	# 局部坐标的正 Z 朝山内；固定故事节点，天然通道允许烘焙时扰动。
	var nodes: Array[Dictionary] = []
	var rows: Array = [
		["gate", Vector3.ZERO, 3.0, 6.0, "entrance"],
		["foyer", Vector3(0, 0, 20), 8.0, 8.0, "chamber"],
		["columns", Vector3(0, 0, 100), 2.5, 6.0, "bend"],
		["ramp", Vector3(0, -15, 190), 2.5, 6.0, "bend"],
		["hall", Vector3(0, -15, 210), 16.0, 14.0, "chamber"],
		["side", Vector3(60, -15, 210), 2.5, 6.0, "bend"],
		["junction", Vector3(80, -15, 210), 3.0, 7.0, "junction"],
		["niches", Vector3(105, -15, 235), 10.0, 8.0, "chamber"],
		["stream", Vector3(150, -18, 120), 3.5, 7.0, "junction"],
		["mouth", Vector3(100, -20, 0), 4.0, 8.0, "entrance"],
		["loop_a", Vector3(40, -5, 80), 3.0, 6.0, "bend"],
		["loop_b", Vector3(45, -12, 140), 3.0, 6.0, "bend"],
	]
	for row: Array in rows:
		nodes.append({"id": row[0], "local": row[1], "radius": row[2], "height": row[3], "kind": row[4]})
	var edges: Array[Dictionary] = []
	for pair: Array in [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [6, 8], [8, 9], [1, 10], [10, 11], [11, 8]]:
		var natural: bool = int(pair[0]) >= 6
		edges.append({"a": pair[0], "b": pair[1], "width": 6.0 if natural else 5.0, "height": 7.0 if natural else 6.0, "profile": "stream" if pair[1] in [8, 9] and pair[0] in [6, 8] else ("natural" if natural else "carved"), "waypoints": PackedVector3Array()})
	return {"id": 0, "name": "回声洞", "template": "echo", "nodes": nodes, "edges": edges, "entrances": [], "props": [], "lights": [], "climbs": [], "waters": []}
