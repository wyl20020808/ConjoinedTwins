extends SceneTree
const Journey=preload("res://scripts/journey_run.gd")
class FullScan:
	extends "res://scripts/journey_run.gd"
	func front_sweep_near(_index:int,_previous:Rect2,_current:Rect2,_bounds:Rect2)->bool:return true
	func front_warning_near(_index:int,_forward_speed:float)->bool:return true
	func obstacles_in_bounds(_bounds:Rect2)->Array[int]:
		var all:Array[int]=[]
		for index in range(kinds.size()):all.append(index)
		return all
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:
	for kind in ["fly_low","fly_body","rocket","stone_ball","iron_ball"]:
		for position in [Vector2(-42,640),Vector2(0,640),Vector2(240,640),Vector2(-42,10000)]:
			var fast=Journey.new();var full=FullScan.new()
			for run in [fast,full]:
				run.journey_events.clear();run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
				run.charge_gates.clear();run.select_charge_gate();run.rewards.clear();run.combat=run.Combat.fresh();run.state="running";run.clear_input=false
				var size:Vector2=run.Threats.CONFIG[kind].size
				var index:int=run.add_hazard(kind,Rect2(position-size/2,size));run.hazard_specs[index].start_distance=0
			var same:=true
			for frame in range(240):
				for run in [fast,full]:run.step(run.FIXED_STEP,Vector2.ZERO,Vector2.ZERO,frame==30,frame==45)
				same=same and fast.sync_hash()==full.sync_hash()
			check(same,"full simulation equals unfiltered sweep "+kind+str(position))
			if position.y==10000 or position.x==240:check(fast.state=="running","far trajectory harmless "+kind)
			elif kind=="rocket" and position.x==-42:
				# 连续旅程现在按机关扣血；仍要求真实高速扫掠结算准确伤害，不能用存活掩盖漏判。
				check(fast.state=="running" and fast.combat.health[0]==100-fast.Combat.HAZARD_DAMAGE[kind],"fast projectile actually applies typed damage")
			fast.dispose();full.dispose()
	print("FRONT_SWEEP CHECKS ",checks," FAILURES ",failures.size());quit(0 if failures.is_empty() else 1)
