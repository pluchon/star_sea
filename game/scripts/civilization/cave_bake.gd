class_name CaveBake
extends RefCounted

const SAMPLE: float = 8.0 # 离线约束检查沿通道每八米采样。


static func fit(noise: TerrainNoise, data: CivilizationData) -> Dictionary:
	var town: Vector3 = data.town["direction"]
	var forward: Vector3 = SurfaceSites.tangent_forward(town)
	var attempts: int = 0
	var failures: Dictionary = {}
	for distance: int in range(1000, 2001, 50):
		for degrees: int in range(0, 360, 2):
			var direction: Vector3 = SurfaceSites.offset_direction(town, forward.rotated(town, deg_to_rad(degrees)), distance, noise.radius)
			var elevation: float = noise.height(direction)
			if elevation < 70 or elevation > 2400 or noise.slope(direction, elevation) < 0.7 or noise.river_distance(direction) < 30:
				continue
			var tangent: Vector3 = SurfaceSites.tangent_forward(direction)
			var side: Vector3 = tangent.cross(direction).normalized()
			var dx: float = noise.height(SurfaceSites.offset_direction(direction, side, 5, noise.radius)) - noise.height(SurfaceSites.offset_direction(direction, -side, 5, noise.radius))
			var dz: float = noise.height(SurfaceSites.offset_direction(direction, tangent, 5, noise.radius)) - noise.height(SurfaceSites.offset_direction(direction, -tangent, 5, noise.radius))
			var inward: Vector3 = (side * dx + tangent * dz).normalized()
			if inward.dot(town.slide(direction).normalized()) > -0.15:
				continue
			for variant: int in 32:
				attempts += 1
				var z: Vector3 = inward
				var frame: Transform3D = Transform3D(Basis(direction.cross(z), direction, z), direction * (noise.radius + elevation))
				var network: Dictionary = CaveTemplates.echo()
				network["frame"] = frame
				var nodes: Array = network["nodes"]
				var rotation: float = (1.0 if variant % 2 == 0 else -1.0) * (variant / 2) * 1.35 / 15.0
				for index: int in range(2, nodes.size()):
					if index != 9:
						nodes[index]["local"] = (Vector3(nodes[index]["local"]) - Vector3(0, 0, 20)).rotated(Vector3.UP, rotation) + Vector3(0, 0, 20)
				var mouth: Vector3 = frame * Vector3(nodes[9]["local"])
				var mouth_ground: Vector3 = mouth.normalized() * (noise.radius + noise.height(mouth.normalized()))
				var local_mouth: Vector3 = frame.affine_inverse() * mouth_ground
				if absf(local_mouth.y + 18) > 35:
					continue
				nodes[9]["local"] = local_mouth
				for node: Dictionary in nodes:
					node["position"] = frame * Vector3(node["local"])
					node["floor"] = Vector3(node["position"]).length() - noise.radius
				var hall: Vector3 = nodes[4]["position"]
				var sky: Vector3 = hall.normalized() * (noise.radius + noise.height(hall.normalized()))
				if sky.distance_to(hall) < 25 or sky.distance_to(hall) > 65 or noise.slope(sky.normalized(), noise.height(sky.normalized())) > 0.4:
					continue
				var result: Dictionary = constraints(noise, network, data)
				if result["passed"]:
					network["constraints"] = result
					network["attempts"] = attempts
					print("回声洞拟合：%d 次，距城 %.1f 米，顶板最薄 %.2f 米" % [attempts, direction.angle_to(town) * noise.radius, result["minimum_roof_m"]])
					return network
				var reason: String = result["reason"]
				failures[reason] = int(failures.get(reason, 0)) + 1
	push_error("回声洞没有符合约束的位置：%d 次，%s" % [attempts, str(failures)])
	return {}


static func constraints(noise: TerrainNoise, network: Dictionary, data: CivilizationData) -> Dictionary:
	var frame: Transform3D = network["frame"]
	var nodes: Array = network["nodes"]
	var minimum_roof: float = INF
	var maximum_slope: float = 0.0
	var minimum_floor: float = INF
	var length_value: float = 0.0
	for edge: Dictionary in network["edges"]:
		var a: Vector3 = nodes[edge["a"]]["local"]
		var b: Vector3 = nodes[edge["b"]]["local"]
		if edge["profile"] == "shaft":
			continue
		var horizontal: float = Vector2(a.x - b.x, a.z - b.z).length()
		var slope: float = absf(a.y - b.y) / maxf(horizontal, 0.01)
		maximum_slope = maxf(maximum_slope, slope)
		length_value += a.distance_to(b)
		if slope > 0.35:
			return {"passed": false, "reason": "通道坡度"}
		var count: int = ceili(a.distance_to(b) / SAMPLE)
		for index: int in count + 1:
			var p: Vector3 = a.lerp(b, index / float(count))
			var world: Vector3 = frame * p
			minimum_floor = minf(minimum_floor, world.length() - noise.radius)
			if world.length() - noise.radius < 5:
				return {"passed": false, "reason": "海拔"}
			var roof: Vector3 = frame * (p + Vector3.UP * float(edge["height"]))
			var thickness: float = noise.radius + noise.height(roof.normalized()) - roof.length()
			if minf(p.distance_to(nodes[0]["local"]), p.distance_to(nodes[9]["local"])) > 30:
				minimum_roof = minf(minimum_roof, thickness)
				if thickness < 6:
					return {"passed": false, "reason": "顶板"}
			if noise.water_surface(roof.normalized()) > -INF and thickness < 15:
				return {"passed": false, "reason": "水系"}
			for site: Dictionary in [data.town, data.ladder]:
				if world.normalized().angle_to(site["direction"]) * noise.radius < 60:
					return {"passed": false, "reason": "遗迹"}
			for beacon: Dictionary in data.beacons:
				if world.normalized().angle_to(beacon["direction"]) * noise.radius < 60:
					return {"passed": false, "reason": "烽火塔"}
	for node: Dictionary in nodes:
		if node["kind"] != "chamber":
			continue
		for angle: int in 9:
			var p: Vector3 = Vector3(node["local"]) + Vector3(sin(angle * TAU / 8), 0, cos(angle * TAU / 8)) * float(node["radius"]) * (0.8 if angle < 8 else 0.0) + Vector3.UP * float(node["height"])
			var world: Vector3 = frame * p
			if p.distance_to(nodes[0]["local"]) > 30 and noise.radius + noise.height(world.normalized()) - world.length() < 6:
				return {"passed": false, "reason": "厅室顶板"}
	return {"passed": true, "reason": "", "minimum_roof_m": minimum_roof, "maximum_floor_slope": maximum_slope, "minimum_floor_altitude_m": minimum_floor, "passages_m": length_value}


static func complete(noise: TerrainNoise, network: Dictionary) -> void:
	var frame: Transform3D = network["frame"]
	var approach: Dictionary = {}
	for length_value: int in range(64, 257, 16):
		var direction: Vector3 = (frame * Vector3(0, 0, -length_value)).normalized()
		var at: Vector3 = frame.affine_inverse() * (direction * (noise.radius + noise.height(direction)))
		var slope: float = at.y / (at.z + 8)
		approach = {"length": float(length_value), "slope": slope}
		if absf(slope) <= 0.6:
			break
	network["approach"] = approach
	var nodes: Array = network["nodes"]
	var entrances_local: PackedVector3Array = PackedVector3Array()
	for pair: Array in [[0, "gate"], [9, "mouth"]]:
		var node: Dictionary = nodes[pair[0]]
		network["entrances"].append({"node": pair[0], "kind": pair[1], "position": Vector3(node["position"]) + frame.basis.y * 3, "normal": -frame.basis.z, "up": frame.basis.y})
		entrances_local.append(node["local"])
	var hall: Vector3 = nodes[4]["position"]
	var sky: Vector3 = hall.normalized() * (noise.radius + noise.height(hall.normalized()))
	var top: Vector3 = frame.affine_inverse() * sky
	nodes.append({"id": "skylight", "kind": "shaft_top", "local": top, "position": sky, "floor": sky.length() - noise.radius, "radius": 4.0, "height": 8.0})
	network["edges"].append({"a": 4, "b": 12, "width": 8.0, "height": sky.distance_to(hall), "profile": "shaft", "waypoints": PackedVector3Array()})
	network["entrances"].append({"node": 12, "kind": "skylight", "position": sky, "normal": sky.normalized(), "up": sky.normalized(), "depth": sky.distance_to(hall)})
	entrances_local.append(top)
	network["entrances_local"] = entrances_local
	var primitives: Array[Dictionary] = []
	for edge: Dictionary in network["edges"]:
		var a: Vector3 = nodes[edge["a"]]["local"]
		var b: Vector3 = nodes[edge["b"]]["local"]
		var shaft: bool = edge["profile"] == "shaft"
		if edge["a"] == 0:
			# 端帽必须位于洞外缓坡下方，不能在平段末端留下阻挡步行的矮坎。
			a.z -= 16
		if edge["b"] == 9:
			b.z -= 8
		if shaft:
			a += Vector3.UP * 4
			b += Vector3.UP * 8
		primitives.append(_primitive(a, b, float(edge["width"]) * 0.5, edge["height"], edge["profile"] == "carved", shaft, edge["profile"] == "stream"))
	for node: Dictionary in nodes:
		if node["kind"] == "chamber":
			var point: Vector3 = node["local"]
			primitives.append(_primitive(point, point, node["radius"], node["height"], node["id"] != "niches"))
	network["primitives"] = primitives
	network["echo_anchor"] = hall + frame.basis.y * 0.15
	# 出口位于两根柱子之间，并投影到真实地面，不能假设井口周围同高。
	var exit_heading: Vector3 = frame.basis.x.rotated(sky.normalized(), PI / 8).slide(sky.normalized()).normalized()
	var rope_bottom: Vector3 = hall + exit_heading * 2.8 + frame.basis.y * 0.5
	var rope_top: Vector3 = sky + exit_heading * 2.8
	var exit_direction: Vector3 = SurfaceSites.offset_direction(sky.normalized(), exit_heading, 6.8, noise.radius)
	var exit_top: Vector3 = exit_direction * (noise.radius + noise.height(exit_direction) + 0.1)
	network["climbs"].append({"id": "cave_0_skylight", "kind": "rope", "bottom": rope_bottom, "top": rope_top, "width": 0.6, "normal": exit_heading, "exit_top": exit_top})
	_prop(network, "temple_gate", Vector3(0, -0.1, -1), 0, Vector3(2, 1, 1))
	_prop(network, "cave_mouth", nodes[9]["local"], 0)
	for sign_value: float in [-1.0, 1.0]:
		_prop(network, "statue_broken", Vector3(sign_value * 7, 0, -4), 0)
	_prop(network, "stele", Vector3(nodes[1]["local"]) + Vector3(4, 0, 0), PI)
	_prop(network, "statue_kneel", Vector3(nodes[4]["local"]) + Vector3(0, 0, 11), PI, Vector3.ONE * 2)
	# 柱廊与侧廊按实际拟合方向摆放，地面从同一条边线性取高。
	for edge_index: int in [1, 2, 4]:
		var edge: Dictionary = network["edges"][edge_index]
		var a: Vector3 = nodes[edge["a"]]["local"]
		var b: Vector3 = nodes[edge["b"]]["local"]
		var heading: Vector3 = a.direction_to(b)
		var side: Vector3 = heading.cross(Vector3.UP).normalized()
		var length_value: float = a.distance_to(b)
		var angle: float = atan2(-heading.x, -heading.z)
		for distance: int in range(8, floori(length_value), 8):
			var p: Vector3 = a.lerp(b, distance / length_value)
			if edge_index == 1:
				for sign_value: float in [-1, 1]:
					_prop(network, "column_broken" if distance % 24 == 0 and sign_value > 0 else "column", p + side * sign_value * 2.1, angle, Vector3.ONE * 0.7)
			if distance % 16 == 0:
				_prop(network, "lamp_post", p + side * 1.8, angle, Vector3.ONE * 0.5)
				network["lights"].append({"position": frame * (p + side * 1.8 + Vector3.UP * 2.5), "range": 5.0, "color": Color("f2b45a"), "kind": "glyph_lamp"})
	for index: int in 6:
		var angle: float = index * TAU / 6 + 0.2
		var p: Vector3 = Vector3(nodes[4]["local"]) + Vector3(sin(angle) * 15.9, 2, cos(angle) * 15.9)
		_prop(network, "mural_panel", p, angle, Vector3.ONE * 0.8)
	for node_index: int in [1, 4]:
		var center: Vector3 = nodes[node_index]["local"]
		var radius: float = float(nodes[node_index]["radius"]) - 1.5
		for x: int in range(-floori(radius), floori(radius) + 1, 2):
			for z: int in range(-floori(radius), floori(radius) + 1, 2):
				if Vector2(x, z).length() > radius or posmod(x * 37 + z * 17, 19) == 0:
					continue
				var wide: bool = posmod(x, 4) == 0 and absf(x + 2) + absf(z) < radius - 2
				if posmod(x, 4) == 2 and absf(x - 2) + absf(z) < radius - 2:
					continue
				_prop(network, "floor_slab", center + Vector3(x + (1 if wide else 0), -0.30, z), 0, Vector3(1.96 if wide else 0.97, 1, 0.96))
				network["props"][-1]["collision"] = false
	for index: int in 12:
		var angle: float = index * TAU / 12
		_prop(network, "stele", Vector3(nodes[7]["local"]) + Vector3(sin(angle) * 8.0, 0, cos(angle) * 8.0), angle)
	for index: int in 8:
		var angle: float = index * TAU / 8
		var direction: Vector3 = SurfaceSites.offset_direction(sky.normalized(), frame.basis.x.rotated(sky.normalized(), angle), 6.5, noise.radius)
		var p: Vector3 = frame.affine_inverse() * (direction * (noise.radius + noise.height(direction)))
		_prop(network, "column_broken" if index in [1, 4, 6] else "column", p, angle, Vector3.ONE * 0.7)
	network["lights"].append({"position": sky, "target": hall, "range": sky.distance_to(hall) + 5, "color": Color("fff0d2"), "kind": "shaft"})
	# 回廊塌方保留一侧一点六米以上净宽，不用完整石堆堵住唯一环路。
	var loop: Vector3 = Vector3(nodes[10]["local"]).lerp(nodes[11]["local"], 0.5)
	var side: Vector3 = Vector3(nodes[10]["local"]).direction_to(nodes[11]["local"]).cross(Vector3.UP).normalized()
	_prop(network, "rubble", loop + side * 2.7, 0, Vector3.ONE * 0.45)
	network["waters"].append({"edges": PackedInt32Array([7, 8]), "width": 1.5, "depth": 0.3})
	network["map_nodes"] = []
	for edge_index: int in network["edges"].size():
		var edge: Dictionary = network["edges"][edge_index]
		var a: Dictionary = nodes[edge["a"]]
		var b: Dictionary = nodes[edge["b"]]
		var count: int = ceili(Vector3(a["local"]).distance_to(b["local"]) / 16.0)
		var points: Array[Dictionary] = [a]
		for index: int in range(1, count):
			var p: Vector3 = Vector3(a["local"]).lerp(b["local"], index / float(count))
			var point: Dictionary = {"id": "edge_%d_%d" % [edge_index, index], "local": p, "position": frame * p, "kind": "bend"}
			points.append(point)
			network["map_nodes"].append(point)
		points.append(b)
		edge["map_points"] = points


static func _primitive(a: Vector3, b: Vector3, radius: float, height: float, carved: bool, shaft: bool = false, wet: bool = false) -> Dictionary:
	var bounds: AABB = AABB(a, Vector3.ZERO).expand(b)
	bounds.position -= Vector3(radius + 2, radius + 2 if shaft else 2, radius + 2)
	bounds.size += Vector3(2 * radius + 4, 2 * radius + 4 if shaft else height + 4, 2 * radius + 4)
	return {"a": a, "b": b, "radius": radius, "height": height, "carved": carved, "shaft": shaft, "wet": wet, "bounds": bounds}


static func _prop(network: Dictionary, piece: String, local: Vector3, angle: float, scale_value: Vector3 = Vector3.ONE) -> void:
	network["props"].append({"piece": piece, "transform": Transform3D(network["frame"]) * Transform3D(Basis(Vector3.UP, angle).scaled(scale_value), local), "moss": 0.3, "sand": 0.0, "awake": 0.15})
