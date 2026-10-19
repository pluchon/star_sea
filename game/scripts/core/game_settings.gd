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
		sensitivity = clampf(float(config.get_value("controls", "sensitivity", 0.002)), 0.0005, 0.006)
		volume = clampf(float(config.get_value("audio", "volume", 0.65)), 0.0, 1.0)
		render_scale = clampf(float(config.get_value("video", "scale", 1.0)), 0.65, 1.0)
		field_of_view = clampf(float(config.get_value("video", "fov", 75.0)), 60.0, 100.0)
		fullscreen = bool(config.get_value("video", "fullscreen", true))
		vsync = bool(config.get_value("video", "vsync", true))
	return error


func apply() -> void:
	get_viewport().scaling_3d_scale = render_scale
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
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
	return config.save(path)
