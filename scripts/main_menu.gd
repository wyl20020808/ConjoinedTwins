extends Control
# 主界面：选择章节。网页版此时只下载了主包（脚本、界面与封面），
# 章节资源在点“进入章节”后才下载；已下载过的章节由浏览器缓存直接读取。
signal chapter_chosen(chapter: int)

const Catalog = preload("res://scripts/chapter_catalog.gd")
const Shade = preload("res://scripts/menu_shade.gdshader")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const GOLD := Color("e8bd7d")

var selected := 0
var covers: Array[TextureRect] = []
var cover_front := 0
var shade: ColorRect
var logo: Label
var logo_sub: Label
var kicker: Label
var heading: Label
var route: Label
var summary: Label
var facts: Label
var status_chip: Label
var enter_button: Button
var footer: Label
var notice: Label
var reload_button: Button
var cards: Array = []
var clock := 0.0

class ChapterCard extends Control:
	signal picked(index: int)
	var index := 0
	var texture: Texture2D
	var number := ""
	var title := ""
	var status := ""
	var accent := Color.WHITE
	var selected := false
	var hovered := false
	var lift := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hovered = true)
		mouse_exited.connect(func(): hovered = false)

	func _gui_input(event: InputEvent) -> void:
		var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if tap or (event is InputEventScreenTouch and event.pressed):
			picked.emit(index)
			accept_event()

	func _process(delta: float) -> void:
		var target := 1.0 if selected else (0.5 if hovered else 0.0)
		lift = lerpf(lift, target, minf(1.0, delta * 10.0))
		queue_redraw()

	func _draw() -> void:
		var image_height := size.x * 9.0 / 16.0
		var offset := Vector2(0, -6.0 * lift)
		var frame := Rect2(offset, Vector2(size.x, image_height))
		# 选中卡片的金色外发光。
		if lift > 0.01:
			for r in [10.0, 6.0, 3.0]:
				draw_rect(frame.grow(r), Color(accent, 0.05 * lift * (11.0 - r) / 3.0), false, 2.0)
		if texture != null:
			var tex_size := texture.get_size()
			var scale := maxf(frame.size.x / tex_size.x, frame.size.y / tex_size.y)
			var region_size := frame.size / scale
			draw_texture_rect_region(texture, frame, Rect2((tex_size - region_size) * 0.5, region_size), Color(1, 1, 1, 0.72 + 0.28 * lift))
		# 底部渐暗，叠放章节编号。
		for i in range(12):
			var t := float(i) / 12.0
			draw_rect(Rect2(frame.position + Vector2(0, frame.size.y * (0.55 + t * 0.45)), Vector2(frame.size.x, frame.size.y * 0.45 / 12.0 + 1)), Color(0.02, 0.03, 0.04, t * 0.75))
		var font := get_theme_default_font()
		draw_string(font, frame.position + Vector2(12, frame.size.y - 12), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(accent, 0.95))
		draw_rect(frame, Color(accent, 0.25 + 0.75 * lift) if lift > 0.01 else Color(1, 1, 1, 0.14), false, 2.0 if selected else 1.0)
		var text_y := frame.end.y + 24.0
		draw_string(font, Vector2(2, text_y), title, HORIZONTAL_ALIGNMENT_LEFT, size.x, 18, Color("f7f2e6"))
		draw_string(font, Vector2(2, text_y + 20.0), status, HORIZONTAL_ALIGNMENT_LEFT, size.x, 13, Color(0.82, 0.86, 0.8, 0.8))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b1117")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	for n in range(2):
		var cover := TextureRect.new()
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cover)
		covers.append(cover)
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = Shade
	shade.material = material
	add_child(shade)
	logo = label(40, Color("f7f2e6"))
	logo.text = "共生连线"
	logo.add_theme_constant_override("outline_size", 5)
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	logo_sub = label(15, Color("cfd6cc"))
	logo_sub.text = "双人能量连线 · 合作闯关"
	kicker = label(18, GOLD)
	heading = label(56, Color("f7f2e6"))
	heading.add_theme_constant_override("outline_size", 6)
	heading.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	route = label(15, Color("cfd6cc"))
	summary = label(17, Color("e6e9e0"))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts = label(14, Color(0.8, 0.85, 0.8, 0.85))
	status_chip = label(14, Color("f2ede0"))
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(0.05, 0.07, 0.08, 0.72)
	chip.border_color = Color(GOLD, 0.45)
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(12)
	chip.content_margin_left = 12
	chip.content_margin_right = 12
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	status_chip.add_theme_stylebox_override("normal", chip)
	enter_button = LoadingScreen.make_button("进入章节", true)
	enter_button.custom_minimum_size = Vector2(220, 54)
	enter_button.add_theme_font_size_override("font_size", 20)
	enter_button.pressed.connect(func(): choose(selected))
	add_child(enter_button)
	notice = label(15, Color("ffd9a8"))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reload_button = LoadingScreen.make_button("刷新页面", false)
	reload_button.pressed.connect(func(): if OS.has_feature("web"): JavaScriptBridge.eval("location.reload()", true))
	add_child(reload_button)
	footer = label(13, Color(0.8, 0.84, 0.8, 0.6))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for chapter in range(Catalog.ENTRIES.size()):
		var card := ChapterCard.new()
		var data := Catalog.entry(chapter)
		card.index = chapter
		card.texture = Catalog.cover(chapter)
		card.number = data.number
		card.title = data.name
		card.accent = data.accent
		card.picked.connect(func(index):
			if index == selected: choose(index)
			else: select(index))
		add_child(card)
		cards.append(card)
	ChapterPacks.changed.connect(refresh)
	get_viewport().size_changed.connect(layout)
	select(selected, true)
	enter_button.grab_focus.call_deferred()

func label(font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	result.add_theme_constant_override("shadow_offset_y", 2)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func select(chapter: int, instant: bool = false) -> void:
	var changed := chapter != selected or instant
	selected = clampi(chapter, 0, Catalog.ENTRIES.size() - 1)
	if changed:
		# 两张封面交叉淡入，切换章节时背景不闪黑。
		cover_front = 1 - cover_front
		covers[cover_front].texture = Catalog.cover(selected)
		covers[cover_front].modulate.a = 1.0 if instant else 0.0
		move_child(covers[cover_front], 2)
	var data := Catalog.entry(selected)
	kicker.text = data.number
	heading.text = data.name
	route.text = "  ›  ".join(data.zones)
	summary.text = data.summary
	facts.text = data.length + ("　·　进入后可选单人＋搭档或远程双人" if selected != Catalog.TRAINING else "　·　单人持枪练习")
	for card in cards: card.selected = card.index == selected
	refresh()

func status_text(chapter: int) -> String:
	match ChapterPacks.manifest_state:
		"none": return "已就绪"
		"loading", "idle": return "正在检查章节数据…"
		"stale": return "游戏已更新，请刷新页面"
		"error": return "章节清单读取失败"
	if ChapterPacks.downloading(chapter): return "下载中 %d%%" % int(ChapterPacks.progress(chapter) * 100.0)
	if ChapterPacks.is_ready(chapter): return "已载入 · 立即进入"
	var bytes := ChapterPacks.bytes_missing(chapter)
	if bytes == 0: return "已缓存 · 秒开"
	return "需下载 " + ChapterPacks.megabytes(bytes)

func refresh() -> void:
	for card in cards: card.status = status_text(card.index)
	status_chip.text = status_text(selected)
	var blocked: bool = ChapterPacks.manifest_state in ["stale", "error"]
	notice.text = ChapterPacks.failure if blocked else ""
	reload_button.visible = blocked and OS.has_feature("web")
	enter_button.disabled = blocked or ChapterPacks.manifest_state == "loading"
	footer.text = "章节数据按需下载，下载过的章节会缓存在本机，刷新页面无需重新下载" if ChapterPacks.enabled else ""
	layout()

func choose(chapter: int) -> void:
	if enter_button.disabled: return
	select(chapter)
	chapter_chosen.emit(chapter)

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_left"): select(posmod(selected - 1, cards.size()))
	elif event.is_action_pressed("ui_right"): select(posmod(selected + 1, cards.size()))
	else: return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible: return
	clock += delta
	var front: TextureRect = covers[cover_front]
	front.modulate.a = minf(1.0, front.modulate.a + delta * 2.5)
	# 背景封面缓慢平移，主界面不是一张静止的图。
	var zoom := 1.06 + 0.02 * sin(clock * 0.1)
	for cover in covers:
		cover.scale = Vector2(zoom, zoom)
		cover.position.x = -cover.size.x * 0.015 * sin(clock * 0.05)
	if Engine.get_process_frames() % 15 == 0 and ChapterPacks.downloading(selected): refresh()

func layout() -> void:
	if not is_node_ready(): return
	var view := get_viewport().get_visible_rect().size
	size = view
	for cover in covers:
		cover.size = view
		cover.pivot_offset = view * 0.5
	var narrow := view.x < 900.0
	var margin := 22.0 if narrow else 56.0
	var width := view.x - margin * 2.0
	logo.position = Vector2(margin, margin * 0.7)
	logo_sub.position = Vector2(margin + 2, margin * 0.7 + 52)
	# 章节卡片：宽屏一行四张，窄屏两行两张。
	var columns := 2 if narrow else 4
	var gap := 14.0 if narrow else 20.0
	var card_width := (width - gap * (columns - 1)) / columns
	var card_height := card_width * 9.0 / 16.0 + 48.0
	var rows := ceili(float(cards.size()) / columns)
	var cards_top := view.y - margin * 0.8 - rows * card_height - (rows - 1) * gap - 18.0
	for i in range(cards.size()):
		var card = cards[i]
		card.position = Vector2(margin + (i % columns) * (card_width + gap), cards_top + (i / columns) * (card_height + gap))
		card.size = Vector2(card_width, card_height)
	footer.position = Vector2(margin, view.y - 24)
	footer.size = Vector2(width, 0)
	var column := minf(width, 620.0)
	var y := cards_top - 26.0
	enter_button.position = Vector2(margin, y - 54)
	status_chip.position = Vector2(margin + 236, y - 42)
	y -= 74
	notice.visible = not notice.text.is_empty()
	reload_button.position = Vector2(margin + column - 120, y - 40)
	if notice.visible:
		notice.position = Vector2(margin, y - 34)
		notice.custom_minimum_size = Vector2(column - 130, 0)
		notice.size = Vector2(column - 130, 0)
		y -= 48
	facts.position = Vector2(margin, y - 22)
	y -= 30
	# 自动换行的文字先定宽，最小高度才按实际行数计算。
	summary.custom_minimum_size = Vector2(column, 0)
	summary.size = Vector2(column, 0)
	var summary_height := summary.get_combined_minimum_size().y
	summary.size.y = summary_height
	summary.position = Vector2(margin, y - summary_height)
	y -= summary_height + 10
	route.position = Vector2(margin, y - 22)
	route.size = Vector2(width, 0)
	route.visible = not narrow
	if not narrow: y -= 30
	heading.add_theme_font_size_override("font_size", 40 if narrow else 56)
	heading.position = Vector2(margin, y - (52 if narrow else 72))
	kicker.position = Vector2(margin, y - (78 if narrow else 100))
	logo.add_theme_font_size_override("font_size", 30 if narrow else 40)
