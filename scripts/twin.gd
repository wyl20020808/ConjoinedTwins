extends Node2D

const RADIUS := 12.0
var tint := Color.CYAN
var number := "1"

func _draw() -> void:
	draw_circle(Vector2(0, 9), 15, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-11, -16, 22, 25), tint)
	draw_rect(Rect2(-7, -12, 14, 7), Color(0.06, 0.1, 0.16))
	draw_circle(Vector2(-4, -9), 2, Color.WHITE)
	draw_circle(Vector2(4, -9), 2, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(-4, 5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
