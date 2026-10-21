extends RefCounted
# 主界面、章节载入画面与网页启动页共用的章节资料。
# 只放文字和封面路径，不引用玩法脚本：主界面要在章节数据下载前就能显示。
# 名称与区域须与 journey_run.gd 的 CHAPTERS 一致，由 tests/chapter_menu.gd 核对。

const TRAINING := 3
# 主界面背景与网页启动页共用的主页图。
const HOME_COVER := "res://assets/ui/covers/home.jpg"
const ENTRIES := [
	{"number":"第一章", "name":"穿林入村", "cover":"res://assets/ui/covers/chapter_0.jpg",
		"zones":["原野石板路","森林深处","坍塌林道","林缘与村口","村庄街道","村口防御"],
		"summary":"从原野石板路出发，穿过幽深森林与坍塌林道，在村口与村民一起击退来袭的怪物。",
		"length":"约 2.4 公里 · 6 个区域", "accent":Color("8fd18a"),
		"tips":["倒树倒下前地面会出现标记，两人一起离开标记区。","绳子拉满会把队友拽过来，分开绕柱前先商量走哪一侧。","野猪会沿直线冲锋，看准方向后同侧避开。","村口防御段怪物很多，先捡枪再进入专区。"]},
	{"number":"第二章", "name":"水车河道", "cover":"res://assets/ui/covers/chapter_1.jpg",
		"zones":["村外田野","农田小路","河岸渡口","水车栈道","旧桥防线","河谷出口"],
		"summary":"沿田埂与河岸前行，避开横扫的水车摆臂，守住旧桥防线，从河谷出口离开。",
		"length":"约 1.9 公里 · 6 个区域", "accent":Color("7cc4e8"),
		"tips":["水车摆臂有固定节奏，等它扫过再从侧面通过。","推车横穿路面时先观察轨迹，再找空当前进。","双人踏板要两个人分别站稳才会开门。","村民会向落点投掷石块，看到预警及时离开。"]},
	{"number":"第三章", "name":"矿道归航", "cover":"res://assets/ui/covers/chapter_2.jpg",
		"zones":["河谷山路","矿场入口","矿道深处","遗迹回廊","设施防线","归航出口"],
		"summary":"夜入矿场与遗迹回廊，借着灯火穿过设施防线，踏上最后的归航之路。",
		"length":"约 1.9 公里 · 6 个区域", "accent":Color("b39ddb"),
		"tips":["夜里视野变短，留意前方的断路与缺口。","矿道石卫预警后会攻击固定落点，移动即可躲开。","遗迹回廊的断路较多，跳之前确认落点有地面。","供能接力门需要一人接线、一人站板。"]},
	{"number":"训练", "name":"战斗训练", "cover":"res://assets/ui/covers/chapter_3.jpg",
		"zones":["拾取与射击","单只冲锋兽","换弹与补给","交替应敌","护盾与医疗","共同抵达"],
		"summary":"持枪步行约 90 秒，熟悉拾取、射击、换弹、换枪与补给，再出发也不迟。",
		"length":"约 90 秒 · 6 个小节", "accent":Color("e8bd7d"),
		"tips":["靠近枪械自动拾取，最多带两把。","按住射击会自动锁定前方的敌人。","R 换弹，Q 换枪，G 丢枪。","弹药和医疗包靠近即可拾取，满时会保留在地上。"]},
]

static func entry(chapter: int) -> Dictionary:
	return ENTRIES[clampi(chapter, 0, ENTRIES.size() - 1)]

static func title(chapter: int) -> String:
	var data := entry(chapter)
	return "%s · %s" % [data.number, data.name]

static func home() -> Texture2D:
	return load(HOME_COVER) if ResourceLoader.exists(HOME_COVER) else null

static func cover(chapter: int) -> Texture2D:
	var path: String = entry(chapter).cover
	return load(path) if ResourceLoader.exists(path) else null
