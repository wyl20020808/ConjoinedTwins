shader_type spatial;
// Boss 地面预警：直线 / 横带（shape 0）与圆圈（shape 1）。charge 0→1 为前摇进度，
// 越接近出手越亮，最后 15% 快速闪烁；直线内有朝 flow 方向流动的箭纹，提示攻击来向。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform float charge = 0.0;
uniform int shape = 0;
uniform float flow = 1.0;
uniform vec2 aspect = vec2(1.0, 8.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge;
	float fill;
	if (shape == 1) {
		float d = length(p);
		edge = smoothstep(0.86, 0.94, d) * (1.0 - smoothstep(0.97, 1.0, d));
		// 圆内由外向内收拢的环，前摇结束时收到中心。
		float sweep = 1.0 - charge;
		fill = (1.0 - smoothstep(sweep - 0.06, sweep, d)) * 0.0 + step(d, 1.0) * 0.22;
		fill += (smoothstep(sweep - 0.08, sweep, d) - smoothstep(sweep, sweep + 0.04, d)) * 0.8 * step(d, 1.0);
	} else {
		vec2 q = abs(p);
		float bx = 1.0 - smoothstep(1.0 - 0.12 / aspect.x, 1.0 - 0.04 / aspect.x, q.x);
		edge = 1.0 - bx;
		float stripes = fract(UV.y * aspect.y * 0.5 - TIME * 1.6 * flow + abs(p.x) * 0.35);
		fill = 0.18 + smoothstep(0.55, 0.7, stripes) * (1.0 - smoothstep(0.8, 0.95, stripes)) * 0.35;
	}
	float blink = charge > 0.85 ? 0.55 + 0.45 * step(0.5, fract(TIME * 9.0)) : 1.0;
	float alpha = clamp((edge * 0.95 + fill) * mix(0.45, 1.0, charge) * blink, 0.0, 1.0);
	ALBEDO = tint.rgb * (1.0 + charge * 0.6);
	ALPHA = alpha * tint.a;
}
