class_name SkyHorizonReview
extends RefCounted


static func run(context: VersionContext) -> Dictionary:
	var environment: Environment = (context.scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var original: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	var code: String = original.shader.code
	# 分层截图只替换验证实例的材质；原着色器文件和游戏画面参数不变。
	if code.count("clouds * surface_sky * 0.92") != 1 or code.count("COLOR = col;") != 1:
		return {"passed": false, "error": "天空诊断的着色器锚点已变化，需要更新分层方法"}
	var no_clouds: ShaderMaterial = original.duplicate() as ShaderMaterial
	no_clouds.shader = Shader.new()
	no_clouds.shader.code = code.replace("clouds * surface_sky * 0.92", "0.0")
	var mask: ShaderMaterial = original.duplicate() as ShaderMaterial
	mask.shader = Shader.new()
	mask.shader.code = code.replace("COLOR = col;", "COLOR = vec3(clouds * surface_sky);")
	var results: Array[Dictionary] = []
	for shot: String in ["s3_ground_day", "s44_ladder_balcony"]:
		ShotCatalog.place(shot, context.player, context.planet, context.director)
		if not await context.settle():
			results.append({"shot": shot, "passed": false, "error": "天空复现机位加载超时"})
			continue
		await context.tree.create_timer(2.2).timeout
		var camera: Camera3D = context.player.camera
		var up: Vector3 = context.local_position().normalized()
		var forward: Vector3 = (-camera.global_basis.z).slide(up).normalized()
		if shot == "s3_ground_day":
			forward = -forward
		# 水平线固定在视野中部附近，便于比较地面与高处的地平线和云层。
		camera.global_basis = Basis.looking_at((forward * cos(deg_to_rad(6)) + up * sin(deg_to_rad(6))).normalized(), up)
		var modes: Array[Dictionary] = []
		var atmospheres: Array[Dictionary] = []
		for node: Node in context.scene.find_children("*", "", true, false):
			modes.append({"node": node, "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is GeometryInstance3D:
				var geometry: GeometryInstance3D = node as GeometryInstance3D
				var material: ShaderMaterial = geometry.material_override as ShaderMaterial
				if material != null and material.shader.resource_path == "res://shaders/atmosphere.gdshader":
					atmospheres.append({"node": geometry, "visible": geometry.visible})
		var name: String = "sky-horizon/" + shot
		var full: String = await context.capture(name + "-full")
		environment.sky.sky_material = no_clouds
		await _material_frames(context)
		var plain: String = await context.capture(name + "-no-clouds")
		environment.sky.sky_material = original
		for state: Dictionary in atmospheres:
			(state["node"] as GeometryInstance3D).visible = false
		var clear: String = await context.capture(name + "-no-atmosphere")
		environment.sky.sky_material = mask
		await _material_frames(context)
		var cloud_mask: String = await context.capture(name + "-cloud-mask")
		environment.sky.sky_material = original
		for state: Dictionary in atmospheres:
			(state["node"] as GeometryInstance3D).visible = state["visible"]
		for state: Dictionary in modes:
			(state["node"] as Node).process_mode = state["mode"]
		var altitude: float = (camera.global_position - context.planet.global_position).length() - context.planet.radius
		var depression: float = rad_to_deg(acos(context.planet.radius / maxf(context.planet.radius, context.planet.radius + altitude)))
		results.append({"shot": shot, "passed": not full.is_empty() and not plain.is_empty() and not clear.is_empty() and not cloud_mask.is_empty(), "full": full, "no_clouds": plain, "no_atmosphere": clear, "cloud_mask": cloud_mask, "camera_planet_position": camera.global_position - context.planet.global_position, "camera_basis": camera.global_basis, "camera_fov": camera.fov, "sea_altitude_m": altitude, "geometric_horizon_depression_degrees": depression})
	var projection: Dictionary = await _projection_probe(context, environment, original)
	return {"passed": results.size() == 2 and results.all(func(value: Dictionary) -> bool: return bool(value["passed"])) and bool(projection["passed"]), "results": results, "projection": projection, "visual_acceptance": null, "requires_visual_review": true, "purpose": "用户反馈的远处天空塌落感：同帧分离云层、大气与球面地平线，并检查实际云层采样投影的突变；数值通过仍需看图", "sky_source_sha256": FileAccess.get_sha256("res://shaders/sky.gdshader"), "atmosphere_source_sha256": FileAccess.get_sha256("res://shaders/atmosphere.gdshader")}


static func _projection_probe(context: VersionContext, environment: Environment, original: ShaderMaterial) -> Dictionary:
	var instrumented: ShaderMaterial = original.duplicate() as ShaderMaterial
	instrumented.shader = Shader.new()
	# 直接读取生产着色器的采样坐标导数，不另写一套云层投影公式。
	instrumented.shader.code = original.shader.code.replace("COLOR = col;", "COLOR = vec3(clamp(length(dFdy(cloud_point)) * 100.0, 0.0, 1.0));")
	var camera: Camera3D = context.player.camera
	var transform_value: Transform3D = camera.global_transform
	var fov: float = camera.fov
	var up: Vector3 = context.local_position().normalized()
	var forward: Vector3 = (-camera.global_basis.z).slide(up).normalized()
	var angle: float = asin(0.12)
	camera.global_basis = Basis.looking_at(forward * cos(angle) + up * sin(angle), up)
	camera.fov = 1.0
	var states: Array[Dictionary] = []
	for node: Node in context.scene.find_children("*", "", true, false):
		var state: Dictionary = {"node": node, "mode": node.process_mode}
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is GeometryInstance3D:
			state["visible"] = (node as GeometryInstance3D).visible
			(node as GeometryInstance3D).visible = false
		states.append(state)
	var adjustment: bool = environment.adjustment_enabled
	var tonemap: int = environment.tonemap_mode
	var glow: bool = environment.glow_enabled
	environment.adjustment_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = false
	environment.sky.sky_material = instrumented
	await _material_frames(context)
	var path: String = await context.capture("sky-horizon/projection-derivative")
	var image: Image = Image.load_from_file(path) if not path.is_empty() else null
	environment.sky.sky_material = original
	environment.adjustment_enabled = adjustment
	environment.tonemap_mode = tonemap as Environment.ToneMapper
	environment.glow_enabled = glow
	camera.global_transform = transform_value
	camera.fov = fov
	for state: Dictionary in states:
		var node: Node = state["node"]
		node.process_mode = state["mode"]
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visible = state["visible"]
	if image == null:
		return {"passed": false, "error": "无法读取云层投影诊断图"}
	var values: Array[float] = []
	for sign_value: int in [-1, 1]:
		var sum: float = 0
		var count: int = 0
		for dy: int in range(50, 151):
			for dx: int in range(-50, 51):
				sum += image.get_pixel(image.get_width() / 2 + dx, image.get_height() / 2 + sign_value * dy).srgb_to_linear().r
				count += 1
		values.append(sum / count)
	# 一度视野中相隔约 0.2 度的窄带，平滑投影不应突然改变数倍。
	var ratio: float = maxf(values[0], values[1]) / maxf(minf(values[0], values[1]), 0.00001)
	return {"passed": ratio <= 1.5, "derivative_ratio": ratio, "maximum_ratio": 1.5, "sample_elevation_degrees": rad_to_deg(angle), "vertical_fov_degrees": 1.0, "upper_lower_linear_values": values, "screenshot": path, "scope": "低空云层投影连续性回归，不能代表整个天空的视觉验收"}


static func _material_frames(context: VersionContext) -> void:
	# 新诊断材质需要实际提交到渲染线程，避免把前一材质的缓存帧当作结果。
	for frame: int in 3:
		await context.tree.process_frame
