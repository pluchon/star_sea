class_name LandformShots
extends RefCounted


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
