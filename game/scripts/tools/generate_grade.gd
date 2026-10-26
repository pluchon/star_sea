extends SceneTree

const SIZE: int = 32 # 每个颜色轴的采样数。


func _initialize() -> void:
	var palette: RenderPalette = load("res://data/palette.tres") as RenderPalette
	DirAccess.make_dir_recursive_absolute("res://textures/grade")
	for period: int in palette.periods.size():
		var slices: Array[Image] = []
		for blue: int in SIZE:
			var slice: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
			for green: int in SIZE:
				for red: int in SIZE:
					var color: Color = Color(float(red) / (SIZE - 1), float(green) / (SIZE - 1), float(blue) / (SIZE - 1))
					slice.set_pixel(red, green, palette.grade(color, period))
			slices.append(slice)
		var table: GradeLut = GradeLut.new()
		table.slices = slices
		var error: Error = ResourceSaver.save(table, "res://textures/grade/%s.res" % palette.periods[period]["name"], ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("三维调色表生成失败：%s" % error_string(error))
			quit(1)
			return
	quit()
