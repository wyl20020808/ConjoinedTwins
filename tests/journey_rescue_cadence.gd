extends SceneTree

# 使用生产旅程和原始跳跃键状态；固定频率以外保留反应时间与不规则按键间隔。
const Journey=preload("res://scripts/journey_run.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",message)
func _initialize()->void:call_deferred("verify")

func trial(difficulty:String,role:int,prior:int,fps:int,mode:String,rate:float=2.0)->void:
	var run=Journey.new()
	run.difficulty=difficulty;run.state="running";run.rescue_count=prior
	run.a.position=Vector2(run.EDGE-70,100)
	run.b.position=Vector2(run.EDGE-30,100)
	run.last_support=[run.a.position,run.b.position];run.ground_support=[true,true]
	run.rope.reset(run.a.position,run.b.position)
	run.begin_fall(role,Vector2(run.EDGE+12,100))
	check(run.state=="rescue","进入生产救援")
	check(is_equal_approx(run.rescue.rate,run.RESCUE_RATES[difficulty]),"多次救援保持相同频率门槛")
	var next_press:=fps # 先留一秒反应时间。
	var intervals:=[0.4,0.6,0.45,0.55]
	var press_index:=0
	var frames:=0
	while run.state=="rescue" and frames<ceili((run.RESCUE_TIME+run.RESCUE_CLIMB_TIME+1.0)*fps):
		var pressed:=false
		if mode=="hold":pressed=frames>=fps
		elif mode in ["paced","jitter"] and frames==next_press:
			pressed=true
			next_press+=maxi(2,roundi(fps*(intervals[press_index%intervals.size()] if mode=="jitter" else 1.0/rate)))
			press_index+=1
		var jumps:=[false,false]
		jumps[1-role]=pressed
		run.step(1.0/fps,Vector2.ZERO,Vector2.ZERO,jumps[0],jumps[1])
		frames+=1
	var success:bool=mode in ["paced","jitter"]
	check(run.state==("running" if success else "failed"),"%s %s role=%d prior=%d fps=%d state=%s"%[difficulty,mode,role,prior,fps,run.state])
	if success:
		var point:Vector2=run.a.position if role==0 else run.b.position
		check(run.has_ground_support(point) and run.rescue_count==prior+1,"正常按键救起后站稳并计数")
		check(frames/float(fps)<=run.RESCUE_TIME+run.RESCUE_CLIMB_TIME,"正常节奏在限时内拉满并爬上")
	print("CADENCE ",difficulty," mode=",mode," role=",role," prior=",prior," fps=",fps," seconds=",frames/float(fps)," state=",run.state)
	run.dispose()

func verify()->void:
	for role in range(2):
		for fps in [30,60,120]:trial("普通",role,0,fps,"paced")
		for prior in [8,32]:trial("普通",role,prior,60,"paced")
		trial("普通",role,0,60,"jitter")
		trial("普通",role,0,60,"hold")
		trial("普通",role,0,60,"none")
		trial("简单",role,0,60,"paced",2.0)
		trial("困难",role,0,60,"paced",3.0)
	print("JOURNEY_RESCUE_CADENCE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
