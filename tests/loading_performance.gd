extends SceneTree
# 同一生产入口、固定布局和种子；只报告 headless CPU，不代表 GPU 帧时。
const Run = preload("res://scripts/road_run.gd")
const NoThreads = preload("res://tests/fixtures/no_threads_run.gd")
const Sound = preload("res://scripts/sfx.gd")
var report := {}

func _initialize() -> void:
	call_deferred("measure")

func summary(values: Array) -> Dictionary:
	values.sort()
	return {"median_usec": values[values.size() / 2], "p95_usec": values[int((values.size() - 1) * 0.95)], "max_usec": values[-1], "samples": values.size()}

func measure() -> void:
	report.engine = Engine.get_version_info().string
	report.cpu = OS.get_processor_name()
	report.mode = "headless CPU；进程内资源缓存；非磁盘冷启动和 GPU 帧时"
	var sounds: Array = []
	for sample in range(5):
		var sound = Sound.new()
		var started := Time.get_ticks_usec()
		root.add_child(sound)
		sounds.append(Time.get_ticks_usec() - started)
		if sample == 0:
			report.audio_hashes = {}
			for key in sound.streams: report.audio_hashes[key] = sound.streams[key].data.hex_encode().sha256_text()
		sound.free()
	report.audio_ready = summary(sounds)
	var started := Time.get_ticks_usec()
	var game = load("res://scenes/road_demo.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	if game.has_method("finish_scene_preparation"):
		while not game.scene_prepared: game.finish_scene_preparation()
	report.scene_ready_usec = Time.get_ticks_usec() - started
	game.run.dispose()
	game.run = Run.new(false)
	game.run.retry()
	game.run.install_block({"hazards": [{"kind":"road_gap", "rect":Rect2(-320,0,298,440)}, {"kind":"road_gap", "rect":Rect2(22,0,298,440)}], "rewards":[]}, 0, "performance-gap")
	game.sync_view()
	var views: Array = []
	var unchanged_meshes := 0
	var mesh_ids := {}
	for chunk in game.scenery:
		if chunk.has_meta("road_slot"): mesh_ids[chunk.get_instance_id()] = chunk.get_node("SupportSurface").mesh.get_instance_id()
	for frame in range(360):
		game.run.distance += 4.0
		started = Time.get_ticks_usec()
		game.sync_view()
		views.append(Time.get_ticks_usec() - started)
	for chunk in game.scenery:
		if chunk.has_meta("road_slot") and mesh_ids[chunk.get_instance_id()] == chunk.get_node("SupportSurface").mesh.get_instance_id(): unchanged_meshes += 1
	report.moving_gap_view = summary(views)
	report.unchanged_support_meshes = unchanged_meshes
	report.routes = {}
	for route in ["steam", "narrow", "charge_cargo", "slope", "lift"]:
		var picker = Run.Templates.new()
		picker.reset(4242)
		var candidates: Array = []
		for index in range(3): candidates.append(picker.candidate_of(route, 0))
		var request := {"epoch":1,"number":0,"difficulty":"普通","level":0,"candidates":candidates}
		var result: Dictionary = Run.verification_worker(request, Run.Templates.Cancellation.new())
		report.routes[route] = var_to_str(result.block).sha256_text()
	var startups := {}
	for backend in ["cooperative", "native"]:
		game.run.dispose()
		game.run = NoThreads.new(true,true) if backend == "cooperative" else Run.new(true,true)
		game.run.charge_tutorial = true
		game.run.seed_value = 4242
		game.run.retry()
		var before: int = game.run.sync_hash()
		var calls: Array = []
		var wall := Time.get_ticks_usec()
		var ready := false
		for poll in range(10000):
			started = Time.get_ticks_usec()
			ready = game.prepare_game_frame()
			calls.append(Time.get_ticks_usec() - started)
			if ready: break
			await process_frame
		var cpu_total := 0
		for value in calls: cpu_total += value
		startups[backend] = {"wall_usec":Time.get_ticks_usec()-wall,"prepare_cpu_usec":cpu_total,"calls":summary(calls),"ready":ready,"state_unchanged":before==game.run.sync_hash(),"blocks":{}}
		for key in game.run.async_preload_tasks:
			var task = game.run.async_preload_tasks[key]
			startups[backend].blocks[str(task.job.number)] = var_to_str(task.result.block).sha256_text()
	report.startups = startups
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loading_baseline.json"))
	var deterministic: bool=report.audio_hashes==expected.audio_hashes and report.routes==expected.routes and startups.cooperative.blocks==expected.startup_blocks and startups.native.blocks==expected.startup_blocks
	report.deterministic=deterministic
	game.free()
	var path := OS.get_environment("PERFORMANCE_REPORT")
	if path.is_empty(): path = "res://build-tools/cache/loading-performance/latest.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("PERFORMANCE_REPORT ", path, " ", JSON.stringify(report))
	quit(0 if deterministic and startups.cooperative.ready and startups.native.ready and startups.cooperative.state_unchanged and startups.native.state_unchanged else 1)
