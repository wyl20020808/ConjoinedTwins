extends Node
# 入口：先显示主界面选章，只依赖主包（脚本、界面与封面），不下载任何章节资源。
# 选中章节后：下载该章数据包（网页版，已缓存则直接读取）→ 后台读取首屏资源 → 分帧准备生产场景，
# 全程显示该章的载入画面与进度。回到主页时释放旧场景，换章不残留上一章资源。
# 无界面运行（自动化检查）或带 --chapter=N 时跳过主界面，直接进入对应章节。
const AssetQueue = preload("res://scripts/road_asset_queue.gd")
const MainMenu = preload("res://scripts/main_menu.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const Catalog = preload("res://scripts/chapter_catalog.gd")
const JOURNEY := "res://scenes/journey.tscn"
var assets = AssetQueue.new()
var game: Node
var overlay: CanvasLayer
var menu
var loading
var chapter := 0
# menu / download / assets / scene / playing / error
var phase := "menu"
var show_menu := true
var direct_chapter := 0
# 主界面可用（显示过主界面或用 --chapter 指定章节）时，游戏内“回到主页”回到章节选择。
var menu_entry := true
var first_frame := true
var download_share := 0.0
var bootstrap_ready_usec := 0
var started := Time.get_ticks_usec()

func _init() -> void:
	show_menu = DisplayServer.get_name() != "headless"
	menu_entry = show_menu
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			show_menu = false
			menu_entry = true
			direct_chapter = clampi(int(arg.get_slice("=", 1)), 0, Catalog.ENTRIES.size() - 1)

func _exit_tree() -> void:
	assets.dispose()

func _ready() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	menu = MainMenu.new()
	menu.chapter_chosen.connect(enter_chapter)
	overlay.add_child(menu)
	loading = LoadingScreen.new()
	loading.visible = false
	loading.retry_pressed.connect(func(): enter_chapter(chapter))
	overlay.add_child(loading)
	bootstrap_ready_usec = Time.get_ticks_usec() - started
	if not show_menu:
		menu.visible = false
		enter_chapter(direct_chapter)

func enter_chapter(value: int) -> void:
	chapter = value
	if is_instance_valid(game):
		game.queue_free()
		game = null
	assets.error = ""
	menu.visible = false
	loading.setup(chapter)
	loading.visible = true
	overlay.visible = true
	phase = "download"
	first_frame = true
	# 需要下载时进度条前七成给下载，其余给读取与场景准备。
	download_share = 0.7 if ChapterPacks.bytes_missing(chapter) > 0 or ChapterPacks.manifest_state == "loading" else 0.0
	ChapterPacks.request(chapter, true)

func back_to_menu() -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
	phase = "menu"
	loading.visible = false
	menu.visible = true
	overlay.visible = true
	menu.refresh()

func _process(_delta: float) -> void:
	match phase:
		"download": process_download()
		"assets": process_assets()
		"scene": process_scene()

func process_download() -> void:
	if ChapterPacks.blocked():
		loading.set_stage("章节数据下载失败", ChapterPacks.progress(chapter) * download_share)
		loading.show_error(ChapterPacks.failure)
		return
	loading.show_error("")
	if not ChapterPacks.is_ready(chapter):
		var total := ChapterPacks.bytes_total(chapter)
		var done := ChapterPacks.bytes_done(chapter)
		var info := "%s / %s" % [ChapterPacks.megabytes(done), ChapterPacks.megabytes(total)] if total > 0 else ""
		if ChapterPacks.speed > 1024.0 and total > done:
			info += "　%s/秒 · 约 %d 秒" % [ChapterPacks.megabytes(int(ChapterPacks.speed)), ceili((total - done) / ChapterPacks.speed)]
		var text := "正在检查章节数据…" if ChapterPacks.manifest_state == "loading" else "正在下载章节数据"
		loading.set_stage(text, ChapterPacks.progress(chapter) * download_share, info, ChapterPacks.manifest_state == "loading")
		return
	phase = "assets"

func process_assets() -> void:
	# 在首次资源请求前让载入画面获得一帧绘制机会。
	if first_frame:
		first_frame = false
		assets.request(AssetQueue.startup_paths())
		return
	var ready: bool = assets.poll(Time.get_ticks_usec() + 2000)
	loading.set_stage("正在读取角色与地形资源", download_share + assets.progress() * (1.0 - download_share) * 0.45)
	if not assets.error.is_empty():
		loading.show_error("资源加载失败：%s。请刷新页面重试。" % assets.error.get_file())
		push_error("首屏资源加载失败：" + assets.error)
		phase = "error"
		return
	if not ready: return
	game = assets.resources[JOURNEY].instantiate()
	game.incremental_loading = true
	# 有界面的正式游玩才播开场运镜；无界面自动化检查直接开局。
	game.opening_enabled = DisplayServer.get_name() != "headless"
	if chapter == Catalog.TRAINING: game.training_entry = true
	else: game.start_chapter = chapter
	# 保持首屏资源强引用，后续主题换材质时直接复用已读入的贴图。
	game.chunk_assets.resources.merge(assets.resources)
	game.menu_entry = menu_entry or show_menu
	game.home_requested.connect(back_to_menu)
	add_child(game)
	phase = "scene"

func process_scene() -> void:
	if not is_instance_valid(game):
		phase = "menu"
		return
	if game.scene_prepared:
		overlay.visible = false
		loading.visible = false
		phase = "playing"
		return
	var base := download_share + (1.0 - download_share) * 0.45
	loading.set_stage("正在准备沿途场景", base + game.scene_preparation_progress * (1.0 - base))
