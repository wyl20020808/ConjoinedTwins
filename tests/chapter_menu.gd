extends SceneTree
# 主界面选章流程：主界面不加载生产场景；选章后进入对应章节；回到主页释放场景；战斗训练入口；
# 章节资料与玩法章节表一致；联机帧二进制编解码往返一致。
# 用法：Godot --headless --path . --script res://tests/chapter_menu.gd
const Catalog = preload("res://scripts/chapter_catalog.gd")
const Journey = preload("res://scripts/journey_run.gd")
const Relay = preload("res://scripts/net_relay.gd")
var failures: Array = []

func check(ok: bool, name: String) -> void:
	print("PASS " if ok else "FAIL ", name)
	if not ok: failures.append(name)

func _initialize() -> void:
	call_deferred("validate")

func until(predicate: Callable, seconds: float = 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func validate() -> void:
	var same := true
	for i in range(Journey.CHAPTERS.size()):
		same = same and Catalog.entry(i).name == Journey.CHAPTERS[i].name and Catalog.entry(i).zones == Journey.CHAPTERS[i].zones
	check(same and Catalog.entry(Catalog.TRAINING).zones == Journey.TRIAL_ZONES, "章节资料与玩法章节表一致")
	check(range(4).all(func(i): return Catalog.cover(i) != null), "四个章节封面都能读取")
	var packs = root.get_node("ChapterPacks")
	check(packs.manifest_state == "none" and range(4).all(func(i): return packs.is_ready(i)), "原生运行无拆包清单时全部章节就绪")
	var frame := Relay.encode_frame(123456, [100, -100, true], [-37, 55, false], true, false, [[1, "chapter", "2"]])
	var decoded := Relay.decode_frame(frame)
	check(decoded.index == 123456 and decoded.a == Vector2(1, -1) and decoded.b == Vector2(-0.37, 0.55) and decoded.ja and not decoded.jb and decoded.cmds == [[1, "chapter", "2"]], "联机帧二进制编解码往返一致")
	check(Relay.encode_frame(7, [0, 0, false], [0, 0, false], false, false, []).size() == 11, "无命令的联机帧只有 11 字节")
	var boot = load("res://scenes/journey_boot.tscn").instantiate()
	boot.show_menu = true
	root.add_child(boot)
	await process_frame
	await process_frame
	check(boot.menu.visible and boot.game == null and boot.phase == "menu", "启动后先显示主界面，不建立生产场景")
	check(not ResourceLoader.has_cached("res://scenes/journey.tscn"), "主界面阶段不读取生产场景")
	check(boot.menu.cards.size() == 4 and boot.menu.status_text(0) == "已就绪", "主界面有四张章节卡片")
	boot.menu.select(1)
	check(boot.menu.heading.text == "水车河道" and boot.menu.kicker.text == "第二章", "选中卡片更新章节标题")
	boot.menu.choose(2)
	check(boot.loading.visible and not boot.menu.visible, "选章后显示该章载入画面")
	check(boot.loading.heading.text == "矿道归航", "载入画面显示所选章节")
	check(await until(func(): return boot.game != null and boot.game.scene_prepared), "第三章场景准备完成")
	check(boot.game.run.level_index == 2 and not boot.game.run.combat_trial and boot.game.run.state == "start", "直接进入第三章开始页")
	check(not boot.overlay.visible, "准备完成后收起载入画面")
	check(boot.game.title.text == "第三章 · 矿道归航", "开始页标题显示章节")
	var first = boot.game
	boot.game.return_home()
	await process_frame
	check(boot.menu.visible and boot.game == null and boot.phase == "menu", "回到主页回到章节选择")
	await process_frame
	check(not is_instance_valid(first), "回到主页释放上一章场景")
	boot.menu.choose(Catalog.TRAINING)
	check(await until(func(): return boot.game != null and boot.game.scene_prepared), "战斗训练场景准备完成")
	check(boot.game.run.combat_trial, "训练卡片进入战斗训练")
	boot.queue_free()
	for n in range(4): await process_frame
	print("CHAPTER MENU failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
