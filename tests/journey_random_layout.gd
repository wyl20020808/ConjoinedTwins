extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
const Layout=preload("res://scripts/journey_random.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func fingerprint(run)->int:
	var enemies:Array=[]
	for event in run.journey_events:
		if event.kind=="monster":enemies.append([event.origin,event.archetype])
	return hash([run.encounter_markers,run.kinds,run.obstacles,enemies])
func _initialize()->void:
	var records:Array=[]
	# 验证长样本配比，同时要求不同种子的顺序发生变化。
	var orders:={}
	for seed_value in range(12):
		var stream=Layout.new(seed_value,0,1)
		var counts:={3:0,4:0,5:0}
		var sequence:Array=[]
		for n in range(400):
			var size:int=stream.draw("density",[3,4,4,5])
			counts[size]+=1;sequence.append(size)
		check(counts=={3:100,4:200,5:100},"400 次群组抽样保持均值 4 与 1:2:1 配比")
		orders[hash(sequence)]=true
	check(orders.size()==12,"不同种子不复用同一固定顺序")
	var first=Journey.new(true);var second=Journey.new(true)
	check(first.seed_value!=second.seed_value and fingerprint(first)!=fingerprint(second),"生产构造每局使用新种子与不同布局")
	var first_seed:int=first.seed_value
	first.retry();check(first.seed_value!=first_seed,"主动重新开始更换种子")
	first.capture_checkpoint();var saved_seed:int=first.seed_value;var saved_layout:=fingerprint(first)
	first.state="failed"
	check(first.restore_checkpoint() and first.seed_value==saved_seed and fingerprint(first)==saved_layout,"从存档继续保留原地图")
	first.dispose();second.dispose()
	for chapter in range(3):
		var unique:={}
		var counts:Array=[]
		for seed_value in range(12):
			var run=Journey.new();run.level_index=chapter;run.seed_value=1000+seed_value;run.retry()
			var value:=fingerprint(run);unique[value]=true
			var types:={}
			var total:=0
			for event in run.journey_events:
				if event.kind!="monster":continue
				total+=1;types[event.archetype]=types.get(event.archetype,0)+1
				check(run.Monsters.safe_spawn(run,event.origin),"多种子怪物出生保留实体、缺口与合作门安全检查")
			var special:Array=[types.get("archer",0),types.get("dasher",0),types.get("wolf",0)]
			check(special.max()-special.min()<=1,"实际生成的远程、冲锋和狼保持配比")
			for n in range(1,run.encounter_markers.size()):
				var previous:Dictionary=run.encounter_markers[n-1]
				var current:Dictionary=run.encounter_markers[n]
				if current.blocked!=previous.blocked and current.y-previous.y<800:
					check(current.y-previous.y>=400,"随机换侧保留完整退出及横移空地")
			counts.append(total)
			records.append({"chapter":chapter,"seed":run.seed_value,"monsters":total,"encounters":run.encounter_markers.size(),"hash":value})
			# 重试与全局随机调用不应改变固定种子的布局。
			if seed_value==0:
				randf();run.retry();check(fingerprint(run)==value,"同种子重试布局完全复现")
			run.dispose()
		check(unique.size()==12,"每章 12 个种子均有不同的完整布局")
		var mean:=0.0
		for count in counts:mean+=count/float(counts.size())
		var variance:=0.0
		for count in counts:variance+=pow(count-mean,2)/counts.size()
		check(sqrt(variance)/mean<.15,"各局实际怪物数围绕均值波动，变异系数低于 15%")
		check(mean>(123 if chapter==0 else 101)*.8 and mean<(123 if chapter==0 else 101)*1.2,"随机化保持原有战斗密度的 20% 范围")
		print("RANDOM_DENSITY chapter=",chapter," mean=",mean," min=",counts.min()," max=",counts.max()," stddev=",sqrt(variance))
	var output:=OS.get_environment("RANDOM_LAYOUT_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"checks":checks,"failures":failures},"\t"))
	print("JOURNEY_RANDOM_LAYOUT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
