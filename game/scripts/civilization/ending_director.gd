class_name EndingDirector
extends Node

const FLIGHT_SECONDS: float = 60.0
const PATH_COUNT: int = 40
var awakened: bool = false
var ending_seen: bool = false
var light_path: Vector3 = Vector3.ZERO
var flight_seconds: float = 0.0
var busy: bool = false
var points: PackedVector3Array = []
var _planet: Planet
var _player: StarSeaPlayer
var _echoes: EchoSystem
var _wait: float = 0.0
var _phase: float = 0.0
var _path_root: Node3D
var _flares: Array[MeshInstance3D] = []
var _lamp: Node3D
var _overlay: CanvasLayer
var _stars: ColorRect
var _black: ColorRect
var _caption: Label
var _saved_controls: bool = true
var _returned: bool = false
var _hud_visible: bool = true
var _path_overlay: PathOverlay

class PathOverlay extends Control:
	var director: EndingDirector
	func _draw() -> void:
		if director == null or not director.busy:
			return
		var camera: Camera3D = director._player.camera
		for point: Vector3 in director.points:
			var global_point: Vector3 = director._planet.to_global(point)
			if camera.is_position_behind(global_point):
				continue
			var at: Vector2 = camera.unproject_position(global_point)
			for i: int in range(8, 0, -1):
				draw_circle(at, i, Color(1, 0.91, 0.7, 0.012 * (9 - i)))


func _ready() -> void:
	_planet = get_parent() as Planet
	_player = _planet.get_parent().get_parent().get_node("Player") as StarSeaPlayer
	_echoes = _planet.get_node("EchoSystem") as EchoSystem
	_path_root = Node3D.new()
	_path_root.name = "LightPath"
	_planet.add_child(_path_root)
	_overlay = CanvasLayer.new()
	_overlay.layer = 8
	add_child(_overlay)
	_stars = ColorRect.new()
	_stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_material: ShaderMaterial = ShaderMaterial.new()
	star_material.shader = load("res://shaders/ending_stars.gdshader") as Shader
	_stars.material = star_material
	_stars.visible = false
	_overlay.add_child(_stars)
	_path_overlay = PathOverlay.new()
	_path_overlay.director = self
	_path_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_path_overlay)
	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color.BLACK
	_black.visible = false
	_overlay.add_child(_black)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 28)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI"])
	_caption.add_theme_font_override("font", font)
	_black.add_child(_caption)


func all_seen() -> bool:
	for id: String in EchoScripts.IDS:
		if not _echoes.seen.has(id):
			return false
	return true


func _process(delta: float) -> void:
	var sky: SkyDirector = _planet.get_parent().get_parent().get_node("SkyDirector") as SkyDirector
	if not sky.time_paused and not busy:
		if all_seen() and _echoes.active.is_empty():
			_wait += delta
			if _wait >= 5:
				awakened = true
		else:
			_wait = 0
	var ladder: SkyLadder = _planet.get_node("SkyLadder") as SkyLadder
	ladder.ending_awake = awakened
	if not light_path.is_zero_approx() and points.is_empty():
		illuminate(1)
	var camera: Camera3D = _player.camera
	for i: int in _flares.size():
		var flare: MeshInstance3D = _flares[i]
		flare.global_basis = camera.global_basis
		flare.scale = Vector3.ONE * BeaconTowers.flare_size(flare.global_position.distance_to(camera.global_position), camera.fov, get_viewport().get_visible_rect().size.y) * 0.7
	if busy:
		_phase += delta
		_path_overlay.queue_redraw()
		var material: ShaderMaterial = _stars.material as ShaderMaterial
		material.set_shader_parameter("fade", smoothstep(0, 8, _phase) if _phase < 20 else 1 - smoothstep(20, 23, _phase))
		material.set_shader_parameter("view_rotation", camera.global_basis)
		var half_y: float = tan(deg_to_rad(camera.fov) * 0.5)
		material.set_shader_parameter("view_half", Vector2(half_y * get_viewport().get_visible_rect().size.aspect(), half_y))
		_black.visible = _phase >= 8 and _phase < 20
		if _black.visible:
			var at: float = fposmod(_phase - 8, 6)
			_caption.text = "星海尽头" if _phase < 14 else "制作 · pluchon"
			_caption.modulate.a = minf(smoothstep(0, 1.5, at), 1 - smoothstep(4.5, 6, at))
		if _phase >= 20 and not _returned:
			_returned = true
			return_position()
		if _phase >= 23:
			finish_credits()
	elif not sky.time_paused and not ending_seen and not points.is_empty() and _player.mode == StarSeaPlayer.Mode.FLY:
		advance_flight(delta)


func illuminate(amount: float) -> void:
	var frame: Transform3D = _echoes.anchors["dawn_ending"]
	if light_path.is_zero_approx():
		var giant: Node3D = _planet.get_parent().get_node("GasGiant") as Node3D
		var toward: Vector3 = (_planet.to_local(giant.global_position) - frame.origin).normalized()
		var up: Vector3 = frame.origin.normalized()
		# 渊在本站的地平线下；保留它的方位并抬高仰角，避免光之路穿入晨。
		light_path = toward.slide(up).normalized() * sqrt(1 - 0.65 * 0.65) + up * 0.65
	if points.is_empty():
		var distance: float = 0
		for i: int in PATH_COUNT:
			distance += lerpf(100, 2000, float(i) / (PATH_COUNT - 1))
			points.append(frame.origin + light_path * distance)
			var flare: MeshInstance3D = MeshInstance3D.new()
			var mesh: QuadMesh = QuadMesh.new()
			mesh.size = Vector2.ONE
			flare.mesh = mesh
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = load("res://shaders/light_path.gdshader") as Shader
			flare.material_override = material
			flare.position = points[-1]
			flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_path_root.add_child(flare)
			_flares.append(flare)
	for i: int in _flares.size():
		(_flares[i].material_override as ShaderMaterial).set_shader_parameter("strength", smoothstep(float(i) / PATH_COUNT, float(i + 1) / PATH_COUNT, amount) * 0.6)
	if _lamp == null:
		var ladder: SkyLadder = _planet.get_node("SkyLadder") as SkyLadder
		_lamp = ladder.model("watcher_lamp", _path_root, frame.origin + frame.basis.z * -2, false)
		_lamp.basis = frame.basis
		var light: OmniLight3D = OmniLight3D.new()
		light.omni_range = 4
		light.light_color = Color("f2b45a")
		light.light_energy = 1
		light.position.y = 0.7
		_lamp.add_child(light)


func advance_flight(delta: float) -> void:
	if busy or ending_seen or light_path.is_zero_approx():
		return
	var origin: Vector3 = Transform3D(_echoes.anchors["dawn_ending"]).origin
	var at: Vector3 = _player.global_position - _planet.global_position
	var along: float = (at - origin).dot(light_path)
	var gap: float = (at - origin - light_path * maxf(along, 0)).length()
	if along >= 0 and gap <= 3000 and _player.velocity.length() > 0.5 and _player.velocity.normalized().dot(light_path) > cos(PI / 4):
		flight_seconds += delta
		if flight_seconds >= FLIGHT_SECONDS:
			begin_credits()


func begin_credits() -> void:
	if busy or ending_seen:
		return
	busy = true
	_phase = 0
	_returned = false
	_saved_controls = _player.controls_enabled
	_player.controls_enabled = false
	_player.velocity = Vector3.ZERO
	_stars.visible = true
	var hud: CanvasLayer = _planet.get_parent().get_parent().get_node("HUD") as CanvasLayer
	_hud_visible = hud.visible
	hud.visible = false


func finish_credits() -> void:
	if points.is_empty():
		return
	busy = false
	ending_seen = true
	_stars.visible = false
	_black.visible = false
	_path_overlay.queue_redraw()
	return_position()
	_player.mode = StarSeaPlayer.Mode.FLY
	_player.velocity = Vector3.ZERO
	_player.controls_enabled = _saved_controls
	(_planet.get_parent().get_parent().get_node("HUD") as CanvasLayer).visible = _hud_visible
	var towers: BeaconTowers = _planet.get_node("BeaconTowers") as BeaconTowers
	var ids: Array[int] = []
	for i: int in towers.towers.size():
		ids.append(i)
	towers.set_lit(ids)
	JourneyStore.autosave(_planet.get_parent().get_parent())


func return_position() -> void:
	var at: Vector3 = points[-1] - light_path * 80
	_player.place_at(_planet.to_global(at), light_path, at.normalized())


func restore_state(seen: bool, direction: Vector3) -> void:
	ending_seen = seen
	light_path = direction
	flight_seconds = 0
	awakened = false
	_wait = 0
	for child: Node in _path_root.get_children():
		_path_root.remove_child(child)
		child.queue_free()
	_flares.clear()
	points.clear()
	_lamp = null
	if not direction.is_zero_approx():
		illuminate(1)
