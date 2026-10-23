extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const T = Run.Templates
var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures += 1
func _initialize() -> void:
	var complete := true
	var repeatable := true
	var gates_spaced := true
	var dynamic_coverage := true
	for level in range(3):
		for seed_value in [1,42,4242,812208,20261014,999999]:
			var first = T.new()
			var second = T.new()
			first.reset(seed_value)
			second.reset(seed_value)
			var seen: Array = []
			var last_gate := -100
			var dynamics := 0
			for number in range(30):
				var block: Dictionary = first.candidate_block(number,level)
				repeatable = repeatable and var_to_str(block) == var_to_str(second.candidate_block(number,level))
				if number < 18: seen.append(block.route)
				if block.route in T.GATE_ROUTES:
					gates_spaced = gates_spaced and number-last_gate >= 3
					last_gate = number
				if block.route in T.DYNAMIC_ROUTES: dynamics += 1
			for route in ["shuttle","piston","sweep_pair","narrow_dual","narrow_triple"]: complete = complete and seen.has(route)
			dynamic_coverage = dynamic_coverage and dynamics >= 10 and dynamics <= 20
	check(complete,"18 组种子/关卡前18段均包含五种新布局")
	check(repeatable,"分类编排同种子完全可复现")
	check(gates_spaced,"等待型机关之间至少隔两个非机关段")
	check(dynamic_coverage,"前30段动态段占比保持在三分之一至三分之二")
	var distributed := true
	for mode in T.DIFFICULTIES:
		for seed_value in [1,42,4242]:
			var picker := RandomNumberGenerator.new()
			picker.seed = seed_value
			var extras := T.extra_hazards(T.make_block("safe",0,0),[],picker,mode,0)
			var ys: Array = extras.map(func(h): return h.rect.get_center().y)
			ys.sort()
			distributed = distributed and extras.size() >= 2 and extras.size() <= 4
			for i in range(1,ys.size()): distributed = distributed and ys[i]-ys[i-1] > 100
	check(distributed,"额外陷阱限量且纵向间隔超过5米，不随机扎堆")
	var picker := RandomNumberGenerator.new()
	picker.seed = 4242
	var gate_extras := T.extra_hazards(T.make_block("charge_cargo",1,0),[],picker,"困难",0)
	check(not gate_extras.is_empty() and gate_extras.all(func(h): return h.rect.position.y > 350),"门前位置被保护时仍能独立布置后续位置")
	# 强制前三个候选均为无法通过的全幅坑，确认第四候选仍须经过生产验证。
	var source = Run.new(false)
	var request: Dictionary = source.generation_request(source.generator,0,T.START_DISTANCE)
	var blocked := T.make_block("safe",0,0)
	blocked.hazards = [{"kind":"road_gap","rect":Rect2(-400,100,800,440)}]
	for index in range(3): request.candidates[index] = blocked.duplicate(true)
	var proven := Run.verification_worker(request,T.Cancellation.new())
	check(proven.block.get("route","") == "left" and not proven.block.hazards.is_empty(),"随机变体全失败后使用经过验证的非空绕箱段")
	source.dispose()
	# 实际整关：核验已安装布局，不能只拿抽签结果冒充正式内容。
	var run = Run.new(true,true)
	run.seed_value = 4242
	run.difficulty = "普通"
	run.retry()
	var kinds := {}
	var empty := 0
	var fallback := 0
	for tick in range(20000):
		while run.async_thread != null and run.async_thread.is_alive(): OS.delay_msec(1)
		var input: Array = T.existing_route_input(run)
		run.step(Run.FIXED_STEP,input[0],input[1],input[2],input[3])
		if run.state != "running": break
	for block in run.block_history.values():
		kinds[block.route] = kinds.get(block.route,0)+1
		if block.hazards.is_empty() and not block.has("gates") and not block.has("gate"): empty += 1
	for event in run.async_events:
		if event.get("source","").begins_with("safe"): fallback += 1
	check(run.state == "settlement", "生产整关实际通关")
	check(empty == 0 and fallback == 0,"生产已安装段落没有空路回退")
	var new_present := true
	for route in ["shuttle","piston","sweep_pair","narrow_dual","narrow_triple"]: new_present = new_present and kinds.has(route)
	check(new_present,"五种新布局均实际安装并通过")
	print("RHYTHM installed=",run.next_segment," empty=",empty," safe_fallback=",fallback," routes=",kinds)
	run.dispose()
	print("OBSTACLE_RHYTHM failures=",failures)
	quit(1 if failures else 0)
