extends RefCounted
# 玩家本机设置：音量、画质预设、帧率上限、伤害数字与画面冲击。
# 保存在 user://settings.cfg（网页由引擎写入浏览器本地存储），只影响表现，不参与模拟与联机同步。

const PATH := "user://settings.cfg"
const QUALITIES := ["low","medium","high"]
const QUALITY_NAMES := {"low":"低","medium":"中","high":"高"}
const VOLUMES := ["master","music","sfx","ambience"]
const VOLUME_NAMES := {"master":"总音量","music":"音乐","sfx":"音效","ambience":"环境"}
# 桌面 Forward+：高档即原有画质；中档关体积雾并降低内部渲染高度；低档再关阴影与 SSAO。
const DESKTOP := {
	"low":{"shadows":false,"fog":false,"ssao":false,"height":540.0,"msaa":false},
	"medium":{"shadows":true,"fog":false,"ssao":true,"height":680.0,"msaa":true},
	"high":{"shadows":true,"fog":true,"ssao":true,"height":800.0,"msaa":true},
}
# 网页 Compatibility 没有体积雾与 SSAO，动态阴影一直关闭，只调 3D 内部分辨率；中档即原有 960×540。
const WEB_RESOLUTION := {"low":Vector2(768,432),"medium":Vector2(960,540),"high":Vector2(1280,720)}
# 移动端原生包：中档即原有 0.75 渲染缩放。
const MOBILE_SCALE := {"low":0.6,"medium":0.75,"high":0.9}

var platform := "desktop"
var volumes := {"master":1.0,"music":1.0,"sfx":1.0,"ambience":1.0}
var quality := "high"
var fps_cap := 0
var damage_numbers := true
var impact_effects := true

func _init(target_platform: String = "desktop") -> void:
	platform = target_platform
	quality = default_quality()
	fps_cap = 60 if platform == "web" else 0

func default_quality() -> String:
	return "high" if platform == "desktop" else "medium"

# 网页由浏览器按显示器刷新驱动，只提供 30 / 60；0 表示不限（仍受垂直同步约束）。
func fps_options() -> Array:
	return [30,60] if platform == "web" else [30,60,120,0]

static func fps_name(cap: int) -> String:
	return "不限" if cap <= 0 else str(cap)

func read_file(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	for key in VOLUMES:
		volumes[key] = clampf(float(config.get_value("audio", key, volumes[key])), 0.0, 1.0)
	var saved_quality := str(config.get_value("video", "quality", quality))
	if saved_quality in QUALITIES: quality = saved_quality
	var saved_cap := int(config.get_value("video", "fps_cap", fps_cap))
	if saved_cap in fps_options(): fps_cap = saved_cap
	damage_numbers = bool(config.get_value("hud", "damage_numbers", damage_numbers))
	# 沿用旧版暂停菜单写入的键，保持兼容。
	impact_effects = bool(config.get_value("feel", "impact_effects", impact_effects))

func write_file(path: String = PATH) -> void:
	var config := ConfigFile.new()
	# 先读入原文件，保留其他模块写入的键。
	config.load(path)
	for key in VOLUMES: config.set_value("audio", key, volumes[key])
	config.set_value("video", "quality", quality)
	config.set_value("video", "fps_cap", fps_cap)
	config.set_value("hud", "damage_numbers", damage_numbers)
	config.set_value("feel", "impact_effects", impact_effects)
	config.save(path)
