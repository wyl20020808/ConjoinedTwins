extends SceneTree

var failures: Array[String]=[]
var checks := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);printerr("FAIL ",message)
func _initialize() -> void: call_deferred("validate")
func prepared(game) -> bool:
	for frame in range(10000):
		if game.prepare_journey_frame(): return true
		await process_frame
	return false
func validate() -> void:
	var sound=load("res://scripts/sfx.gd").new()
	root.add_child(sound)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loading_baseline.json"))
	for key in expected.audio_hashes:
		check(sound.streams[key].data.hex_encode().sha256_text()==expected.audio_hashes[key],"original PCM unchanged: "+key)
	check(sound.streams.has("gunshot") and not sound.streams.gunshot.data.is_empty(),"baked gunshot is loaded at startup")
	sound.queue_free()
	var boot=load("res://scenes/journey_boot.tscn").instantiate()
	root.add_child(boot)
	for frame in range(10000):
		await process_frame
		if boot.game!=null and boot.game.scene_prepared: break
	check(boot.game!=null and boot.game.scene_prepared,"default asynchronous boot prepares battle scene")
	if boot.game==null: quit(1);return
	var game=boot.game
	game.set_physics_process(false)
	check(game.run.elapsed==0 and game.run.progress()==0,"boot preparation never advances gameplay")
	game.training_button.pressed.emit()
	check(game.run.combat_trial,"training button selects battle map after asynchronous boot")
	check(await prepared(game),"training assets prepare incrementally")
	game.sync_view()
	check(game.chunk_chapter(0).length==12240 and game.chunk_chapter(0).zones==game.run.TRIAL_ZONES,"background plan receives training length and signs")
	check(game.built_training and game.gate_views.is_empty(),"training switch removes original chapter gate views")
	var chunk_id: int=game.world_chunks[0].get_instance_id()
	game.run.retry();game.reset_journey_views()
	check(await prepared(game),"training retry prepares without advancing")
	game.sync_view()
	check(game.world_chunks[0].get_instance_id()==chunk_id,"same-map retry retains prepared environment")
	check(game.run.elapsed==0,"retry preparation freezes combat timers")
	game.run.combat_trial=false;game.run.retry();game.reset_journey_views()
	check(await prepared(game),"switch back to campaign prepares real chapter")
	game.sync_view()
	check(not game.built_training and game.world_chunks[0].get_instance_id()!=chunk_id,"different map replaces training chunks")
	boot.queue_free();await process_frame
	await create_timer(0.15).timeout
	print("RELEASE INTEGRATION CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
