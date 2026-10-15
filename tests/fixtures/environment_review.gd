extends Node
# 仅展示层巡检，不计为合法通关。通过独立测试工程导出，不进入生产入口。
var game
var records:Array=[]
func _ready()->void:
	game=load("res://scenes/journey.tscn").instantiate()
	game.incremental_loading=true
	add_child(game)
	while not game.scene_prepared:await get_tree().process_frame
	game.set_physics_process(false);game.web_test_mode=true
	game.run.state="running"
	game.set_process_unhandled_key_input(false)
	var index:=0
	for lap in range(2):
		for meters in range(0,1921,40):
			game.run.a.position=Vector2(-42,meters*20);game.run.b.position=Vector2(42,meters*20)
			game.run.distance=meters*20;game.run.elapsed=meters/8.0
			while not game.prepare_journey_frame():await get_tree().process_frame
			game.sync_view()
			await get_tree().create_timer(.35).timeout
			var r:={"index":index,"lap":lap,"meters":meters,"nodes":get_tree().get_node_count(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"memory":Performance.get_monitor(Performance.MEMORY_STATIC),"video":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"fps":Engine.get_frames_per_second(),"mobile":game.landscape.mobile,"cached_assets":game.chunk_assets.resources.size(),"chunks":game.world_chunks.size(),"jobs":game.chunk_jobs.size()}
			records.append(r)
			JavaScriptBridge.eval("window.__ctReview="+JSON.stringify(r),true)
			if lap==0 and meters in [0,240,360,520,800,1080,1200,1400,1720]:await get_tree().create_timer(1.4).timeout
			index+=1
		# 重新游玩清理展示缓存，第二轮应达到内存平台。
		game.run.retry();game.reset_journey_views()
	JavaScriptBridge.eval("window.__ctReviewDone="+JSON.stringify(records),true)
