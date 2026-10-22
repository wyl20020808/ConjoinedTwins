extends SceneTree
# 当前前后移动、镜头高水位、换弹姿态和密集组合的生产回归。
const Journey=preload("res://scripts/journey_run.gd")
const Buddy=preload("res://scripts/journey_buddy.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func isolated():
	var run=Journey.new()
	run.journey_events.clear();run.obstacles.clear();run.kinds.clear();run.obstacle_heights.clear();run.obstacle_ids.clear();run.hazard_specs.clear()
	run.charge_gates.clear();run.select_charge_gate();run.rewards.clear();run.combat=run.Combat.fresh()
	run.state="running";run.clear_input=false
	return run
func ticks(run,count:int,move:Vector2)->void:
	for frame in range(count):run.step(run.FIXED_STEP,move,move)
func _initialize()->void:call_deferred("verify")
func verify()->void:
	var run=isolated()
	ticks(run,240,Vector2.DOWN)
	var progress:float=run.distance
	var before:Vector2=run.a.position
	ticks(run,60,Vector2.UP)
	check(run.a.position.y<before.y-70 and run.b.position.y<before.y-70,"both actors really retreat")
	check(run.distance==progress,"camera progress never retreats")
	ticks(run,360,Vector2.UP)
	check(absf(run.a.position.y-(progress-run.RETREAT_DISTANCE))<.01,"retreat stops at visible rear boundary")
	check(run.rope.length<=run.LINK_LIMIT+.01,"retreat respects rope")
	var stopped:Vector2=run.a.position
	ticks(run,60,Vector2.ZERO)
	check(run.a.position==stopped and run.distance==progress,"released input stops world and actors")
	run.dispose()
	run=isolated();ticks(run,240,Vector2.DOWN)
	var y:float=run.a.position.y
	run.add_hazard("cargo",Rect2(-120,y-90,240,40))
	ticks(run,120,Vector2.UP)
	check(run.a.position.y>=y-50+run.Motion.RADIUS-.01,"retreat cannot cross solid wall")
	run.dispose()
	run=isolated();ticks(run,240,Vector2.DOWN)
	run.add_hazard("road_gap",Rect2(-100,run.a.position.y-70,200,35))
	ticks(run,90,Vector2.UP)
	check(run.state in ["rescue","failed"],"retreat into real missing ground still falls")
	run.dispose()
	run=isolated();ticks(run,240,Vector2.DOWN)
	var buddy=Buddy.new();before=run.b.position
	for frame in range(80):
		var choice:Dictionary=buddy.think(run,run.FIXED_STEP,Vector2.UP)
		run.step(run.FIXED_STEP,Vector2.UP,choice.move,false,choice.jump)
	check(run.b.position.y<before.y-40,"single-player buddy follows retreat through ordinary inputs")
	run.dispose()
	for chapter in range(3):
		run=Journey.new();run.level_index=chapter;run.retry()
		check(run.obstacles.size()+run.journey_events.size()>200,"chapter %d has dense physical formations"%chapter)
		var gaps:int=run.kinds.count("road_gap")
		check(gaps>=30,"chapter %d has frequent real missing ground"%chapter)
		run.dispose()
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false);game.set_process(false)
	game.run.state="running";game.blocked_keys.clear()
	var key:=InputEventKey.new();key.keycode=KEY_S;key.physical_keycode=KEY_S;key.pressed=true
	Input.parse_input_event(key.duplicate());Input.flush_buffered_events()
	check(game.sample_local_input().a.y==-1,"S sampled as retreat")
	key.pressed=false;Input.parse_input_event(key.duplicate());Input.flush_buffered_events()
	game.play_mode="local";key.keycode=KEY_DOWN;key.physical_keycode=KEY_DOWN;key.pressed=true
	Input.parse_input_event(key.duplicate());Input.flush_buffered_events()
	check(game.sample_local_input().b.y==-1,"local player two Down sampled as retreat")
	key.pressed=false;Input.parse_input_event(key.duplicate());Input.flush_buffered_events()
	game.touch.move=Vector2(.2,-.8)
	check(game.sample_local_input().a.y<0,"touch joystick retains backward axis")
	game.touch.move=Vector2.ZERO
	game.run.combat.weapons[0]=game.run.Combat.gun()
	var weapon:Dictionary=game.run.combat.weapons[0]
	weapon.ammo=5;game.run.Combat.start_reload(game.run,0)
	game.sync_view()
	var gun:Node3D=game.combat_view.guns[0]
	var smg:Node3D=gun.get_node("smg")
	var start:Transform3D=gun.transform
	weapon.reload=84;game.sync_view()
	check(not gun.transform.is_equal_approx(start),"reload raises and tilts gun")
	check(not smg.get_node("Magazine").visible,"old magazine discarded while left hand fetches a new one")
	weapon.reload=118;game.sync_view()
	var rest:Vector3=smg.get_meta("magazine_rest",Vector3(0,-.22,-.37))
	check(smg.get_meta("detachable",smg.has_node("MagazineLip")),"smg magazine is a separate detachable part")
	check(smg.get_node("Magazine").position.distance_to(rest)>.2,"magazine visibly pulled out of the well")
	weapon.reload=84;game.sync_view()
	var pose:Transform3D=gun.transform
	game.run.state="paused";game.sync_view()
	check(gun.transform.is_equal_approx(pose),"paused reload pose is stable")
	weapon.reload=0;game.sync_view()
	check(smg.get_node("Magazine").position.is_equal_approx(rest),"magazine returns without accumulated transform")
	weapon.reload=84;game.sync_view();game.run.Combat.drop_weapon(game.run,0);game.sync_view()
	check(gun.visible and smg.get_node("Magazine").position.is_equal_approx(rest),"dropped weapon is tossed with reload pose cleared")
	game.run.elapsed+=game.combat_view.TOSS_TIME+0.1;game.sync_view()
	check(not gun.visible,"weapon hidden once it lands")
	var camera_before:Transform3D=game.camera.transform
	game.run.a.position.y-=60;game.run.b.position.y-=60;game.run.update_stream();game.sync_view()
	check(game.camera.transform==camera_before and game.road.position==Vector3.ZERO,"backward actors do not move map or camera")
	game.queue_free();await process_frame
	print("JOURNEY POLISH checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
