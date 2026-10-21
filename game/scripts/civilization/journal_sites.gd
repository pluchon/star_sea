class_name JournalSites
extends RefCounted


static func surface(planet: Planet, direction: Vector3, forward: Vector3 = Vector3.ZERO) -> Transform3D:
	var heading: Vector3 = SurfaceSites.tangent_forward(direction) if forward.is_zero_approx() else forward.slide(direction).normalized()
	return Transform3D(Basis.looking_at(heading, direction), direction * planet.surface_radius(direction))


static func add(sites: Dictionary, id: String, title: String, frame: Transform3D, radius: float, echo: String = "") -> void:
	sites[id] = {"name": title, "frame": frame, "radius": radius, "echo": echo}


static func catalog(planet: Planet) -> Dictionary:
	var sites: Dictionary = {}
	var features: TerrainFeatures = planet.noise.features
	var data: CivilizationData = features.civilization.data
	for landmark: Dictionary in features.landmarks:
		var kind: String = landmark["kind"]
		if kind in ["sea_arch", "lighthouse", "fallen_ring"]:
			add(sites, kind, {"sea_arch": "海蚀拱门", "lighthouse": "灯塔残骸", "fallen_ring": "巨环"}[kind], surface(planet, features.direction_at(landmark["point"])), {"sea_arch": 150.0, "lighthouse": 30.0, "fallen_ring": 40.0}[kind])
	add(sites, "crater_lake", "火山口湖", surface(planet, features.direction_at(features.volcano)), features.crater_radius + 80)
	var town_direction: Vector3 = data.town["direction"]
	add(sites, "town", "河畔古城", surface(planet, town_direction, town_direction.direction_to(data.ladder["direction"])), 60, "dawn_daily")
	add(sites, "cemetery", "墓园", surface(planet, data.cemetery["direction"]), 40)
	var network: Dictionary = features.caves.networks[0]
	add(sites, "temple", "回声洞", network["frame"], 12)
	var hall: Transform3D = network["frame"]
	hall.origin = network["echo_anchor"]
	add(sites, "temple_hall", "回声洞大厅", hall, 15, "dawn_faith")
	var ladder: Transform3D = LandingPads.frame(planet)
	add(sites, "ladder_base", "天梯基座", ladder, 65, "dawn_departure")
	var balcony: Transform3D = ladder.translated_local(Vector3(0, 240, -36))
	add(sites, "ladder_balcony", "天梯观景环", balcony, 20)
	add(sites, "ladder_break", "天梯断口", ladder.translated_local(Vector3(0, LandingPads.HEIGHT, -54)), 17)
	var ordinals: Array[String] = ["第一", "第二", "第三", "第四", "第五", "第六", "第七", "第八", "第九", "第十"]
	for i: int in data.beacons.size():
		var frame: Transform3D = BeaconTowers.tower_frame(data.beacons[i], planet.radius).translated_local(Vector3(0, BeaconTowers.TOP, 0))
		add(sites, "beacon_" + str(i + 1), ordinals[i] + "座烽火塔", frame, 8, "dawn_watcher" if i == data.beacons.size() - 1 else "")
	for peak: Dictionary in features.landforms.metadata["peaks"]:
		var id: String = {"horn": "horn_peak", "twins": "twin_peaks", "mesa": "table_peak"}[peak["shape"]]
		add(sites, id, {"horn": "角峰", "twins": "双子峰", "mesa": "平顶峰"}[peak["shape"]], surface(planet, peak["direction"]), 80)
	var pass_names: Array[String] = ["北山口", "东山口", "南山口"]
	for i: int in features.landforms.metadata["passes"].size():
		add(sites, "pass_" + str(i + 1), pass_names[i % 3], surface(planet, features.landforms.metadata["passes"][i]["direction"]), 100)
	var canyon: CanyonLandmarks = planet.get_node("CanyonLandmarks") as CanyonLandmarks
	add(sites, "canyon", "大峡谷", surface(planet, canyon.overlook), 30)
	add(sites, "canyon_walkway", "崖上栈道", surface(planet, canyon.boardwalk_gap), 80)
	var hydrology: HydrologyData = features.hydrology.data
	var closest: Vector3 = Vector3.ZERO
	var minimum: float = INF
	for i: int in hydrology.river_flags.size():
		if (hydrology.river_flags[i] & 1) == 0:
			continue
		var gap: float = hydrology.river_points[i].distance_squared_to(planet.site["direction"])
		if gap < minimum:
			minimum = gap
			closest = hydrology.river_points[i]
	if not closest.is_zero_approx():
		add(sites, "waterfall_1", "白练瀑", surface(planet, closest), 30)
	return sites


static func anchors(planet: Planet, sites: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in sites:
		var site: Dictionary = sites[id]
		if String(site["echo"]).is_empty():
			continue
		var frame: Transform3D = site["frame"]
		if site["echo"] == "dawn_daily":
			frame = frame.translated_local(Vector3(0, 0.04, 12))
		if site["echo"] == "dawn_departure":
			frame = LandingPads.frame(planet).translated_local(Vector3(0, 0.05, -35))
			frame.basis *= Basis(Vector3.UP, PI)
		result[site["echo"]] = frame
	var ladder: SkyLadder = planet.get_node("SkyLadder") as SkyLadder
	var end: Vector3 = ladder.bridge_direction * 74 + Vector3.UP * LandingPads.HEIGHT
	result["dawn_ending"] = LandingPads.frame(planet) * Transform3D(Basis.looking_at(ladder.bridge_direction, Vector3.UP), end)
	return result
