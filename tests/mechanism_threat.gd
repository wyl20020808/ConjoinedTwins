extends SceneTree

const Run=preload("res://scripts/road_run.gd")
var failures:=0

func _initialize()->void:
	for level in range(3):
		for difficulty in Run.Templates.DIFFICULTIES:
			var run=Run.new(false)
			run.level_index=level
			run.difficulty=difficulty
			run.retry()
			run.install_block(Run.Templates.make_block("steam_corridor",1,level),600,"threat")
			for tick in range(1600):
				run.step(Run.FIXED_STEP)
				if run.state!="running": break
			var ok:bool=run.state=="failed" and run.reason.contains("喷口")
			print("PASS " if ok else "FAIL ","不操作不能直接穿过喷口长廊 L",level+1," ",difficulty," state=",run.state," reason=",run.reason)
			if not ok: failures+=1
			run.dispose()
	print("MECHANISM_THREAT failures=",failures)
	quit(1 if failures else 0)
