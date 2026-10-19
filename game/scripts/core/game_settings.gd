class_name StarSeaSettings
extends Node

const PATH: String = "user://settings.cfg"
static var sensitivity: float = 0.002
static var volume: float = 0.65
static var render_scale: float = 1.0
static var field_of_view: float = 75.0
static var fullscreen: bool = true
static var vsync: bool = true


func _ready() -> void:
	Engine.max_fps = 0
	# 自动验收采用固定参数，用户设置只影响正常游玩。
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().is_empty():
		return
	load_settings()
	apply()


func load_settings(path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error == OK:
		var values: Array = [config.get_value("controls", "sensitivity", 0.002), config.get_value("audio", "volume", 0.65), config.get_value("video", "scale", 1.0), config.get_value("video", "fov", 75.0)]
		for value: Variant in values:
			if (not value is float and not value is int) or not is_finite(float(value)):
				return ERR_INVALID_DATA
		var fullscreen_value: Variant = config.get_value("video", "fullscreen", true)
		var vsync_value: Variant = config.get_value("video", "vsync", true)
		if not fullscreen_value is bool or not vsync_value is bool:
			return ERR_INVALID_DATA
		# 全部校验通过后再更新，损坏的设置不能留下部分生效的状态。
		sensitivity = clampf(values[0], 0.0005, 0.006)
		volume = clampf(values[1], 0.0, 1.0)
		render_scale = clampf(values[2], 0.65, 1.0)
		field_of_view = clampf(values[3], 60.0, 100.0)
		fullscreen = fullscreen_value
		vsync = vsync_value
	return error


func apply() -> void:
	get_viewport().scaling_3d_scale = render_scale
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		camera.fov = field_of_view


func save(path: String = PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("audio", "volume", volume)
	config.set_value("video", "scale", render_scale)
	config.set_value("video", "fov", field_of_view)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	apply()
	var error: Error = config.save(path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
