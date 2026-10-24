class_name ClimbLayout
extends RefCounted

const LAYOUT_PATH: String = "res://data/dawn_layout.tres"
const FACE_MIN_GRADE: float = 1.0 # 宽岩壁从坡度一处进入攀爬，覆盖改宽后不足二的坡面。
const EXIT_RUNOUT: float = 6.0 # 末段延至缓坡，避免出口仍停在陡壁上。


static func generate(noise: TerrainNoise) -> Dictionary:
	var zones: Array[Dictionary] = []
	var placements: Array[Dictionary] = []
	var site: Dictionary = noise.features.site
	var up: Vector3 = SurfaceSites.ruin_direction(site, noise.radius)
	var frame: Basis = Basis.looking_at(site["forward"], up)
	# 拱门侧面的残墙属于同一处遗迹，不在出发地空地里增加物件。
	var wall_point: Vector3 = up * (noise.radius + noise.height(up)) + frame.x * 6.0
	wall_point = surface(noise, wall_point.normalized())
	var height: float = RuinKit.mesh("wall").get_aabb().size.y
	var wall: Transform3D = Transform3D(frame, wall_point)
	placements.append({"piece": "wall", "transform": wall, "moss": 0.6})
	var normal: Vector3 = -frame.z
	var bottom: Vector3 = wall_point + normal * 0.45
	var top: Vector3 = bottom + up * height
	zones.append(record("spawn_vines", "vine_wall", bottom, top, 2.5, normal, wall_point + up * (height + 0.05)))
	for landmark: Dictionary in noise.features.landmarks:
		if landmark["kind"] != "peak_tower":
			continue
		var direction: Vector3 = noise.features.direction_at(landmark["point"])
		var heading: Vector3 = noise.features.axis_u * cos(landmark["facing"]) + noise.features.axis_v * sin(landmark["facing"])
		var orientation: Basis = Basis.looking_at(heading.slide(direction).normalized(), direction)
		var ground: Vector3 = surface(noise, direction) - direction * 1.5
		var roof: float = int(float(landmark["height"]) / 0.95) * 0.95
		var half: float = landmark["radius"]
		var base: Vector3 = ground + orientation.z * (half + 0.65)
		bottom = surface(noise, base.normalized()) + orientation.z * 0.05
		top = base + direction * (roof + 0.15)
		zones.append(record("peak_rope", "rope", bottom, top, 0.6, orientation.z, ground + direction * (roof + 0.05) + orientation.z * (half - 0.6)))
	var forms: DawnLandforms = noise.features.landforms
	var center: Vector3 = forms.canyon[6].slerp(forms.canyon[7], 0.5).normalized()
	var heading: Vector3 = forms.canyon[6].direction_to(forms.canyon[7]).slide(center).normalized()
	var side: Vector3 = heading.cross(center).normalized()
	var runs: Array[Vector2i] = []
	var first: int = -1
	for meter: int in range(400, 1400):
		var a: Vector3 = SurfaceSites.offset_direction(center, side, meter, noise.radius)
		var b: Vector3 = SurfaceSites.offset_direction(center, side, meter + 1, noise.radius)
		var steep: bool = noise.height(b) - noise.height(a) > FACE_MIN_GRADE
		if steep and first < 0:
			first = meter
		elif not steep and first >= 0:
			var rise: float = noise.height(a) - noise.height(SurfaceSites.offset_direction(center, side, first, noise.radius))
			if rise > 35.0:
				runs.append(Vector2i(first, meter))
			first = -1
	# 两级岩壁分成三段，第一道岩壁中部加一处石质休息台。
	var selected: Array[Vector2i] = []
	for start: int in maxi(runs.size() - 1, 0):
		var gain: float = 0.0
		for index: int in range(start, start + 2):
			gain += noise.height(SurfaceSites.offset_direction(center, side, runs[index].y, noise.radius)) - noise.height(SurfaceSites.offset_direction(center, side, runs[index].x, noise.radius))
		if gain >= 120.0 and gain <= 200.0:
			var middle: int = (runs[start].x + runs[start].y) / 2
			selected.assign([Vector2i(runs[start].x, middle), Vector2i(middle, runs[start].y), runs[start + 1]])
			break
	assert(selected.size() == 3, "峡谷没有找到 120～200 米的三级攀爬路线。")
	for index: int in selected.size():
		var run: Vector2i = selected[index]
		if index == selected.size() - 1:
			run.y += int(EXIT_RUNOUT)
		var low: Vector3 = SurfaceSites.offset_direction(center, side, run.x, noise.radius)
		var high: Vector3 = SurfaceSites.offset_direction(center, side, run.y, noise.radius)
		bottom = surface(noise, low)
		top = surface(noise, high) + high * 0.15
		normal = (-side).slide(bottom.direction_to(top)).normalized()
		# 休息台放在线路侧边，给攀爬胶囊的头部留出净空，避免先撞到台板底面。
		var exit: Vector3 = (top + normal * 0.9 + heading * (1.6 if index == 0 else -1.6) + high * 0.05) if index < 2 else surface(noise, SurfaceSites.offset_direction(center, side, run.y + 2, noise.radius)) + high * 0.05
		var route: Dictionary = record("canyon_route_" + str(index), "climb_route", bottom, top, 2.0, normal, exit)
		var path: PackedVector3Array = []
		var normals: PackedVector3Array = []
		var lengths: PackedFloat32Array = [0.0]
		var steps: int = maxi(2, (run.y - run.x) * 5)
		for step: int in steps + 1:
			var direction: Vector3 = SurfaceSites.offset_direction(center, side, lerpf(run.x, run.y, step / float(steps)), noise.radius)
			path.append(surface(noise, direction))
			if step > 0:
				lengths.append(lengths[-1] + path[step - 1].distance_to(path[step]))
		for step: int in path.size():
			var tangent: Vector3 = path[maxi(step - 1, 0)].direction_to(path[mini(step + 1, path.size() - 1)])
			normals.append((-side).slide(tangent).normalized())
		route["path"] = path
		route["path_normals"] = normals
		route["path_lengths"] = lengths
		zones.append(route)
		if index < 2:
			var slab: Transform3D = Transform3D(Basis.looking_at(heading.slide(high).normalized(), high), exit - high * 0.42)
			placements.append({"piece": "floor_slab", "transform": slab, "moss": 0.4})
	var start: Vector3 = forms.canyon[6]
	var segment: float = start.angle_to(forms.canyon[7]) * noise.radius
	var gap_path: Vector3 = start.slerp(forms.canyon[7], (10.0 + 83 * 12.0) / segment).normalized()
	heading = start.direction_to(forms.canyon[7]).slide(gap_path).normalized()
	var gap: Vector3 = SurfaceSites.offset_direction(gap_path, heading.cross(gap_path).normalized(), 850.0, noise.radius)
	var lower: Array[Vector3] = []
	for sign_value: float in [-1.0, 1.0]:
		var edge: Vector3 = SurfaceSites.offset_direction(gap, heading, sign_value * 6.4, noise.radius)
		normal = -heading.cross(edge).normalized()
		var deck: Vector3 = surface(noise, edge) + edge * 6.0
		top = deck + normal * 2.3
		bottom = top - edge * 5.0
		var exit: Vector3 = deck + heading * sign_value * 1.0 + edge * 0.05
		var vines: Dictionary = record("boardwalk_vines_" + str(int(sign_value)), "vine_wall", bottom, top, 2.0, normal, exit)
		vines["support_wall"] = true
		zones.append(vines)
		var wall_basis: Basis = Basis.looking_at(normal, edge).scaled(Vector3(1, 5.0 / 3.6, 1))
		placements.append({"piece": "wall", "transform": Transform3D(wall_basis, bottom - normal * 0.3), "moss": 0.5, "collision": false})
		lower.append(bottom)
	var bridge_up: Vector3 = gap
	var bridge_x: Vector3 = lower[0].direction_to(lower[1])
	var bridge_z: Vector3 = bridge_x.cross(bridge_up).normalized()
	var bridge_y: Vector3 = bridge_z.cross(bridge_x).normalized()
	# 两端各留 1.2 米落脚区，下降到藤蔓末端时不能恰好站在桥板端面之外。
	var bridge_basis: Basis = Basis(bridge_x * ((lower[0].distance_to(lower[1]) + 2.4) / 12.0), bridge_y, bridge_z)
	placements.append({"piece": "bridge_span", "transform": Transform3D(bridge_basis, (lower[0] + lower[1]) * 0.5 - bridge_y * 6.0), "moss": 0.2})
	return {"version": 1, "zones": zones, "placements": placements}


static func surface(noise: TerrainNoise, direction: Vector3) -> Vector3:
	return direction * (noise.radius + maxf(noise.height(direction), 0.0))


static func record(id: String, kind: String, bottom: Vector3, top: Vector3, width: float, normal: Vector3, exit: Vector3) -> Dictionary:
	return {"id": id, "kind": kind, "bottom": bottom, "top": top, "width": width, "normal": normal, "exit_top": exit, "occupied": false}
