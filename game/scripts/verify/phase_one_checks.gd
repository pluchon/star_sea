extends SceneTree

# 固定的分步验收场景不修改正常运行的画面参数。
const OUTPUT_DIRECTORY: String = "res://../test-output/p1"

var _scene: Node3D


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var check_name: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--check="):
			check_name = argument.trim_prefix("--check=")
	if check_name == "terrain_stats":
		_check_terrain_statistics()
		return
	if check_name == "geometry":
		var report: Dictionary = TerrainGeometryChecks.run()
		VerificationMetrics.write_json(OUTPUT_DIRECTORY.path_join("geometry_checks.json"), report)
		print(JSON.stringify(report))
		quit(0 if report["passed"] else 1)
		return
	if check_name == "systems" or check_name == "interface" or check_name == "upload_descent":
		var packed: PackedScene = load("res://scenes/main.tscn")
		var scene: Node3D = packed.instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		var report: Dictionary
		if check_name == "systems":
			report = SystemChecks.run(scene)
		else:
			if DisplayServer.get_name() == "headless":
				_fail("交互截图必须使用真实渲染器。")
				return
			if check_name == "interface":
				report = await InteractionChecks.run(scene)
			else:
				report = await UploadDescentCheck.run(scene)
		VerificationMetrics.write_json(OUTPUT_DIRECTORY.path_join(check_name + "_checks.json"), report)
		var summary: Dictionary = report.duplicate()
		summary.erase("upload_frames")
		print(JSON.stringify(summary))
		quit(0 if report["passed"] else 1)
		return
	if check_name != "sky" and check_name != "toon":
		_fail("未知的分步验收项目：" + check_name)
		return
	if DisplayServer.get_name() == "headless":
		_fail("截图必须使用真实渲染器，不能使用无界面模式。")
		return
	var packed_scene: PackedScene = load("res://scripts/verify/fixtures/lighting.tscn")
	_scene = packed_scene.instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var camera: Camera3D = _scene.get_node("Camera") as Camera3D
	var sun_direction: Vector3 = Vector3(0.35, 0.35, -0.87).normalized()
	RenderingServer.global_shader_parameter_set("sun_dir", sun_direction)
	camera.look_at(camera.global_position + Vector3(0.0, 0.1, -1.0), Vector3.UP)
	var ball: MeshInstance3D
	if check_name == "toon":
		var light: DirectionalLight3D = _scene.get_node("Sun") as DirectionalLight3D
		light.global_basis = Basis.looking_at(Vector3(0.8, -0.35, -0.4).normalized(), Vector3.UP)
		ball = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 128
		sphere.rings = 64
		ball.mesh = sphere
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = load("res://scripts/verify/fixtures/toon_ball.gdshader") as Shader
		ball.material_override = material
		_scene.add_child(ball)
		camera.global_position = Vector3(0.0, 0.0, 4.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
	for frame: int in 120:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		_fail("无法创建验收输出目录：" + error_string(directory_error))
		return
	var image: Image = root.get_texture().get_image()
	var filename: String = "toon_ball.png" if check_name == "toon" else "sky.png"
	var save_error: Error = image.save_png(directory.path_join(filename))
	if save_error != OK:
		_fail("无法保存天空截图：" + error_string(save_error))
		return
	if is_instance_valid(ball):
		ball.free()
	quit(0)


func _check_terrain_statistics() -> void:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0)
	var statistics: Dictionary = TerrainStatistics.collect(noise)
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("terrain_stats.json"), FileAccess.WRITE)
	if file == null:
		_fail("无法写入地形统计：" + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(statistics, "\t"))
	file.close()
	print(JSON.stringify(statistics))
	quit(0 if statistics["passed"] else 1)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
