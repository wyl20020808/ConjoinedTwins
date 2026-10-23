extends SceneTree

func _initialize() -> void:call_deferred("verify")

func verify() -> void:
	var error:=change_scene_to_file("res://scenes/journey_boot.tscn")
	assert(error==OK)
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var game=current_scene.get("game") if is_instance_valid(current_scene) else null
		if is_instance_valid(game) and game.scene_prepared:
			var result:={"startup":"pass","scene":game.scene_file_path,"driver":RenderingServer.get_current_rendering_driver_name(),"method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"max_fps":Engine.max_fps,"state":game.run.state,"physics_hz":Engine.physics_ticks_per_second}
			FileAccess.open(OS.get_environment("DENSE_FRAME_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
			print("HIGH FPS BOOT ",JSON.stringify(result));quit();return
	printerr("启动超时");quit(1)
