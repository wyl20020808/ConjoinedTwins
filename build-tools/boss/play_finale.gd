extends "res://build-tools/boss/play_intro.gd"
# 专用演出预览：复用生产入场与战斗，展示一轮技能后触发真实伤害入口。
# 仅此工具自动击败 Boss，生产战斗没有自动击杀。
func play() -> void:
	await super.play()
	var event: Dictionary = Boss.boss(game.run)
	while is_instance_valid(game) and (event.phase == "dormant" or event.phase == "intro"):
		await process_frame
	var until: float = game.run.elapsed+12.0
	while is_instance_valid(game) and game.run.elapsed < until:
		game.run.invulnerable_until = game.run.elapsed+1.0
		await process_frame
	game.run.Combat.damage(game.run,event,event.max_hp*8)
