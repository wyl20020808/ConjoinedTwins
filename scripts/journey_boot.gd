extends Node
# 轻量入口先显示加载页；生产场景和贴图在后台读取。
const AssetQueue = preload("res://scripts/road_asset_queue.gd")
var assets = AssetQueue.new()
var game: Node
var overlay: CanvasLayer
var caption: Label
var bar: ProgressBar
var first_frame := true
var scene_started := false
var bootstrap_ready_usec := 0
var started := Time.get_ticks_usec()
func _ready() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var background := ColorRect.new()
	background.color = Color("0e1822")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(background)
	caption = Label.new()
	caption.text = "正在准备旅程…"
	caption.position = Vector2(360, 280)
	caption.size = Vector2(560, 80)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 28)
	overlay.add_child(caption)
	bar = ProgressBar.new()
	bar.position = Vector2(360, 370)
	bar.size = Vector2(560, 28)
	overlay.add_child(bar)
	bootstrap_ready_usec = Time.get_ticks_usec() - started
func _process(_delta: float) -> void:
	# 在首次资源请求前让 UI 获得一帧绘制机会。
	if first_frame:
		first_frame = false
		assets.request(AssetQueue.startup_paths())
		return
	if scene_started:
		if game.scene_prepared:
			overlay.hide()
			assets.resources.clear()
			set_process(false)
		else:
			caption.text = "正在准备场景…"
			bar.value = 80.0 + game.scene_preparation_progress * 20.0
		return
	var ready: bool = assets.poll(Time.get_ticks_usec() + 2000)
	bar.value = assets.progress() * 80.0
	if not assets.error.is_empty():
		caption.text = "资源加载失败，请重新启动。"
		push_error("首屏资源加载失败：" + assets.error)
		set_process(false)
		return
	if not ready: return
	game = assets.resources["res://scenes/journey.tscn"].instantiate()
	game.incremental_loading = true
	# 保持首屏资源强引用，后续主题换材质时直接复用已读入的贴图。
	game.chunk_assets.resources.merge(assets.resources)
	scene_started = true
	add_child(game)
