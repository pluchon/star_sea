extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	if DisplayServer.get_name() != "headless":
		# 真实渲染器会在加载时编译依赖，脚本入口的日志检查负责识别着色器错误。
		for path: String in DirAccess.get_files_at("res://shaders"):
			if path.ends_with(".gdshader"):
				var shader: Shader = load("res://shaders/" + path) as Shader
				shader.get_shader_uniform_list()
	var palette: RenderPalette = load("res://data/palette.tres") as RenderPalette
	var maximum_error: float = 0.0
	for period: int in palette.periods.size():
		var table: GradeLut = load("res://textures/grade/%s.res" % palette.periods[period]["name"]) as GradeLut
		if table.slices.size() != 32 or table.slices[0].get_width() != 32 or table.slices[0].get_height() != 32:
			_failures.append("调色表尺寸不符合 32³。")
		var slices: Array[Image] = table.slices
		var previous: float = -1
		for level: int in 32:
			var gray: Color = slices[level].get_pixel(level, level)
			if gray.get_luminance() < previous:
				_failures.append("灰阶调色发生明度反转。")
			previous = gray.get_luminance()
			for sample: Vector2i in [Vector2i(0, 0), Vector2i(31, 31), Vector2i(3, 21), Vector2i(28, 8)]:
				var input: Color = Color(float(sample.x) / 31, float(sample.y) / 31, float(level) / 31)
				var expected: Color = palette.grade(input, period)
				var actual: Color = slices[level].get_pixelv(sample)
				for channel: int in 3:
					maximum_error = maxf(maximum_error, absf(actual[channel] - expected[channel]))
	if maximum_error > 1.0 / 255:
		_failures.append("调色表与色板不同步，需要重新生成。")
	var grade: ColorGrade = ColorGrade.new(palette)
	grade.update(Vector3(1, 1, 0), 0, 1)
	grade.finish()
	# 不同太阳高度和进洞混合必须能完成，后台任务不能影响退出。
	for height: float in [-0.2, -0.12, 0.0, 0.04, 0.38, 0.8]:
		for rising: bool in [true, false]:
			grade.update(palette.daylight(height, rising), 0.5, 0.2)
			grade.finish()
	var report: Dictionary = {"passed": _failures.is_empty(), "failures": _failures, "lut_count": palette.periods.size(), "lut_size": 32, "maximum_quantization_error": maximum_error}
	VerificationMetrics.write_json("res://../test-output/render/render_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)
