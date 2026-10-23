extends SceneTree
const Boss = preload("res://scripts/journey_boss.gd")
const Finale = preload("res://scripts/journey_boss_finale.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var game = load("res://scenes/journey.tscn").instantiate()
	game.start_chapter = 0
	root.add_child(game)
	while not game.scene_prepared: await process_frame
	game.set_physics_process(false); game.set_process(false)
	game.frame_delta = 1.0/60
	var run = game.run
	for sound in ["colossus_charge", "colossus_attack", "colossus_hurt"]:
		var previous: AudioStream = game.sfx.pick(sound)
		var different := true
		for n in range(20):
			var current: AudioStream = game.sfx.pick(sound)
			different = different and current != previous
			previous = current
		check(different, sound+" 不连续重复同一音频")
	run.retry(); run.state = "running"
	for gate in run.charge_gates: gate.open = true; gate.opened_at = -10.0
	run.select_charge_gate()
	var event: Dictionary = Boss.boss(run)
	run.a.position = Vector2(-42, event.arena+1200)
	run.b.position = Vector2(42, event.arena+1200)
	run.distance = event.arena+1200
	run.rope.reset(run.a.position, run.b.position)
	event.phase = "active"; event.trigger = 0.0; event.state = "spikes"
	run.elapsed = 30.0; event.state_at = 30.0
	game.sync_view()
	var view: Node3D = game.event_views[event.id]
	for skill in ["spikes", "sweep", "seeds", "summon", "root", "roar"]:
		event.state = skill; event.skill_seq += 1; event.state_at = run.elapsed
		game.sync_view()
		var key: String = "%s:%d:%d"%[skill,event.skill_seq,event.stage]
		check(view.get_meta("fx_combat_voice", "") == key, skill+" 蓄力音效")
		run.elapsed += 1.6
		game.sync_view()
		check(view.get_meta("fx_combat_release", "") == key, skill+" 出手音效")
		await process_frame
	event.hp = 1; run.Combat.damage(run,event,10000)
	var start: float = run.elapsed
	var positions := [run.a.position,run.b.position]
	var hp: Array = run.combat.health.duplicate()
	game.sync_view()
	check(Finale.active(run), "死亡镜头开始")
	check(view.has_meta("final_roar"), "死亡咆哮只触发一次")
	for i in range(roundi(Finale.LENGTH*120)):
		run.step(run.FIXED_STEP,Vector2.ONE,Vector2.ONE,true,true)
		if i%4 == 0:
			game.sync_view()
			await process_frame
		if i in [180, 360, 540, 990] and "--capture-finale" in OS.get_cmdline_user_args():
			game.update_journey_camera()
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("D:/ConjoinedTwins-task-temp/boss-finale-evidence/frame_%d.png"%i)
		if i == 360:
			check(not view.get_node("Body/Colossus").visible, "爆裂后本体消失")
			check(view.get_node("DeathFragments").visible and view.get_node("DeathFragments").get_meta("shards").size() == 28, "28 块本体切割碎片沿裂缝分开")
		if i == 990:
			check(view.get_node("Cinema/Name").text == "恭喜通关" and view.get_node("Cinema/Name").modulate.a > 0.0, "爆裂后出现通关标题")
			var frozen: float = run.elapsed
			run.state = "paused"; run.step(0.2); game.sync_view()
			check(run.elapsed == frozen, "暂停冻结死亡演出")
			run.state = "running"
	check(run.a.position == positions[0] and run.b.position == positions[1], "演出期间锁定两人位置")
	check(run.combat.health == hp, "演出期间不受伤害")
	check(run.elapsed-start >= Finale.LENGTH-0.01, "死亡时间轴完整推进")
	game.sync_view()
	check(not view.get_node("DeathFragments").visible, "碎片收回固定池")
	run.step(run.FIXED_STEP)
	check(not Finale.active(run), "结束后交还控制")
	event.hp = event.max_hp; event.phase = "dormant"
	game.sync_view()
	check(not view.has_meta("final_roar") and view.get_node("Cinema/Name").text == Boss.NAME, "重试恢复标题与一次性标记")
	game.queue_free(); await process_frame
	game = null; run = null
	for n in range(8): await process_frame
	print("BOSS_FINALE failures=",failures)
	quit(1 if failures else 0)
