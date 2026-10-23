extends Node
# 实际 WebAssembly 展示巡检；跳转观察点不作为玩法通关证明。
var game
var records:Array=[]
func _ready()->void:
	game=load("res://scenes/journey.tscn").instantiate();game.incremental_loading=true;add_child(game)
	while not game.scene_prepared:await get_tree().process_frame
	game.set_physics_process(false);game.set_process(false);game.web_test_mode=true
	var spots:=[[0,520,"forest"],[0,800,"deep-forest"],[0,1200,"village-edge"],[0,1400,"village"],[1,240,"farm"],[1,1100,"riverside-village"]]
	for lap in range(2):
		for spot in spots:
			game.run.level_index=spot[0];game.run.retry();game.reset_journey_views();game.run.state="running"
			game.run.a.position=Vector2(-42,spot[1]*20);game.run.b.position=Vector2(42,spot[1]*20)
			game.run.distance=spot[1]*20;game.run.elapsed=15.0;game.run.rope.reset(game.run.a.position,game.run.b.position)
			for gate in game.run.charge_gates:
				gate.open=gate.receiver.y<game.run.distance-180;gate.opened_at=0.0 if gate.open else -1.0
			game.run.select_charge_gate()
			while not game.prepare_journey_frame():await get_tree().process_frame
			var before:int=game.run.sync_hash();game.sync_view();assert(before==game.run.sync_hash())
			await get_tree().create_timer(.4).timeout
			var item:={"name":spot[2],"lap":lap,"nodes":get_tree().get_node_count(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"cached_assets":game.chunk_assets.resources.size(),"mobile":game.landscape.mobile,"scale":get_viewport().scaling_3d_scale}
			records.append(item)
			JavaScriptBridge.eval("window.__atmosphereShot="+JSON.stringify(item),true)
			await get_tree().create_timer(1.1).timeout
	JavaScriptBridge.eval("window.__atmosphereDone="+JSON.stringify(records),true)
