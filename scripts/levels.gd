extends RefCounted

static func create(index: int) -> Dictionary:
	var common := {
		"spawn": [Vector2(140, 390), Vector2(210, 390)],
		"walls": [Rect2(0, 120, 1100, 20), Rect2(0, 660, 1100, 40), Rect2(0, 120, 40, 580), Rect2(1060, 120, 40, 580)],
		"plates": [], "hazards": [], "receiver": Vector2.ZERO,
		"gates": [], "checkpoint": Rect2(),
		"exit": Rect2(930, 290, 115, 230)
	}
	match index:
		0:
			common["title"] = "01 · 保持连接"
			common["hint"] = "绕墙上侧 → 右键队友到上板 → 自己站下板 → E 召回 → 两人进入出口"
			common["walls"].append(Rect2(360, 320, 44, 160))
			common["plates"] = [Vector2(690, 300), Vector2(690, 480)]
			common["gates"] = [{"rect": Rect2(850, 140, 22, 520), "kind": "plates", "open": false}]
		1:
			common["title"] = "02 · 共同通过危险区"
			common["hint"] = "激光虚线=关闭，三角=预警，斜纹=危险；安全岛激活检查点，观察时机再同行"
			common["hazards"] = [{"rect": Rect2(360, 140, 48, 520), "offset": 0.0}, {"rect": Rect2(650, 140, 48, 520), "offset": 2.4}]
			common["checkpoint"] = Rect2(465, 260, 130, 280)
		2:
			common["title"] = "03 · 以连接传能"
			common["hint"] = "队友停在 (650,285)，自己到 (650,495)；连线张紧穿过接收器 0.8 秒，再合作双板"
			common["receiver"] = Vector2(650, 390)
			common["plates"] = [Vector2(890, 300), Vector2(890, 480)]
			common["gates"] = [{"rect": Rect2(790, 140, 20, 520), "kind": "receiver", "open": false}, {"rect": Rect2(955, 140, 20, 520), "kind": "plates", "open": false}]
			common["exit"] = Rect2(980, 270, 65, 260)
	return common
