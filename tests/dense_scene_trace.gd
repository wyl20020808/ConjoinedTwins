extends SceneTree

const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")

func _initialize() -> void:
	var traces: Array=[]
	for chapter in range(3):
		var run=Journey.new();run.random_seed=false;run.seed_value=8123;run.level_index=chapter;run.retry()
		run.state="running";run.clear_input=false;run.solo_control=true;run.external_companion=true
		var found:=false
		for offset in [0,100,-100,200,-200]:
			for x in [-42,-120,80,-200,180]:
				var point:=Vector2(x,9600+offset)
				if run.Monsters.safe_spawn(run,point) and run.Monsters.safe_spawn(run,point+Vector2(56,0)):
					run.a.position=point;run.b.position=point+Vector2(56,0);found=true;break
			if found:break
		assert(found)
		run.distance=run.a.position.y;run.elapsed=10
		for gate in run.charge_gates:
			gate.open=gate.receiver.y<run.distance-180;gate.opened_at=0 if gate.open else -1
		run.select_charge_gate();run.rope.reset(run.a.position,run.b.position)
		run.combat.weapons=[run.Combat.gun(),run.Combat.gun()]
		run.capture_checkpoint()
		var buddy=Buddy.new();var frames: Array=[]
		for frame in range(240):
			var move:Vector2=[Vector2(0,1),Vector2.RIGHT,Vector2.ZERO,Vector2(0,-1),Vector2.LEFT,Vector2(0,1)][frame/40]
			var jump:bool=frame%47==0
			if frame==65 or frame==80:run.pause()
			if frame==150:run.fail_threat("对照存档恢复");run.restore_checkpoint();buddy.reset()
			var companion:Dictionary=buddy.think(run,run.FIXED_STEP,move,jump)
			run.set_combat_input(frame<120,frame==121,frame==200)
			run.step(run.FIXED_STEP,move,companion.move,jump,companion.jump)
			frames.append([run.sync_hash(),companion,run.state,run.combat.health.duplicate()])
		traces.append({"chapter":chapter,"hazards":run.kinds.size(),"events":run.journey_events.size(),"frames":frames})
		run.dispose()
	var output:=OS.get_environment("DENSE_TRACE_REPORT")
	assert(not output.is_empty(),"请设置 DENSE_TRACE_REPORT")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(traces))
	print("DENSE TRACE frames=720");quit()
