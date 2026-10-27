class_name RenderReviewCapture
extends RefCounted


static func view(context: VersionContext, name: String, direction: String) -> String:
	var modes: Array[Dictionary] = []
	for node: Node in context.scene.find_children("*", "", true, false):
		modes.append({"node": node, "mode": node.process_mode})
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = context.player.camera
	var original: Transform3D = camera.transform
	var up: Vector3 = context.local_position().normalized()
	if direction == "backward":
		camera.global_basis = Basis(up, PI) * camera.global_basis
	else:
		camera.global_position += up * 20
		camera.global_basis = Basis.looking_at(-up, (-context.player.global_basis.z).slide(up).normalized())
	var path: String = await context.capture(name + "-" + direction)
	camera.transform = original
	for state: Dictionary in modes:
		(state["node"] as Node).process_mode = state["mode"]
	return path


static func run(context: VersionContext, name: String) -> Dictionary:
	var finish: RenderFinish = context.scene.get_node("RenderFinish") as RenderFinish
	var modes: Array[Dictionary] = []
	for node: Node in context.scene.find_children("*", "", true, false):
		modes.append({"node": node, "mode": node.process_mode})
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var full: String = await context.capture(name + "-forward")
	finish.visible = false
	var plain: String = await context.capture(name + "-no-outline")
	finish.visible = true
	var saved: Array[Dictionary] = []
	var vegetation_shaders: Dictionary = {}
	var environment: Environment = (context.scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky_background: int = environment.background_mode
	var background: Color = environment.background_color
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	# 分类图只改变本次验证实例的材质，暂停业务处理以免覆盖临时材质。
	for node: Node in context.scene.find_children("*", "", true, false):
		var state: Dictionary = {"node": node}
		if node is GeometryInstance3D:
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			state["material"] = geometry.material_override
			state["visible"] = geometry.visible
			var mesh: Mesh = null
			if node is MeshInstance3D:
				mesh = (node as MeshInstance3D).mesh
			elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
				mesh = (node as MultiMeshInstance3D).multimesh.mesh
			if mesh != null:
				var path: String = str(node.get_path())
				var shader_path: String = ""
				if geometry.material_override is ShaderMaterial:
					shader_path = (geometry.material_override as ShaderMaterial).shader.resource_path
				# 草叶虽低于 0.6 米，仍是立起的物体，不能混入地面描边分母。
				var vegetation: bool = path.contains("/SurfaceDetails/") or shader_path.contains("surface_detail") or shader_path.contains("surface_solid") or shader_path.contains("field_stalks")
				var ground: bool = path.contains("/Terrain/") or shader_path.contains("road") or (mesh.get_aabb().size.y < 0.6 and not vegetation)
				if shader_path.get_file() in ["water.gdshader", "inland_water.gdshader", "cave_water.gdshader"]:
					geometry.material_override = _water_mask(geometry.material_override as ShaderMaterial, vegetation_shaders)
				elif vegetation and geometry.material_override is ShaderMaterial:
					geometry.material_override = _vegetation_mask(geometry.material_override as ShaderMaterial, vegetation_shaders)
				else:
					var material: StandardMaterial3D = StandardMaterial3D.new()
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					material.disable_fog = true
					material.albedo_color = Color.GREEN if ground else Color.RED
					geometry.material_override = material
				for excluded: String in ["outline", "contact", "grade", "atmosphere", "sky.gdshader", "light_shaft", "dust"]:
					if shader_path.contains(excluded):
						geometry.visible = false
			else:
				geometry.visible = false
		saved.append(state)
	for frame: int in 3:
		await context.tree.process_frame
	var mask: String = await context.capture(name + "-ground-mask")
	for state: Dictionary in saved:
		var node: Node = state["node"]
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).material_override = state["material"]
			(node as GeometryInstance3D).visible = state["visible"]
	for state: Dictionary in modes:
		(state["node"] as Node).process_mode = state["mode"]
	environment.background_mode = sky_background as Environment.BGMode
	environment.background_color = background
	return {"screenshot": full, "no_outline": plain, "ground_mask": mask, "paired_scene_frozen": true}


static func _vegetation_mask(original: ShaderMaterial, shaders: Dictionary) -> ShaderMaterial:
	var path: String = original.shader.resource_path
	if not shaders.has(path):
		var code: String = original.shader.code
		var include_path: String = "res://shaders/surface_detail.gdshaderinc"
		code = code.replace("#include \"" + include_path + "\"", FileAccess.get_file_as_string(include_path))
		code = code.get_slice("void fragment()", 0)
		code = code.replace("render_mode ", "render_mode unshaded, fog_disabled, shadows_disabled, ")
		code += "\nvoid fragment() { toon_distance = length(VERTEX); ALBEDO = vec3(1.0, 0.0, 0.0); }\n"
		var shader: Shader = Shader.new()
		shader.code = code
		shaders[path] = shader
	# 保留生产顶点位移和风参数，只替换片元颜色，避免草叶掩码与实际轮廓错位。
	var material: ShaderMaterial = original.duplicate() as ShaderMaterial
	material.shader = shaders[path]
	return material


static func _water_mask(original: ShaderMaterial, shaders: Dictionary) -> ShaderMaterial:
	var path: String = original.shader.resource_path
	if not shaders.has(path):
		var code: String = original.shader.code.get_slice("ALBEDO =", 0)
		if not code.contains("unshaded"):
			code = code.replace("render_mode ", "render_mode unshaded, ")
		if not code.contains("fog_disabled"):
			code = code.replace("render_mode ", "render_mode fog_disabled, ")
		# 保留生产水面射线求交和 discard，只把可见水域涂成蓝色并遮住水底。
		code += "ALBEDO = vec3(0.0, 0.0, 1.0); ALPHA = 1.0; }\n"
		var shader: Shader = Shader.new()
		shader.code = code
		shaders[path] = shader
	var material: ShaderMaterial = original.duplicate() as ShaderMaterial
	material.shader = shaders[path]
	return material
