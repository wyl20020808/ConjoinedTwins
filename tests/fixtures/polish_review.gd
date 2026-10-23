extends Node
# 独立无窗口渲染巡检；观察点跳转仅用于画面检查，不作为合法通关证据。
var game
func _ready()->void:
	game=load("res://scenes/journey.tscn").instantiate();game.incremental_loading=true;add_child(game)
	while not game.scene_prepared:await get_tree().process_frame
	game.set_physics_process(false);game.set_process(false);game.web_test_mode=true
	for shot in [[0,70,"ridge"],[0,520,"forest"],[0,1200,"village"],[1,420,"river"],[2,520,"mine"]]:
		game.run.level_index=shot[0];game.run.retry();game.reset_journey_views();game.run.state="running"
		game.run.a.position=Vector2(-42,shot[1]*20);game.run.b.position=Vector2(42,shot[1]*20)
		game.run.distance=shot[1]*20;game.run.elapsed=10.0
		game.run.rope.reset(game.run.a.position,game.run.b.position)
		for gate in game.run.charge_gates:
			gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0.0 if gate.open else -1.0
		game.run.select_charge_gate()
		while not game.prepare_journey_frame():await get_tree().process_frame
		game.sync_view();await capture(shot[2])
	game.run.level_index=0;game.run.retry();game.reset_journey_views();game.run.state="running"
	while not game.prepare_journey_frame():await get_tree().process_frame
	game.run.combat.weapons[0]=game.run.Combat.gun();game.run.combat.weapons[0].ammo=5
	for phase in [[168,"reload-start"],[84,"reload-out"],[32,"reload-in"],[0,"reload-ready"]]:
		game.run.combat.weapons[0].reload=phase[0]
		game.sync_view();await capture(phase[1])
	JavaScriptBridge.eval("window.__polishDone=true",true)
func capture(name:String)->void:
	await get_tree().create_timer(.3).timeout
	JavaScriptBridge.eval("window.__polishShot="+JSON.stringify({"name":name,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}),true)
	await get_tree().create_timer(1.2).timeout
