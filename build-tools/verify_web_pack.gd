extends SceneTree
# 网页包资源完整性巡检：在导出的 index.pck 上运行，确认排除列表没有删掉运行时会加载的资源。
# 用法（脚本在 PCK 之外，用绝对路径传入）：
#   Godot --headless --main-pack builds/web/index.pck -s <工程>/build-tools/verify_web_pack.gd
# 1. 加载生产脚本常量里的全部 res:// 路径和按名字拼接的模型表（怪物、机关、村庄、地标、树木）；
# 2. 按生产入口 scenes/journey.tscn 逐章、多种子把观察位置推过全程，让分块流式加载真实走一遍。
# 边界：桌面无头运行，不走 OS.has_feature("web") 分支，不验证 GPU 渲染与浏览器内存。
const SOURCES:=["res://scripts/journey_view.gd","res://scripts/road_demo.gd","res://scripts/journey_enemy_view.gd","res://scripts/journey_landscape.gd","res://scripts/road_asset_queue.gd"]
const SEEDS:=[20261012,7,99173,424242,31337,5150]
var missing:=0

func _initialize()->void:call_deferred("run")

func check_path(path:String)->void:
	if not ResourceLoader.exists(path):
		missing+=1;printerr("MISSING ",path);return
	var resource:=load(path)
	if resource==null:missing+=1;printerr("BROKEN ",path)

func collect(value,paths:Dictionary)->void:
	if value is String and value.begins_with("res://") and value.get_extension()!="":paths[value]=true
	elif value is Array:for item in value:collect(item,paths)
	elif value is Dictionary:for item in value.values():collect(item,paths)

func run()->void:
	var paths:={}
	for source in SOURCES:
		collect((load(source) as Script).get_script_constant_map().values(),paths)
	var Landscape=load("res://scripts/journey_landscape.gd")
	for kind in Landscape.TRIPO_HOUSES+Landscape.SURFACE_KINDS.slice(3)+Landscape.VILLAGERS:
		var path:="res://assets/landscape/%s.glb"%kind
		var rigged:String=Landscape.rigged_villager(path)
		paths[rigged if not rigged.is_empty() else path]=true
	for kind in ["tripo_road_edge","tripo_stump","tripo_produce_stall","tripo_bread_oven","tripo_stone_fountain","tripo_supplies","tripo_covered_well","tripo_arch","tripo_village_windmill","landmark_watchtower","landmark_headframe","landmark_shrine"]:
		paths["res://assets/landscape/%s.glb"%kind]=true
	for kind in ["natural_oak_7","natural_oak_17","natural_birch"]:
		paths["res://assets/landscape/%s.glb"%kind]=true;paths["res://assets/landscape/%s_lod.glb"%kind]=true
	for path in load("res://scripts/road_asset_queue.gd").startup_paths():paths[path]=true
	for path in paths:check_path(path)
	print("VERIFY_WEB_PACK constants=",paths.size()," missing=",missing)
	var game=load("res://scenes/journey.tscn").instantiate();root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.web_test_mode=true;game.incremental_loading=true
	for chapter in range(3):
		for seed in SEEDS:
			game.run.level_index=chapter;game.run.random_seed=false;game.run.seed_value=seed;game.run.retry();game.run.state="paused"
			var finish:float=game.run.finish_distance()
			var location:=0.0
			while location<=finish+400:
				game.run.distance=location;game.run.a.position.y=location;game.run.b.position.y=location
				var waits:=0
				while waits<3000:
					var ready:bool=game.prepare_journey_frame()
					if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty():break
					waits+=1;await process_frame
				if waits>=3000:missing+=1;printerr("STUCK chapter=",chapter," seed=",seed," at=",location)
				game.sync_view();await process_frame
				location+=500.0
			print("VERIFY_WEB_PACK sweep chapter=",chapter," seed=",seed," finish=",finish)
	for player in game.sfx.players:player.stop()
	game.queue_free()
	for n in range(4):await process_frame
	print("VERIFY_WEB_PACK missing=",missing)
	quit(0 if missing==0 else 1)
