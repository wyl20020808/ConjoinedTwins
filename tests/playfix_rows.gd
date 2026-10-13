extends SceneTree

# 横排障碍：两人不操作、固定站在任何一条横向位置（包括贴着左右路边）都不能走完一关，
# 而且必须死于真实碰撞、踩空或绳索受阻，不是验证判负。
const Run = preload("res://scripts/road_run.gd")
var failed := 0

func check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok: failed += 1

func _initialize() -> void:
	var worst := 0.0
	for difficulty in ["简单", "困难"]:
		for level in range(3):
			var survivors: Array = []
			var unfair: Array = []
			var farthest := 0.0
			for lateral in [-190, -150, -100, -50, 0, 50, 100, 150, 190]:
				var run = Run.new(true, true)
				run.difficulty = difficulty
				run.level_index = level
				run.retry()
				run.a.position = Vector2(lateral - 20, 0)
				run.b.position = Vector2(lateral + 20, 0)
				run.rope.reset(run.a.position, run.b.position)
				for tick in range(60 * 130):
					while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
					run.step(1.0 / 60)
					if run.state != "running": break
				if run.state != "failed": survivors.append(lateral)
				elif run.reason.contains("验证") or run.reason.contains("后台") or run.reason.contains("生成"): unfair.append(run.reason)
				else: farthest = maxf(farthest, run.progress() / 20.0)
				run.dispose()
			worst = maxf(worst, farthest)
			var tag := "%s 第%d关 " % [difficulty, level + 1]
			print(tag, "最远存活 ", snappedf(farthest, 0.1), " 米；走完的位置 ", survivors)
			check(tag + "任何固定横向位置都走不完", survivors.is_empty())
			check(tag + "失败均来自真实危险", unfair.is_empty())
	print("ROWS failed=%d farthest_m=%.1f" % [failed, worst])
	quit(1 if failed > 0 else 0)
