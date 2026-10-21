extends SceneTree
# 主界面与载入画面的离屏截图，供版面自查；只通过 capture_hidden.py 在隐藏窗口运行：
#   python build-tools/capture_hidden.py res://build-tools/capture_menu_screens.gd
# 输出到 builds/menu-capture/（不入库）。截图不代表真实设备与浏览器内的观感验收。
const OUT := "res://builds/menu-capture/"
const LoadingScreen = preload("res://scripts/loading_screen.gd")

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String) -> void:
	for n in range(20): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("MENU_CAPTURE ", name)

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var boot = load("res://scenes/journey_boot.tscn").instantiate()
	boot.show_menu = true
	root.add_child(boot)
	await shot("01-menu-chapter1")
	boot.menu.select(2)
	await shot("02-menu-chapter3")
	boot.menu.select(3)
	await shot("03-menu-training")
	boot.queue_free()
	await process_frame
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var loading = LoadingScreen.new()
	layer.add_child(loading)
	loading.setup(1)
	loading.set_stage("正在下载章节数据", 0.46, "56.4 / 123.2 MB　1.2 MB/秒 · 约 56 秒")
	await shot("04-loading-chapter2")
	loading.setup(0, "online")
	loading.set_steps([["连接联机服务器", "done"], ["等待队友加入", "done"], ["同步章节：第一章 · 穿林入村", "done"], ["下载章节数据 61.0 / 133.3 MB", "active"], ["准备沿途场景", "pending"], ["等待双方就绪", "pending"]])
	loading.set_players([{"role": 0, "name": "你", "status": "下载中 46%", "ready": false}, {"role": 1, "name": "队友", "status": "已就绪", "ready": true}])
	loading.set_stage("下载章节数据 61.0 / 133.3 MB", 0.55, "联机中 · 你是 01 号")
	await shot("05-loading-online")
	quit(0)
