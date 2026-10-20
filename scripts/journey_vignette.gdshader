shader_type canvas_item;
render_mode unshaded;

// 画面暗角与受击/低血量红边；只加一层全屏透明 quad，不采样屏幕纹理。
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float low : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.94);
	float d = length(p);
	float edge = smoothstep(0.28, 0.90, d);
	float hurt = clamp(damage * 0.90 + low * 0.50, 0.0, 1.0);
	vec3 tint = mix(vec3(0.012, 0.014, 0.018), vec3(0.55, 0.03, 0.02), hurt);
	float alpha = edge * (0.34 + hurt * 0.55);
	COLOR = vec4(tint, alpha);
}
