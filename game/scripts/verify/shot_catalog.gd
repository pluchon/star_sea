class_name ShotCatalog
extends RefCounted

const NAMES: Array[String] = [
	"s1_space",
	"s2_high",
	"s3_ground_day",
	"s4_ground_sunset",
	"s5_ground_night",
	"s6_shore",
	"s7_ember",
	"s8_frost",
	"s9_woodland",
	"s10_highland",
	"s11_orbit",
	"s12_ruin",
	"s13_tree_detail",
	"s14_third_person",
	"s15_relief_map",
	"s16_terrace",
	"s17_valley",
	"s18_meadow",
	"s19_broadleaf",
	"s20_wetland",
	"s21_drygrass",
	"s22_tundra",
	"s23_ship_parked",
	"s24_ship_low",
	"s25_waterfall",
	"s28_canyon",
	"s29_ruin_kit",
	"s29b_figures",
	"s29c_details",
	"s29c_details_side",
	"s29d_silhouette",
	"s49_range_from_spawn",
	"s50_horn_peak",
	"s51_canyon_rim",
	"s52_canyon_floor",
	"s53_mountain_pass",
	"s54_glide_canyon",
	"s54b_glide_first_person",
	"s55_glide_range",
	"s56_climb_route",
	"s56b_boardwalk",
	"s30_town_plaza",
	"s31_town_overview",
	"s32_terraces",
	"s33_cemetery",
	"s34_old_road",
	"s35_beacon_top",
	"s36_beacon_chain_night",
	"s37_temple_gate",
	"s38_temple_hall",
]


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	if name == "s7_ember" or name == "s8_frost":
		planet = planet.get_parent().get_node("PlanetEmber" if name == "s7_ember" else "PlanetFrost") as Planet
	var up: Vector3 = planet.site["direction"]
	var forward: Vector3 = planet.site["forward"]
	var height: float = planet.surface_radius(up)
	player.mode = StarSeaPlayer.Mode.FLY
	player.controls_enabled = false
	player.simulated_forward = false
	player.set_third_person(false)
	director.time_paused = true
	match name:
		"s37_temple_gate", "s38_temple_hall":
			CaveShots.place(name, player, planet, director)
		"s30_town_plaza", "s31_town_overview", "s32_terraces", "s33_cemetery", "s34_old_road", "s35_beacon_top", "s36_beacon_chain_night":
			CivilizationShots.place(name, player, planet, director)
		"s54_glide_canyon", "s54b_glide_first_person", "s55_glide_range", "s56_climb_route", "s56b_boardwalk":
			TraversalShots.place(name, player, planet, director)
		"s49_range_from_spawn", "s50_horn_peak", "s51_canyon_rim", "s52_canyon_floor", "s53_mountain_pass":
			LandformShots.place(name, player, planet, director)
		"s25_waterfall", "s28_canyon":
			var data: HydrologyData = planet.noise.features.hydrology.data
			var nearest: int = -1
			var distance: float = INF
			var flag: int = 1 if name == "s25_waterfall" else 2
			for index: int in data.river_flags.size():
				if data.river_flags[index] & flag and up.distance_squared_to(data.river_points[index]) < distance:
					distance = up.distance_squared_to(data.river_points[index])
					nearest = index
			assert(nearest >= 0, "没有找到瀑布或峡谷机位。")
			up = data.river_points[nearest]
			forward = SurfaceSites.tangent_forward(up)
			var side: Vector3 = forward.cross(up)
			if flag == 1:
				forward = (data.river_points[nearest + 1] - up).slide(up).normalized()
				side = forward.cross(up).normalized()
			var eye_up: Vector3 = SurfaceSites.offset_direction(up, side, 40.0 if flag == 1 else 100.0, planet.radius)
			if flag == 1:
				eye_up = (up * planet.radius + forward * 35.0 + side * (data.river_widths[nearest] + 8.0)).normalized()
			player.place_at(planet.to_global(eye_up * (planet.surface_radius(eye_up) + (2.0 if flag == 1 else 70.0))), -side, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.to_global(up * (planet.radius + data.river_levels[nearest] + 3.0))), eye_up)
			director.set_sun_altitude(up, (-forward + side).normalized(), 32.0)
		"s29_ruin_kit", "s29b_figures", "s29c_details", "s29c_details_side", "s29d_silhouette":
			var showcase: RuinShowcase = RuinShowcase.new()
			planet.add_child(showcase)
			showcase.build(planet, name)
			var eye: Vector3 = Vector3(0, 105, 75)
			var target: Vector3 = Vector3.ZERO
			if name != "s29_ruin_kit":
				# 正交展示仅看近景；星球级远裁剪面会损失薄布料的深度精度。
				player.set_process(false)
				player.set_physics_process(false)
				player.camera.near = 0.15
				player.camera.far = 200.0
				player.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				player.camera.size = 11.5 if name == "s29b_figures" else 15.0
				eye = Vector3(7, 5.5, -21) if name == "s29b_figures" else Vector3(0, 6, -28)
				target = Vector3(0, 2, 0)
				if name == "s29c_details_side":
					eye = Vector3(16, 8, -23)
			player.place_at(showcase.to_global(eye), forward, up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(showcase.to_global(target)), up)
			if name == "s29d_silhouette":
				player.camera.size = 6.0
				eye = Vector3(0, 2.5, -12)
				target = Vector3(0, 2.3, 0)
				player.place_at(showcase.to_global(eye), forward, up)
				player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(showcase.to_global(target)), up)
			var light_forward: Vector3 = -forward if name in ["s29_ruin_kit", "s29d_silhouette"] else forward
			director.set_sun_altitude(up, (light_forward + forward.cross(up)).normalized(), 18.0 if name in ["s29b_figures", "s29d_silhouette"] else 35.0)
		"s23_ship_parked":
			player.place_at(planet.to_global(up * (height + 0.05)), forward, up)
			player.mode = StarSeaPlayer.Mode.WALK
			player.park_ship_nearby()
			var anchor: Vector3 = player.ship.position
			var eye: Vector3 = anchor - player.ship.basis.x * 9.0 - player.ship.basis.z * 10.0
			var eye_up: Vector3 = eye.normalized()
			var eye_world: Vector3 = planet.to_global(eye_up * (planet.surface_radius(eye_up) + 0.05))
			var toward_ship: Vector3 = eye_world.direction_to(player.ship.global_position)
			toward_ship = (toward_ship - eye_up * toward_ship.dot(eye_up)).normalized()
			player.place_at(eye_world, toward_ship, eye_up)
			player.set_third_person(true)
			director.set_sun_altitude(up, -forward, 32.0)
		"s24_ship_low":
			player.place_at(planet.to_global(up * (height + 80.0)), forward, up)
			player.set_third_person(true)
			player.set_head_pitch(-0.12)
			director.set_sun_altitude(up, -forward, 32.0)
		"s18_meadow", "s19_broadleaf", "s20_wetland", "s21_drygrass", "s22_tundra":
			var biome: String = {"s18_meadow": "草甸", "s19_broadleaf": "阔叶林", "s20_wetland": "湿地", "s21_drygrass": "干草地", "s22_tundra": "高山苔原"}[name]
			up = SurfaceSites.find_biome(planet.noise, biome)
			assert(up != Vector3.ZERO, "没有找到群系验收机位：" + biome)
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 1.0), forward, up)
			director.set_sun_altitude(up, (-forward + forward.cross(up)).normalized(), 38.0)
		"s14_third_person", "s15_relief_map":
			player.place_at(planet.global_position + up * (height + 0.1), forward, up)
			player.mode = StarSeaPlayer.Mode.WALK
			player.set_third_person(name == "s14_third_person")
			player.set_head_pitch(-0.12 if name == "s14_third_person" else 0.0)
			director.set_sun_altitude(up, -forward, 35.0)
		"s16_terrace", "s17_valley":
			up = SurfaceSites.find_landform(planet.noise, "台地" if name == "s16_terrace" else "峡谷")
			assert(up != Vector3.ZERO, "地貌机位没有找到实际地形。")
			forward = SurfaceSites.tangent_forward(up)
			var eye_up: Vector3 = SurfaceSites.offset_direction(up, forward, 380.0, planet.radius)
			player.place_at(planet.global_position + eye_up * (planet.surface_radius(eye_up) + 220.0), -forward, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.global_position + up * (planet.surface_radius(up) + 25.0)), eye_up)
			director.set_sun_altitude(up, (-forward + forward.cross(up)).normalized(), 26.0)
		"s12_ruin":
			var ruin_up: Vector3 = SurfaceSites.ruin_direction(planet.site, planet.radius)
			var ruin_position: Vector3 = planet.global_position + ruin_up * (planet.surface_radius(ruin_up) - 0.3)
			var eye_up: Vector3 = SurfaceSites.offset_direction(ruin_up, forward, 9.0, planet.radius)
			var eye: Vector3 = planet.global_position + eye_up * (planet.surface_radius(eye_up) + 1.0)
			player.place_at(eye, -forward, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(ruin_position + ruin_up * 2.6), eye_up)
			director.set_sun_altitude(ruin_up, (forward + forward.cross(ruin_up)).normalized(), 35.0)
		"s13_tree_detail":
			var cells: Array[Vector3i] = SurfaceGrid.nearby(up, planet.radius, 200.0, SurfaceDetails.FOREST_DIVISIONS)
			var target: Vector3 = Vector3.ZERO
			var closest: float = INF
			var origin: Vector3 = up * planet.surface_radius(up)
			for cell: Vector3i in cells:
				var generated: Dictionary = SurfaceDetails.generate(planet.noise, Vector4i(SurfaceDetails.FOREST_DIVISIONS, cell.x, cell.y, cell.z), planet.planet_seed, up, SurfaceSites.ruin_direction(planet.site, planet.radius))
				for transform: Transform3D in (generated["broadleaf"] as Array) + (generated["pine"] as Array):
					var position: Vector3 = (generated["center"] as Vector3) + transform.origin
					if position.distance_to(origin) < closest:
						closest = position.distance_to(origin)
						target = position
			assert(target != Vector3.ZERO, "树木近景机位缺少树木。")
			up = target.normalized()
			var eye_up: Vector3 = SurfaceSites.offset_direction(up, forward, 11.0, planet.radius)
			player.place_at(planet.global_position + eye_up * (planet.surface_radius(eye_up) + 1.0), -forward, eye_up)
			player.camera.global_basis = Basis.looking_at(player.camera.global_position.direction_to(planet.global_position + target + up * 4.5), eye_up)
			director.set_sun_altitude(up, (forward + forward.cross(up)).normalized(), 38.0)
		"s7_ember", "s8_frost":
			player.place_at(planet.global_position + up * (height + 2.0), forward, up)
			director.set_sun_altitude(up, -forward, 25.0)
		"s1_space":
			var giant: Node3D = planet.get_parent().get_node("GasGiant") as Node3D
			var giant_direction: Vector3 = (giant.global_position - planet.global_position).normalized()
			up = (up - giant_direction * 0.6).normalized()
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * 160000.0, forward, up)
			var to_planet: Vector3 = player.camera.global_position.direction_to(planet.global_position)
			var to_giant: Vector3 = player.camera.global_position.direction_to(giant.global_position)
			player.camera.global_basis = Basis.looking_at((to_planet * 0.65 + to_giant * 0.35).normalized(), Vector3.UP)
			var side: Vector3 = up.cross(Vector3.UP).normalized()
			director.sun_direction = (up * 0.5 + side * sqrt(0.75)).normalized()
		"s2_high":
			player.place_at(planet.global_position + up * (height + 12000.0), forward, up)
			player.camera.rotation.x = deg_to_rad(-8.0)
			director.set_sun_altitude(up, -forward, 35.0)
		"s3_ground_day":
			player.place_at(planet.global_position + up * height, forward, up)
			director.set_sun_altitude(up, -forward, 40.0)
		"s4_ground_sunset":
			player.place_at(planet.global_position + up * height, forward, up)
			var right: Vector3 = forward.cross(up).normalized()
			director.set_sun_altitude(up, (-forward + right).normalized(), 3.0)
		"s5_ground_night":
			player.place_at(planet.global_position + up * height, forward, up)
			player.camera.rotation.x = deg_to_rad(35.0)
			director.set_sun_altitude(up, -forward, -30.0)
		"s9_woodland":
			up = SurfaceSites.find_woodland(planet.noise, up)
			forward = SurfaceSites.tangent_forward(up)
			var best_height: float = -INF
			var reference: Vector3 = forward
			for heading: int in 16:
				var tangent: Vector3 = reference.rotated(up, heading * TAU / 16.0)
				var inland_height: float = planet.noise.height(SurfaceSites.offset_direction(up, tangent, 150.0, planet.radius))
				if inland_height > best_height:
					best_height = inland_height
					forward = tangent
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 1.0), forward, up)
			director.set_sun_altitude(up, (-forward + forward.cross(up)).normalized(), 28.0)
		"s10_highland":
			up = planet.site["mountain_direction"]
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * (planet.surface_radius(up) + 180.0), forward, up)
			player.camera.rotation.x = deg_to_rad(-18.0)
			director.set_sun_altitude(up, forward.cross(up).normalized(), 22.0)
		"s11_orbit":
			up = -up
			forward = SurfaceSites.tangent_forward(up)
			player.place_at(planet.global_position + up * (planet.radius + 80000.0), forward, up)
			player.camera.global_basis = Basis.looking_at(-up, forward)
			director.set_sun_altitude(up, forward, 12.0)
		"s6_shore":
			up = planet.site["shore_direction"]
			forward = planet.site["shore_forward"]
			player.place_at(planet.global_position + up * planet.surface_radius(up), forward, up)
			director.set_sun_altitude(up, -forward, 25.0)
