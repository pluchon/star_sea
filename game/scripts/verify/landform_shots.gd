class_name LandformShots
extends RefCounted


# 对照机位从不变的布局取绝对高度，避免新旧地形自动抬高相机而失去可比性。
static func terrain_place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var features: TerrainFeatures = planet.noise.features
	var forms: DawnLandforms = features.landforms
	var up: Vector3 = features.site["direction"]
	var north: Vector3 = Vector3.UP.slide(up).normalized()
	var heading: Vector3 = north
	var eye: Vector3 = up * (planet.radius + float(features.site["height_m"]) + 1.75)
	var target: Vector3 = eye + heading * 1000.0
	var bearing: int = ["s70_spawn_north", "s71_spawn_east", "s72_spawn_south", "s73_spawn_west"].find(name)
	if bearing >= 0:
		heading = north.rotated(up, -bearing * PI * 0.5)
		target = eye + heading * 1000.0
	elif name == "s74_pass_view":
		var pass_site: Dictionary = forms.metadata["passes"][1]
		up = pass_site["direction"]
		eye = up * (planet.radius + float(pass_site["ground"]) + 504.0)
		target = eye + Vector3(pass_site["across"]) * 4000.0 - up * 200.0
	elif name == "s75_volcano":
		var center: Vector3 = features.direction_at(features.volcano)
		up = SurfaceSites.offset_direction(center, features.axis_u.slide(center).normalized(), 2000.0, planet.radius)
		eye = up * (planet.radius + features.volcano_base + 300.0)
		target = center * (planet.radius + features.volcano_base + 650.0)
	elif name == "s76_oblique_3km":
		eye += up * 3000.0
		target = Vector3(forms.metadata["peaks"][1]["direction"]) * (planet.radius + 1200.0)
	elif name == "s77_canyon_far":
		var center: Vector3 = forms.canyon[6]
		var along: Vector3 = center.direction_to(forms.canyon[7]).slide(center).normalized()
		up = SurfaceSites.offset_direction(center, along.cross(center), 2000.0, planet.radius)
		eye = up * (planet.radius + 1200.0)
		target = center * (planet.radius + 350.0)
	player.mode = StarSeaPlayer.Mode.FLY
	player.controls_enabled = false
	player.set_third_person(false)
	heading = eye.direction_to(target).slide(up).normalized()
	player.place_at(planet.to_global(eye), heading, up)
	player.camera.global_basis = Basis.looking_at(eye.direction_to(target), up)
	director.time_paused = true
	director.set_sun_altitude(features.site["direction"], features.site["forward"], 36.0)


static func place(name: String, player: StarSeaPlayer, planet: Planet, director: SkyDirector) -> void:
	var forms: DawnLandforms = planet.noise.features.landforms
	var up: Vector3 = planet.site["direction"]
	var target: Vector3 = forms.metadata["peaks"][1]["direction"]
	var lift: float = 1.75
	if name == "s50_horn_peak":
		up = SurfaceSites.offset_direction(target, forms.metadata["peaks"][1]["forward"], 3600.0, planet.radius)
		lift = 50.0
	elif name in ["s51_canyon_rim", "s52_canyon_floor"]:
		var canyon: CanyonLandmarks = planet.get_node("CanyonLandmarks") as CanyonLandmarks
		up = canyon.overlook if name == "s51_canyon_rim" else forms.canyon[6]
		target = forms.canyon[6].slerp(forms.canyon[7], 0.5).normalized() if name == "s51_canyon_rim" else forms.canyon[7]
		lift = 0.2 if name == "s51_canyon_rim" else 12.0
	elif name == "s53_mountain_pass":
		up = forms.metadata["passes"][1]["direction"]
		target = SurfaceSites.offset_direction(up, forms.metadata["passes"][1]["across"], 4000.0, planet.radius)
		lift = 4.0
	var eye: Vector3 = up * (planet.surface_radius(up) + lift)
	var destination: Vector3 = target * planet.surface_radius(target)
	if name == "s50_horn_peak":
		destination += target * 20.0
		# 山谷机位需要看见角峰，按同一高度函数排除沿视线的近壁遮挡。
		for iteration: int in 4:
			var adjustment: float = 0.0
			for sample: int in range(1, 95):
				var weight: float = sample / 100.0
				var point: Vector3 = eye.lerp(destination, weight)
				adjustment = maxf(adjustment, (planet.surface_radius(point.normalized()) + 25.0 - point.length()) / (1.0 - weight))
			eye += up * adjustment
	var heading: Vector3 = eye.direction_to(destination).slide(up).normalized()
	player.place_at(planet.to_global(eye), heading, up)
	player.camera.global_basis = Basis.looking_at(eye.direction_to(destination), up)
	director.set_sun_altitude(up, (-heading + heading.cross(up)).normalized(), 24.0 if name == "s50_horn_peak" else 42.0)
