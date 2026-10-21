extends Control
# 载入画面：章节下载与场景准备、联机入场、章节之间等待下载共用。
# 背景是该章节的封面（真实游戏画面渲染），缓慢推近；左下为章节名与区域，
# 底部是能量连线进度条和轮换的章节提示。联机时额外显示步骤清单和双方状态。
signal retry_pressed
signal cancel_pressed

const Catalog = preload("res://scripts/chapter_catalog.gd")
const EnergyProgress = preload("res://scripts/energy_progress.gd")
const Shade = preload("res://scripts/menu_shade.gdshader")
const TIP_SECONDS := 6.0

var chapter := 0
var cover: TextureRect
var shade: ColorRect
var kicker: Label
var heading: Label
var route: Label
var stage: Label
var detail: Label
var percent: Label
var bar
var tip: Label
var tip_badge: Label
var steps_box: VBoxContainer
var players_box: HBoxContainer
var error_row: HBoxContainer
var error_label: Label
var cancel_button: Button
var clock := 0.0
var tip_index := 0
var tip_clock := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b1117")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	cover = TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = Shade
	shade.material = material
	add_child(shade)
	kicker = text_label(18, Color("e8bd7d"))
	heading = text_label(52, Color("f7f2e6"))
	heading.add_theme_constant_override("outline_size", 6)
	heading.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	route = text_label(16, Color("cfd6cc"))
	stage = text_label(18, Color("f2ede0"))
	detail = text_label(15, Color("b9c3bb"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent = text_label(30, Color("f7f2e6"))
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar = EnergyProgress.new()
	add_child(bar)
	tip_badge = text_label(13, Color("211d16"))
	tip_badge.text = "提示"
	tip_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color("e8bd7d")
	badge.set_corner_radius_all(6)
	badge.content_margin_left = 8
	badge.content_margin_right = 8
	badge.content_margin_top = 2
	badge.content_margin_bottom = 2
	tip_badge.add_theme_stylebox_override("normal", badge)
	tip = text_label(15, Color("dfe5dc"))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps_box = VBoxContainer.new()
	steps_box.add_theme_constant_override("separation", 6)
	steps_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(steps_box)
	players_box = HBoxContainer.new()
	players_box.add_theme_constant_override("separation", 10)
	players_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(players_box)
	error_row = HBoxContainer.new()
	error_row.add_theme_constant_override("separation", 10)
	error_row.visible = false
	add_child(error_row)
	error_label = text_label(16, Color("ffb4a2"), error_row)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var retry := make_button("重试", true)
	retry.pressed.connect(func(): retry_pressed.emit())
	error_row.add_child(retry)
	cancel_button = make_button("返回", false)
	cancel_button.pressed.connect(func(): cancel_pressed.emit())
	add_child(cancel_button)
	cancel_button.visible = false
	get_viewport().size_changed.connect(layout)
	setup(chapter)

func text_label(font_size: int, color: Color, parent: Node = self) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func make_button(text: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 42)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("e8bd7d") if accent else Color(0.06, 0.08, 0.09, 0.82)
	normal.border_color = Color("f4d9a6") if accent else Color(0.80, 0.68, 0.48, 0.38)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("f2cd90") if accent else Color(0.10, 0.13, 0.14, 0.92)
	hover.border_color = Color("fff0cd") if accent else Color(0.95, 0.82, 0.60, 0.6)
	for state in ["normal", "focus"]: button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("211d16") if accent else Color("f2ede0"))
	button.add_theme_color_override("font_hover_color", Color("211d16") if accent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("211d16") if accent else Color.WHITE)
	button.add_theme_font_size_override("font_size", 16)
	return button

# kind：chapter（选章后进入）、online（联机入场）、between（章节之间等待下载）。
func setup(value: int, kind: String = "chapter") -> void:
	chapter = value
	if not is_node_ready(): return
	var data := Catalog.entry(chapter)
	cover.texture = Catalog.cover(chapter)
	kicker.text = ("远程双人 · " if kind == "online" else "") + str(data.number)
	heading.text = str(data.name)
	route.text = "  ›  ".join(data.zones)
	tip_index = randi() % data.tips.size()
	tip.text = data.tips[tip_index]
	tip_clock = 0.0
	set_steps([])
	set_players([])
	show_error("")
	cancel_button.visible = kind == "online"
	set_stage("正在准备…", 0.0)
	layout()

func set_stage(text: String, fraction: float, info: String = "", unknown: bool = false) -> void:
	stage.text = text
	detail.text = info
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.indeterminate = unknown
	percent.text = "" if unknown else "%d%%" % int(round(bar.value * 100.0))

# steps：[[文字, "done"/"active"/"pending"/"error"], ...]，联机入场时显示。
func set_steps(steps: Array) -> void:
	var key := str(steps)
	if steps_box.get_meta("key", "") == key: return
	steps_box.set_meta("key", key)
	for child in steps_box.get_children(): child.queue_free()
	for step in steps:
		var row := text_label(16, Color("f2ede0"), steps_box)
		var marks := {"done": "✓", "active": "›", "pending": "·", "error": "×"}
		var colors := {"done": Color("8fd18a"), "active": Color("f2cd90"), "pending": Color(1, 1, 1, 0.45), "error": Color("ff8f7a")}
		row.text = "%s  %s" % [marks.get(step[1], "·"), step[0]]
		row.add_theme_color_override("font_color", colors.get(step[1], Color.WHITE))
	layout()

# players：[{"role":0,"name":"你","status":"已就绪","ready":true}, ...]
func set_players(players: Array) -> void:
	var key := str(players)
	if players_box.get_meta("key", "") == key: return
	players_box.set_meta("key", key)
	for child in players_box.get_children(): child.queue_free()
	for player in players:
		var chip := PanelContainer.new()
		var color := EnergyProgress.CYAN if int(player.role) == 0 else EnergyProgress.ORANGE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.06, 0.07, 0.78)
		style.border_color = Color(color, 0.85 if player.get("ready", false) else 0.35)
		style.set_border_width_all(2 if player.get("ready", false) else 1)
		style.set_corner_radius_all(10)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		chip.add_theme_stylebox_override("panel", style)
		players_box.add_child(chip)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		chip.add_child(column)
		var name_label := text_label(16, color, column)
		name_label.text = "%02d  %s" % [int(player.role) + 1, player.name]
		var state_label := text_label(13, Color("dfe5dc"), column)
		state_label.text = str(player.status)
	layout()

func show_error(text: String) -> void:
	error_row.visible = not text.is_empty()
	error_label.text = text
	layout()

func _process(delta: float) -> void:
	if not visible: return
	clock += delta
	# 封面缓慢推近，提示每 6 秒轮换一次。
	var zoom := 1.04 + 0.03 * sin(clock * 0.08)
	cover.scale = Vector2(zoom, zoom)
	tip_clock += delta
	if tip_clock >= TIP_SECONDS:
		tip_clock = 0.0
		var tips: Array = Catalog.entry(chapter).tips
		tip_index = (tip_index + 1) % tips.size()
		tip.text = tips[tip_index]

func layout() -> void:
	if not is_node_ready(): return
	var view := get_viewport().get_visible_rect().size
	size = view
	cover.size = view
	cover.pivot_offset = view * 0.5
	var narrow := view.x < 760.0
	var margin := 24.0 if narrow else 64.0
	var width := view.x - margin * 2.0
	var bottom := view.y - (28.0 if narrow else 44.0)
	tip_badge.position = Vector2(margin, bottom - 24)
	tip.position = Vector2(margin + 54, bottom - 26)
	tip.size = Vector2(width - 54, 0)
	bar.position = Vector2(margin - 22, bottom - 92)
	bar.size = Vector2(width + 44, 44)
	stage.position = Vector2(margin, bottom - 124)
	stage.size = Vector2(width * 0.6, 0)
	detail.position = Vector2(margin + width * 0.35, bottom - 122)
	detail.size = Vector2(width * 0.65 - 70, 0)
	percent.position = Vector2(margin + width - 70, bottom - 132)
	percent.size = Vector2(70, 0)
	var top := bottom - 150.0
	error_row.position = Vector2(margin, top - 54)
	error_row.size = Vector2(width, 44)
	if error_row.visible: top -= 60
	players_box.position = Vector2(margin, top - 64)
	if players_box.get_child_count() > 0: top -= 76
	var steps_height := steps_box.get_combined_minimum_size().y
	steps_box.position = Vector2(margin, top - steps_height - 8)
	if steps_box.get_child_count() > 0: top -= steps_height + 18
	heading.add_theme_font_size_override("font_size", 38 if narrow else 52)
	route.position = Vector2(margin, top - 28)
	route.size = Vector2(width, 0)
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if narrow else TextServer.AUTOWRAP_OFF
	heading.position = Vector2(margin, top - (90 if narrow else 104))
	kicker.position = Vector2(margin, top - (118 if narrow else 134))
	cancel_button.position = Vector2(view.x - margin - 110, margin * 0.6)
