extends "res://scripts/road_run.gd"
# 在桌面 headless 下模拟 Web 的真实平台能力；其余全部执行生产实现。
func supports_background_generation() -> bool:
	return false
