extends SceneTree
# 章节资源用量巡检：记录每章实际向 ResourceLoader 请求过的资源，供网页按章节拆包。
# 用法（每章一个独立进程，避免上一章的缓存混入）：
#   Godot --headless --path . -s res://build-tools/chapter_asset_usage.gd -- --chapter=0 --seeds=1,2,3 --out=<json>
#   --chapter=training 表示战斗训练。
# 原理：在加载器链最前面挂一个只记录、不认领的格式加载器，ResourceLoader 每次解析路径都会先问它。
# 记录的是重映射后的导入产物路径（.godot/imported/...），由 split_web_pack.py 映射回源资源。
# 边界：桌面无头运行，不走 OS.has_feature("web") 分支；网页专用路径由拆包脚本另行并入基础包。

class Recorder extends ResourceFormatLoader:
	var seen:={}
	var lock:=Mutex.new()
	func _recognize_path(path:String,_type:StringName)->bool:
		lock.lock();seen[path]=true;lock.unlock()
		return false
	func _get_recognized_extensions()->PackedStringArray:return PackedStringArray()

var recorder:=Recorder.new()

func _initialize()->void:call_deferred("run")

func option(name:String,fallback:String)->String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s="%name):return arg.get_slice("=",1)
	return fallback

func run()->void:
	ResourceLoader.add_resource_format_loader(recorder,true)
	var chapter:=option("chapter","0")
	var seeds:Array=Array(option("seeds","20261012,7,99173").split(",")).map(func(s):return int(s))
	var out:=option("out","user://chapter_usage.json")
	var training:=chapter=="training"
	var packed:PackedScene=load("res://scenes/journey.tscn")
	var game=packed.instantiate()
	game.incremental_loading=true
	if training:game.training_entry=true
	else:game.start_chapter=int(chapter)
	root.add_child(game)
	while not game.scene_prepared:await process_frame
	game.set_physics_process(false);game.web_test_mode=true
	var stuck:=0
	for seed in seeds:
		game.run.random_seed=false;game.run.seed_value=seed
		if not training:game.run.level_index=int(chapter)
		game.run.retry();game.run.state="paused"
		var finish:float=game.run.finish_distance()
		var location:=0.0
		while location<=finish+400:
			game.run.distance=location;game.run.a.position.y=location;game.run.b.position.y=location
			var waits:=0
			while waits<3000:
				var ready:bool=game.prepare_journey_frame()
				if ready and game.chunk_jobs.is_empty() and game.chunk_assets.pending.is_empty() and game.chunk_assets.active.is_empty():break
				waits+=1;await process_frame
			if waits>=3000:stuck+=1;printerr("STUCK chapter=",chapter," seed=",seed," at=",location)
			game.sync_view();await process_frame
			location+=400.0
		print("CHAPTER_USAGE sweep chapter=",chapter," seed=",seed," finish=",finish," paths=",recorder.seen.size())
	# 网页分支在每一章开局都会读取的资源（无头运行走不到）：显式加载一次，连同依赖一起记入本章。
	var web_paths:Array=load("res://scripts/road_asset_queue.gd").startup_paths(true)+Array(game.WEB_WARM_PATHS)
	# 章节音乐在出发后才读取，巡检时停在暂停态走不到：按本章实际选用的曲目补记。
	web_paths+=[game.MUSIC_EXPLORE[clampi(game.run.level_index,0,game.MUSIC_EXPLORE.size()-1)],game.MUSIC_COMBAT]
	for path in web_paths:
		if ResourceLoader.exists(path):load(path)
	for player in game.sfx.players:player.stop()
	game.queue_free()
	for n in range(4):await process_frame
	ResourceLoader.remove_resource_format_loader(recorder)
	var paths:=recorder.seen.keys();paths.sort()
	var file:=FileAccess.open(out,FileAccess.WRITE)
	file.store_string(JSON.stringify({"chapter":chapter,"seeds":seeds,"stuck":stuck,"paths":paths},"\t"))
	file.close()
	print("CHAPTER_USAGE done chapter=",chapter," paths=",paths.size()," stuck=",stuck," out=",out)
	quit(0 if stuck==0 else 1)
