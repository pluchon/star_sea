class_name JournalPage
extends PanelContainer

signal closed
var journal: TravelJournal
var scene: Node
var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 120
	offset_right = -120
	offset_top = 50
	offset_bottom = -50
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.055, 0.075, 0.98)
	background.set_content_margin_all(24)
	add_theme_stylebox_override("panel", background)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 18)
	add_child(_column)
	show_cards()


func clear() -> void:
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()


func button(title: String, action: Callable, parent: Node) -> Button:
	var value: Button = Button.new()
	value.text = title
	value.pressed.connect(action)
	parent.add_child(value)
	return value


func image_for(id: String) -> Texture2D:
	var path: String = "user://journal/" + id + ".png"
	if FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image != null:
			return ImageTexture.create_from_image(image)
	var plain: GradientTexture2D = GradientTexture2D.new()
	plain.gradient = Gradient.new()
	plain.gradient.set_color(0, Color(0.07, 0.15, 0.18))
	plain.gradient.set_color(1, Color(0.12, 0.22, 0.24))
	return plain


func show_cards() -> void:
	clear()
	var header: HBoxContainer = HBoxContainer.new()
	_column.add_child(header)
	var title: Label = Label.new()
	title.text = "旅行手记"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	button("返回", func() -> void: closed.emit(), header)
	var echoes: EchoSystem = journal.get_parent().get_node("EchoSystem") as EchoSystem
	var rings: Label = Label.new()
	var text: String = ""
	for id: String in EchoScripts.IDS + ["dawn_ending"]:
		if id == "dawn_ending" and not echoes.seen.has(id):
			continue
		text += "●　" if echoes.seen.has(id) else "○　"
	rings.text = text
	rings.add_theme_color_override("font_color", Color("f2b45a"))
	rings.add_theme_font_size_override("font_size", 30)
	_column.add_child(rings)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.name = "Cards"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	for id: String in journal.discovered:
		var card: VBoxContainer = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var image: TextureRect = TextureRect.new()
		image.texture = image_for(id)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.custom_minimum_size = Vector2(260, 146)
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(image)
		button(journal.sites[id]["name"], func() -> void: show_detail(id), card)


func show_detail(id: String) -> void:
	clear()
	var title: Label = Label.new()
	title.text = journal.sites[id]["name"]
	title.add_theme_font_size_override("font_size", 30)
	_column.add_child(title)
	var image: TextureRect = TextureRect.new()
	image.texture = image_for(id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(image)
	button("在地图上查看", func() -> void:
		var direction: Vector3 = Transform3D(journal.sites[id]["frame"]).origin.normalized()
		closed.emit()
		(scene.get_node("VoyageMenu") as VoyageMenu).resume()
		var atlas: TerrainAtlas = scene.get_node("HUD/Layout/TerrainAtlas") as TerrainAtlas
		atlas.set_open(true)
		atlas.global_view.center_uv = TerrainMapData.coordinates(direction)
		atlas.global_view._sync_view()
		atlas.globe_view.face(direction), _column)
	button("返回手记", show_cards, _column)
