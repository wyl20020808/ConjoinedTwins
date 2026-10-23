extends Control
# 顶部章节进度细条：本章进度、六个区域分段与区域名、最近存档位置；进入新区域时区域名淡入淡出。
# 只读模拟状态，不参与判定与联机同步。

const ZONES := 6
const TITLE_TIME := 2.0
const TITLE_FADE_IN := 0.4
const TITLE_FADE_OUT := 0.6
const BAR_HEIGHT := 4.0
const LABEL_HEIGHT := 16.0

var bar_rect := Rect2()
var fraction := 0.0
var checkpoint_fraction := -1.0
var current_zone := 0
var zone_key := ""
var title_left := 0.0
var zone_labels: Array[Label] = []
var zone_title: Label
var zone_caption: Label
var drawn_key := ""
var segments := ZONES

func _ready() -> void:
	name = "ChapterBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(ZONES + 1):
		var zone := text_label(11, Color(0.86, 0.88, 0.82, 0.62))
		zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone.clip_text = true
		zone_labels.append(zone)
	zone_caption = text_label(15, Color("d9cfb8"))
	zone_caption.name = "ZoneCaption"
	zone_title = text_label(34, Color("f7f2e6"))
	zone_title.name = "ZoneTitle"
	for title_label in [zone_caption, zone_title]:
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.visible = false

func text_label(font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_outline_color", Color(0.06, 0.09, 0.07, 0.9))
	result.add_theme_constant_override("outline_size", 4)
	add_child(result)
	return result

static func zone_names(run) -> Array:
	var names:Array=(run.TRIAL_ZONES if run.combat_trial else run.CHAPTERS[run.level_index].zones).duplicate()
	if run.Boss.enabled(run):
		var event:Dictionary=run.Boss.boss(run)
		names.append("???" if event.is_empty() or event.phase=="dormant" else "%s Boss"%run.Boss.title(event))
	return names

func progress_fraction(run, progress:float) -> float:
	var finish:float=maxf(1.0,run.finish_distance())
	if not run.Boss.enabled(run):return clampf(progress/finish,0.0,1.0)
	# 独立终点段给 Boss 名称留足空间，前六段仍按原区域边界显示。
	var arena:float=run.Boss.start_y(run)
	if progress>=arena:return clampf((ZONES+(progress-arena)/(finish-arena))/(ZONES+1),0.0,1.0)
	var zone:int=clampi(int(progress/(finish/ZONES)),0,ZONES-1)
	var start:float=zone*finish/ZONES
	var end:float=minf((zone+1)*finish/ZONES,arena)
	return clampf((zone+(progress-start)/(end-start))/(ZONES+1),0.0,1.0)

static func chapter_caption(run) -> String:
	if run.combat_trial: return "战斗训练"
	return "第 %d 章 · %s" % [run.level_index + 1, run.CHAPTERS[run.level_index].name]

# rect 为细条区域；compact 时只画细条与当前区域名，不画六段文字。
func refresh(run, delta: float, rect: Rect2, shown: bool, compact: bool) -> void:
	visible = shown
	fraction = progress_fraction(run,run.progress())
	checkpoint_fraction = -1.0 if run.checkpoint.is_empty() else progress_fraction(run,float(run.checkpoint.progress))
	current_zone = run.zone_index()
	var names := zone_names(run)
	segments=names.size()
	if segments>ZONES and run.progress()>=run.Boss.start_y(run):current_zone=ZONES
	# 只在实际奔跑时登记区域；回到开始页后重新出发也会显示起始区域名。
	if run.state == "start": zone_key = ""
	elif run.state == "running":
		var key := "%d:%s:%d:%s" % [run.level_index, str(run.combat_trial), current_zone,names[current_zone]]
		if key != zone_key:
			zone_key = key
			title_left = TITLE_TIME
			zone_caption.text = chapter_caption(run)
			zone_title.text = names[current_zone]
	title_left = maxf(0.0, title_left - delta)
	update_title(rect)
	bar_rect = rect
	for i in range(zone_labels.size()):
		var zone := zone_labels[i]
		zone.visible = shown and i<segments and (not compact or i == current_zone)
		if not zone.visible: continue
		var width := rect.size.x / segments
		zone.text = names[i]
		zone.position = Vector2(rect.position.x + width * i, rect.end.y + 2.0)
		zone.size = Vector2(width, LABEL_HEIGHT)
		zone.modulate.a = 1.0 if i == current_zone else 0.55
		if compact:
			zone.position.x = rect.position.x
			zone.size.x = rect.size.x
	# 进度量化到 0.1%，静止时不重复提交绘制。
	var draw_key := "%s|%d|%d|%d" % [str(rect), roundi(fraction * 1000), roundi(checkpoint_fraction * 1000), current_zone]
	if draw_key != drawn_key:
		drawn_key = draw_key
		queue_redraw()

func update_title(rect: Rect2) -> void:
	var shown := visible and title_left > 0.0
	zone_title.visible = shown
	zone_caption.visible = shown
	if not shown: return
	var age := TITLE_TIME - title_left
	var alpha := clampf(age / TITLE_FADE_IN, 0.0, 1.0) * clampf(title_left / TITLE_FADE_OUT, 0.0, 1.0)
	var screen := get_viewport_rect().size
	zone_caption.position = Vector2(0, maxf(rect.end.y + 40.0, screen.y * 0.2))
	zone_caption.size = Vector2(screen.x, 20)
	zone_title.position = zone_caption.position + Vector2(0, 22)
	zone_title.size = Vector2(screen.x, 44)
	zone_caption.modulate.a = alpha
	zone_title.modulate.a = alpha

func title_alpha() -> float:
	return zone_title.modulate.a if zone_title.visible else 0.0

func _draw() -> void:
	if bar_rect.size.x <= 0.0: return
	draw_rect(bar_rect.grow(1.0), Color(0.02, 0.03, 0.03, 0.55))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y)), Color("e8bd7d"))
	var width := bar_rect.size.x / segments
	draw_rect(Rect2(bar_rect.position + Vector2(width * current_zone, 0), Vector2(width, bar_rect.size.y)), Color(1, 1, 1, 0.10))
	for i in range(1, segments):
		var x := bar_rect.position.x + width * i
		draw_rect(Rect2(x - 1.0, bar_rect.position.y - 2.0, 2.0, bar_rect.size.y + 4.0), Color(0.95, 0.92, 0.85, 0.55))
	if checkpoint_fraction >= 0.0:
		# 存档点用菱形标记，压在细条上方，便于和区域分隔线区分。
		var center := Vector2(bar_rect.position.x + bar_rect.size.x * checkpoint_fraction, bar_rect.get_center().y)
		var r := 5.0
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), Color("8fe3d2"))
		draw_polyline(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0), center + Vector2(0, -r)]), Color(0.05, 0.08, 0.07, 0.9), 1.0)
