extends SceneTree
# 拆包后的网页数据巡检：只挂载主包，经 HTTP 下载并挂载某一章所需的数据包，再把这一章整章流式加载一遍。
# 由 build-tools/verify_web_packs.py 调用（它负责起本机 HTTP 服务、逐章启动进程并检查日志）：
#   Godot --headless --main-pack builds/web/index.pck -s <工程>/build-tools/verify_web_packs.gd -- --packs-url=http://127.0.0.1:端口/ --chapter=N
# 巡检种子与生成用量记录的种子不同，用来发现“用量记录漏掉、该章又确实需要”的资源。
# 边界：桌面无头运行，不走 OS.has_feature("web") 分支，也不验证浏览器内的下载与缓存。
const SEEDS := [11, 2024, 88888, 777]
var errors := 0

func _initialize() -> void:
	call_deferred("run")

func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.get_slice("=", 1)
	return fallback

func run() -> void:
	var chapter := int(option("chapter", "0"))
	var packs = root.get_node("ChapterPacks")
	while packs.manifest_state == "loading": await process_frame
	if not packs.enabled:
		printerr("VERIFY_WEB_PACKS no manifest: ", packs.manifest_state, " ", packs.failure)
		quit(2)
		return
	var others := 0
	for other in range(4):
		if other != chapter: others += packs.bytes_total(other)
	packs.request(chapter, true)
	while not packs.is_ready(chapter) and not packs.blocked(): await process_frame
	if packs.blocked():
		printerr("VERIFY_WEB_PACKS download failed: ", packs.failure)
		quit(3)
		return
	print("VERIFY_WEB_PACKS chapter=", chapter, " mounted=", packs.mounted.keys(), " bytes=", packs.bytes_total(chapter))
	for path in load("res://scripts/road_asset_queue.gd").startup_paths(true) + load("res://scripts/road_asset_queue.gd").startup_paths(false):
		if load(path) == null:
			errors += 1
			printerr("VERIFY_WEB_PACKS missing startup ", path)
	var game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	if chapter == 3: game.training_entry = true
	else: game.start_chapter = chapter
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	game.web_test_mode = true
	for path in game.WEB_WARM_PATHS:
		if load(path) == null:
			errors += 1
			printerr("VERIFY_WEB_PACKS missing warm ", path)
	for seed in SEEDS:
		game.run.random_seed = false
		game.run.seed_value = seed
		if chapter < 3: game.run.level_index = chapter
		game.run.retry()
		game.run.state = "paused"
		var finish: float = game.run.finish_distance()
		var location := 0.0
		while location <= finish + 400:
			game.run.distance = location
			game.run.a.position.y = location
			game.run.b.position.y = location
			var waits := 0
			while waits < 3000:
				var ready: bool = game.prepare_journey_frame()
				if not game.chunk_assets.error.is_empty():
					errors += 1
					printerr("VERIFY_WEB_PACKS asset error ", game.chunk_assets.error)
					game.chunk_assets.error = ""
				if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty(): break
				waits += 1
				await process_frame
			if waits >= 3000:
				errors += 1
				printerr("VERIFY_WEB_PACKS stuck seed=", seed, " at=", location)
			game.sync_view()
			await process_frame
			location += 400.0
		print("VERIFY_WEB_PACKS sweep chapter=", chapter, " seed=", seed)
	for player in game.sfx.players: player.stop()
	game.queue_free()
	for n in range(4): await process_frame
	print("VERIFY_WEB_PACKS done chapter=", chapter, " errors=", errors, " other_chapter_bytes=", others)
	quit(0 if errors == 0 else 1)
