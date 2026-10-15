extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
func _initialize()->void:
	var records:Array=[]
	for chapter in range(3):
		var run=Journey.new();run.level_index=chapter;run.retry();run.state="running";run.clear_input=false
		# 同一密集地图、同一真实固定步；不关闭碰撞、绳索、危险或战斗。
		for frame in range(30):run.step(run.FIXED_STEP)
		var samples:Array=[]
		for frame in range(180):
			var start:=Time.get_ticks_usec();run.step(run.FIXED_STEP);samples.append(Time.get_ticks_usec()-start)
		samples.sort()
		records.append({"chapter":chapter,"hazards":run.kinds.size(),"state":run.state,"median_usec":samples[90],"p95_usec":samples[170]})
		run.dispose()
	print("POLISH_CPU ",JSON.stringify(records));quit()
