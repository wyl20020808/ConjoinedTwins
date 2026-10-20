shader_type canvas_item;
render_mode unshaded;

// 画面暗角与受击/低血量红边；受击瞬间额外在画面边缘做短暂的 RGB 色散。
// 平时不采样屏幕纹理；只有 damage 大于 0 时才读取。
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float low : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.94);
	float d = length(p);
	float edge = smoothstep(0.28, 0.90, d);
	float hurt = clamp(damage * 0.90 + low * 0.50, 0.0, 1.0);
	vec3 tint = mix(vec3(0.012, 0.014, 0.018), vec3(0.55, 0.03, 0.02), hurt);
	float alpha = edge * (0.34 + hurt * 0.55);
	if (damage > 0.02) {
		vec2 dir = (UV - 0.5) * edge * damage * 0.018;
		vec3 base = texture(screen, SCREEN_UV).rgb;
		vec3 split = vec3(texture(screen, SCREEN_UV + dir).r, base.g, texture(screen, SCREEN_UV - dir).b);
		COLOR = vec4(mix(split, tint, alpha), 1.0);
	} else {
		COLOR = vec4(tint, alpha);
	}
}
