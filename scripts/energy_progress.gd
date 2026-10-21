extends Control
# 能量连线进度条：左端 01（青）与右端 02（橙）两个节点，能量沿连线从 01 流向 02，
# 与游戏里两人之间的能量绳同一配色。只负责绘制，进度由载入画面写入。
const CYAN := Color("4fd8e8")
const ORANGE := Color("ffa04d")
const TRACK := Color(1, 1, 1, 0.12)
var value := 0.0
var shown := 0.0
var indeterminate := false
var clock := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(320, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	clock += delta
	# 显示值平滑追赶真实进度，避免分块下载时跳格；回退（换阶段）直接跟随。
	shown = value if value < shown else lerpf(shown, value, minf(1.0, delta * 8.0))
	queue_redraw()

func node_color(t: float) -> Color:
	return CYAN.lerp(Color("f4f1e8"), clampf(t * 2.0, 0.0, 1.0)) if t < 0.5 else Color("f4f1e8").lerp(ORANGE, clampf((t - 0.5) * 2.0, 0.0, 1.0))

func _draw() -> void:
	var y := size.y * 0.5
	var left := 22.0
	var right := size.x - 22.0
	var span := right - left
	draw_line(Vector2(left, y), Vector2(right, y), TRACK, 4.0, true)
	var head := left + span * clampf(shown, 0.0, 1.0)
	if indeterminate:
		# 未知总量（如等待队友）时，一段光沿连线往返流动。
		var t := (sin(clock * 2.2) + 1.0) * 0.5
		var from := left + span * maxf(0.0, t - 0.18)
		var to := left + span * minf(1.0, t + 0.18)
		segment(from, to, y, 0.7)
	else:
		segment(left, head, y, 1.0)
		# 能量头的光晕与沿连线流动的亮点。
		if shown > 0.002 and shown < 0.999:
			var glow := node_color(shown)
			for r in [14.0, 9.0, 5.0]:
				draw_circle(Vector2(head, y), r, Color(glow, 0.12 + (14.0 - r) * 0.04))
			draw_circle(Vector2(head, y), 3.0, Color.WHITE)
		for n in range(3):
			var p := fposmod(clock * 0.35 + n / 3.0, 1.0)
			var x := left + (head - left) * p
			if head - left > 12.0: draw_circle(Vector2(x, y), 2.2, Color(1, 1, 1, 0.55 * sin(p * PI)))
	orb(Vector2(left, y), CYAN, "01", true)
	orb(Vector2(right, y), ORANGE, "02", shown >= 0.999)

func segment(from: float, to: float, y: float, alpha: float) -> void:
	if to - from < 1.0: return
	var steps := maxi(2, int((to - from) / 6.0))
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var span := size.x - 44.0
	for i in range(steps + 1):
		var x := lerpf(from, to, float(i) / steps)
		points.append(Vector2(x, y))
		colors.append(Color(node_color((x - 22.0) / span), alpha))
	# 外层柔光 + 内芯，形成发光的能量绳。
	var soft := PackedColorArray()
	for c in colors: soft.append(Color(c, c.a * 0.22))
	draw_polyline_colors(points, soft, 12.0, true)
	draw_polyline_colors(points, colors, 4.0, true)

func orb(center: Vector2, color: Color, text: String, lit: bool) -> void:
	var pulse := 0.5 + 0.5 * sin(clock * 3.0)
	if lit:
		draw_circle(center, 18.0 + pulse * 3.0, Color(color, 0.16))
	draw_circle(center, 13.0, Color(0.04, 0.05, 0.06, 0.92))
	draw_arc(center, 13.0, 0, TAU, 32, Color(color, 1.0 if lit else 0.45), 2.5, true)
	var font := get_theme_default_font()
	var measure := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, center + Vector2(-measure.x * 0.5, 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, 1.0 if lit else 0.6))
