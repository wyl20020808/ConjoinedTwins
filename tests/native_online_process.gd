extends SceneTree
# 由 check_native_online.py 启动：每个进程只拥有一个生产客户端或一个中继。
const Relay = preload("res://scripts/net_relay.gd")
class FaultRelay extends Relay:
	var lose_input := false
	func _on_packet(key: Vector2i, bytes: PackedByteArray) -> void:
		if lose_input and roles.get(key, -1) == 1 and not bytes.is_empty():
			if bytes[0] == INPUT_SEQ_TAG: return
			if bytes[0] == TYPE_ARRAY:
				var message = bytes_to_var(bytes)
				if message is Array and message.size() >= 2 and message[0] == "cmd" and message[1] == "combat": return
		super._on_packet(key, bytes)
var directory := OS.get_environment("ONLINE_TEST_DIRECTORY")
var endpoint := OS.get_environment("ONLINE_TEST_ENDPOINT")
var port := int(OS.get_environment("ONLINE_TEST_PORT"))
var relay
var game
var phase := ""
var hashes := {}
var targets := {}
var contiguous := true
var last_frame := -1
var started := false
var snapshot_msec := 0
func _initialize() -> void: call_deferred("validate")
func record(index: int) -> void:
	contiguous = contiguous and index == last_frame + 1
	last_frame = index
	# 与生产上报同频，避免测试逐帧序列化整局状态干扰追帧预算。
	if index % 60 == 0: hashes[str(index)] = game.run.sync_hash()
func snapshot() -> void:
	var data: Dictionary
	if endpoint == "relay":
		data = {"phase": phase, "frame": relay.frame, "acked": relay.acked,
			"inputs": relay.inputs, "stale": relay.input_stale, "desync": relay.desynced}
	else:
		var target: int = game.net.playout_target()
		targets[str(target)] = int(targets.get(str(target), 0)) + 1
		data = {"phase": phase, "role": game.net.role, "applied": game.net.next_frame,
			"queue": game.net.frames.size(), "target": target, "target_samples": targets,
			"stalls": game.net.stalls, "held_ticks": game.net.held_ticks, "doubled_ticks": game.net.doubled_ticks,
			"desync": game.net.desynced, "state": game.run.state,
			"fire": game.run.combat.get("fire", [false, false]),
			"bytes_sent": game.net.bytes_sent, "contiguous": contiguous, "hashes": hashes}
	var file := FileAccess.open(directory.path_join(endpoint + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data)); file.close()
func validate() -> void:
	if endpoint == "relay":
		seed(20261022)
		relay = FaultRelay.new(); relay.port = port; relay.ws_port = 0; root.add_child(relay)
	else:
		game = load("res://scenes/journey.tscn").instantiate(); root.add_child(game)
		game.play_mode = "online"
		game.input_override = {"a": Vector2.ZERO, "b": Vector2.ZERO, "ja": false, "jb": false, "fire": false}
		game.online_frame_applied.connect(record)
		game.net.connect_to("127.0.0.1:%d" % port)
		Engine.max_fps = 60
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var control = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("control.json")))
		if control is Dictionary and control.phase != phase:
			phase = control.phase
			if endpoint == "relay":
				relay.lose_input = phase == "loss"
				if phase == "desync":
					relay.check_hash(0, relay.frame, 111)
					relay.check_hash(1, relay.frame, 222)
			elif endpoint == "client1":
				game.set_physics_process(phase != "stall")
				var held: bool = phase in ["hold", "loss", "recover"]
				game.input_override.a = Vector2(1, 0) if held else Vector2.ZERO
				game.input_override.ja = held
				game.input_override.fire = held
			if phase == "shutdown": break
		if endpoint != "relay" and game.net.in_match and not started:
			started = true
			if game.net.role == 0: game.command("primary")
		if Time.get_ticks_msec() >= snapshot_msec:
			snapshot_msec = Time.get_ticks_msec() + 50
			snapshot()
		await process_frame
	var timed_out := phase != "shutdown"
	snapshot()
	if endpoint == "relay": relay.queue_free()
	else: game.net.disconnect_from(); game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	if timed_out: print("FAIL process deadline exceeded")
	quit(1 if timed_out else 0)
