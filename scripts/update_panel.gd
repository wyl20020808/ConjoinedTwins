extends Control
# 云更新面板：启动时显示检查与下载进度；主界面“检查更新”打开后可编辑更新链接。
# 链接每行一个，按顺序尝试；主机换了隧道时，把新链接粘贴到第一行再点“保存并检查”即可。
signal closed

const CloudUpdate = preload("res://scripts/cloud_update.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")

var updater: CloudUpdate
var title: Label
var version: Label
var status: Label
var bar: ProgressBar
var links: TextEdit
var check_button: Button
var close_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.09, 0.96)
	style.border_color = Color(0.91, 0.74, 0.49, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	title = make_label(box, 24, Color("f7f2e6"))
	title.text = "检查更新"
	version = make_label(box, 14, Color(0.8, 0.85, 0.8, 0.8))
	var current := CloudUpdate.current_release()
	version.text = "当前版本：" + (current if not current.is_empty() else "未知")
	status = make_label(box, 16, Color("e6e9e0"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(bar)
	var hint := make_label(box, 14, Color(0.8, 0.85, 0.8, 0.85))
	hint.text = "更新链接（每行一个，按顺序尝试；主机换了链接就把新链接粘贴到第一行）"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	links = TextEdit.new()
	links.custom_minimum_size = Vector2(0, 86)
	links.placeholder_text = CloudUpdate.DEFAULT_URLS[0]
	links.text = "\n".join(CloudUpdate.user_urls())
	box.add_child(links)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	check_button = LoadingScreen.make_button("保存并检查更新", true)
	check_button.pressed.connect(check)
	row.add_child(check_button)
	close_button = LoadingScreen.make_button("返回", false)
	close_button.pressed.connect(func(): if not updater.busy: closed.emit())
	row.add_child(close_button)
	updater = CloudUpdate.new()
	add_child(updater)
	updater.progress.connect(func(text, ratio):
		status.text = text
		bar.value = ratio)
	updater.finished.connect(_on_finished)

func make_label(parent: Node, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result

# 启动时自动检查：不编辑链接，检查完由调用方决定继续进入主界面。
func start_check() -> void:
	title.text = "正在检查更新"
	set_busy(true)
	updater.run()

func check() -> void:
	CloudUpdate.save_user_urls(links.text.split("\n", false))
	links.text = "\n".join(CloudUpdate.user_urls())
	start_check()

func set_busy(value: bool) -> void:
	check_button.disabled = value
	close_button.disabled = value
	links.editable = not value

func _on_finished(outcome: String, message: String) -> void:
	set_busy(false)
	title.text = "检查更新"
	status.text = message
	bar.value = 1.0 if outcome == "current" else 0.0
