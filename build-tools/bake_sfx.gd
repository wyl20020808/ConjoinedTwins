extends SceneTree
# 显式运行此工具才重新合成；PCM 随项目发布，运行时不再逐样本运算。
func _initialize() -> void:
	var sound = load("res://scripts/sfx.gd").new()
	if sound.has_method("synthesize"): sound.synthesize()
	else: sound._ready()
	var journey = load("res://scripts/journey_view.gd")
	for kind in ["wind", "forest", "river"]:
		sound.streams["ambience_"+kind] = sound.render(7.0, func(t): return journey.ambience_wave(t,kind))
	DirAccess.make_dir_recursive_absolute("res://assets/audio")
	for key in sound.streams:
		var error: int = sound.streams[key].save_to_wav("res://assets/audio/%s.wav" % key)
		if error != OK:
			push_error("音效生成失败：%s (%d)" % [key,error])
			quit(1)
			return
		# Godot 默认的 QOA 有损压缩会改变波形；保持原程序 PCM 完全一致。
		var path := "res://assets/audio/%s.wav.import" % key
		var options := ConfigFile.new()
		options.load(path)
		options.set_value("remap", "importer", "wav")
		options.set_value("remap", "type", "AudioStreamWAV")
		options.set_value("params", "compress/mode", 0)
		options.save(path)
	sound.free()
	quit()
