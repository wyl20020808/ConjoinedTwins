extends SceneTree

# 悬崖边缘：走出路面即坠落并判负，队友被连线拖下去；路面内不受影响。
# 非 headless 运行时额外保存一张坠落过程截图。
const Run = preload("res://scripts/road_run.gd")
var failed := 0

func check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok: failed += 1

func _initialize() -> void:
	call_deferred("main")

func main() -> void:
	for side in [-1.0, 1.0]:
		var run = Run.new(false)
		run.retry()
		var ticks := 0
		while run.state == "running" and ticks < 600:
			run.step(Run.FIXED_STEP, Vector2(side, 0), Vector2(side, 0))
			ticks += 1
		var tag := "左侧" if side < 0 else "右侧"
		check(tag + "走出路面坠崖判负", run.state == "failed" and run.reason.contains("悬崖") and run.fallen == ([true, false] if side < 0 else [false, true]))
		var outer: float = maxf(absf(run.a.position.x), absf(run.b.position.x))
		check(tag + "坠落点刚越过边缘", outer > Run.EDGE and outer <= Run.EDGE + Run.FALL_REACH)
		run.retry(true)
		check(tag + "重试清除坠落标记", run.fallen == [false, false] and run.state == "running")
		run.dispose()
	var safe = Run.new(false)
	safe.retry()
	safe.a.position = Vector2(-Run.EDGE, 0)
	safe.b.position = Vector2(-Run.EDGE + 60, 0)
	safe.rope.reset(safe.a.position, safe.b.position)
	for tick in range(240): safe.step(Run.FIXED_STEP)
	check("贴着边缘内侧行走不坠落", safe.state == "running")
	# 空中越过边缘：落地时没有支撑才判负。
	for tick in range(40): safe.step(Run.FIXED_STEP, Vector2(-1, 0), Vector2.ZERO, tick > 2)
	check("跳出路面落地时坠崖", safe.state == "failed" and safe.reason.contains("悬崖"))
	safe.dispose()
	if DisplayServer.get_name() != "headless":
		var game = load("res://scenes/road_demo.tscn").instantiate()
		root.add_child(game)
		game.set_physics_process(false)
		game.primary_action()
		for tick in range(400):
			game.run.step(1.0 / 120, Vector2(-1, 0), Vector2(-1, 0))
			if game.run.state != "running": break
		game.fall_clock = 0.55
		game.sync_view()
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build-tools/playfix-20261013/shots-cliff/fall.png")
		print("CAPTURE fall state=", game.run.state, " reason=", game.run.reason)
		game.queue_free()
		await process_frame
	print("FALL failed=%d" % failed)
	quit(1 if failed > 0 else 0)
