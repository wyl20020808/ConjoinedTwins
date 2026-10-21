shader_type canvas_item;
// 主界面与载入画面的封面压暗：左侧和底部渐暗留出文字区，四角轻微暗角，保留中间画面。
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.04, 1.0);
uniform float left_strength = 0.82;
uniform float bottom_strength = 0.9;
uniform float base = 0.16;

void fragment() {
	float left = smoothstep(0.72, 0.0, UV.x) * left_strength;
	float bottom = smoothstep(0.42, 1.0, UV.y) * bottom_strength;
	float top = smoothstep(0.22, 0.0, UV.y) * 0.45;
	vec2 c = UV - vec2(0.5);
	float vignette = smoothstep(0.45, 0.85, length(c * vec2(1.0, 1.25))) * 0.5;
	COLOR = vec4(tint.rgb, clamp(max(max(left, bottom), max(top, vignette)) + base, 0.0, 0.96));
}
