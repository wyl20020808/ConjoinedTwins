extends SceneTree
# 章节封面取景：用真实生产场景渲染每章代表性地段，输出无 UI 的原始画面，再由
# make_chapter_covers.py 裁切压缩为 assets/ui/covers/ 下的封面。
# 只通过 build-tools/capture_hidden.py 在隐藏窗口中运行，不打开可见窗口：
#   python build-tools/capture_hidden.py res://build-tools/capture_chapter_covers.gd
# 每个机位：[章节(3=战斗训练), 进度(0-1), 镜头位置偏移, 注视点偏移, 视角]
const OUT := "res://builds/cover-capture/"
const SHOTS := [
	[0, 0.30, Vector3(-3.0, 4.2, 12.0), Vector3(1.0, 1.4, -30.0), 52.0],
	[0, 0.76, Vector3(-3.5, 4.4, 12.5), Vector3(1.0, 1.8, -32.0), 52.0],
	[0, 0.80, Vector3(3.5, 4.0, 12.0), Vector3(-1.0, 1.8, -32.0), 52.0],
	[1, 0.56, Vector3(3.0, 4.2, 12.0), Vector3(-1.0, 1.6, -32.0), 52.0],
	[1, 0.60, Vector3(-3.5, 4.2, 12.0), Vector3(1.0, 1.6, -32.0), 52.0],
	[1, 0.68, Vector3(3.5, 4.0, 12.0), Vector3(-1.0, 1.8, -30.0), 52.0],
	[2, 0.30, Vector3(-3.0, 4.2, 12.0), Vector3(1.0, 1.8, -32.0), 52.0],
	[2, 0.55, Vector3(3.0, 4.0, 12.0), Vector3(-1.0, 2.0, -30.0), 52.0],
	[2, 0.62, Vector3(-3.5, 4.4, 12.5), Vector3(1.0, 2.2, -32.0), 52.0],
	[3, 0.20, Vector3(-3.0, 4.0, 11.0), Vector3(1.0, 1.4, -28.0), 52.0],
	[3, 0.45, Vector3(3.0, 4.2, 12.0), Vector3(-1.0, 1.6, -30.0), 52.0],
	[3, 0.70, Vector3(-3.0, 4.2, 12.0), Vector3(1.0, 1.6, -30.0), 52.0],
]
const SEED := 20261012
const Combat = preload("res://scripts/journey_combat.gd")
var game

func _initialize() -> void:
	call_deferred("capture")

func open(chapter: int) -> void:
	if game != null:
		game.queue_free()
		for n in range(4): await process_frame
	game = load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading = true
	if chapter == 3: game.training_entry = true
	else: game.start_chapter = chapter
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false)
	game.run.random_seed = false
	game.run.seed_value = SEED
	game.run.retry()
	game.run.state = "paused"

# 封面只保留场景与人物：界面层、头顶编号与拾取物文字一律隐藏。
func hide_ui(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer or child is Label3D: child.visible = false
		hide_ui(child)

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var opened := -1
	var index := 0
	for shot in SHOTS:
		if shot[0] != opened:
			await open(shot[0])
			opened = shot[0]
		var y: float = game.run.finish_distance() * shot[1]
		game.run.distance = y
		game.run.a.position = Vector2(-28, y)
		game.run.b.position = Vector2(28, y + 30)
		game.run.rope.reset(game.run.a.position, game.run.b.position)
		# 两人持枪入画；地面补给光柱会遮挡人物，取景时移除。
		game.run.combat.pickups.clear()
		game.run.combat.weapons = [Combat.gun("smg"), Combat.gun("shotgun")]
		var waits := 0
		while waits < 3000:
			var ready: bool = game.prepare_journey_frame()
			if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty(): break
			waits += 1
			await process_frame
		hide_ui(game)
		var focus := Vector3(0, 0, -y / 20.0)
		for n in range(24):
			game.sync_view()
			hide_ui(game)
			game.camera.fov = shot[4]
			game.camera.transform = Transform3D.IDENTITY.translated(focus + shot[2]).looking_at(focus + shot[3], Vector3.UP)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := OUT + "shot_%02d_ch%d.png" % [index, shot[0]]
		var error := root.get_texture().get_image().save_png(path)
		print("COVER_CAPTURE ", path, " error=", error, " waits=", waits)
		index += 1
	game.queue_free()
	for n in range(4): await process_frame
	quit(0)
