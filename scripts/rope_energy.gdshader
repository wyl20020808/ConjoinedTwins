shader_type spatial;
// 能量绳外壳：叠加在麻绳网格上的加色半透明层，只做表现，不改绳形与碰撞。
// 绳网格的三角形绕序朝内（麻绳材质用双面渲染掩盖了这一点），外壳因此剔除 front 面才是朝外那层。
// 沿绳长从 01 的青色渐变到 02 的橙色；能量包沿绳往返流动，张力越大越亮越快，受阻时红色闪动。
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(0.10, 0.85, 1.00);
uniform vec3 color_b : source_color = vec3(1.00, 0.48, 0.10);
uniform vec3 alarm : source_color = vec3(1.00, 0.18, 0.12);
uniform float span = 40.0;       // 绳全长对应的 UV.y 值（rope_view 每帧写入）
uniform float tension = 0.0;     // 0 松弛，1 达到绳长上限
uniform float alarm_mix = 0.0;   // 受阻闪烁 0..1
uniform float clock = 0.0;       // 由脚本推进，暂停时冻结
uniform float inflate = 0.06;
uniform float energy = 1.0;      // 夜里更亮

void vertex() {
	VERTEX += NORMAL * inflate;
}

void fragment() {
	float t = clamp(UV.y / max(span, 0.001), 0.0, 1.0);
	vec3 base = mix(color_a, color_b, smoothstep(0.15, 0.85, t));
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float body = 0.95 + 0.6 * pow(rim, 1.4);
	// 两束能量包：一束 01→02，一束 02→01；绷紧时变快变密。
	float speed = mix(0.45, 1.6, smoothstep(0.5, 1.0, tension));
	float a = fract(t * 2.0 - clock * speed);
	float b = fract(t * 2.0 + clock * speed * 0.8 + 0.5);
	float packets = pow(smoothstep(0.75, 1.0, a), 3.0) + pow(smoothstep(0.80, 1.0, b), 3.0) * 0.7;
	// 细碎电弧噪点，张力大时更明显。
	float crackle = step(0.93, fract(sin(floor(UV.y * 3.0 + clock * 18.0) * 91.7 + floor(UV.x * 6.0) * 13.1) * 4375.5));
	float glow = (0.5 + 0.6 * tension) * body + packets * (2.2 + 2.4 * tension) + crackle * 1.2 * smoothstep(0.75, 1.0, tension);
	vec3 col = mix(base, vec3(1.0), packets * 0.35 * tension);
	col = mix(col, alarm, alarm_mix);
	// 两端淡入，避免与角色腰部硬切。
	float ends = smoothstep(0.0, 0.04, t) * smoothstep(1.0, 0.96, t);
	ALBEDO = col * glow * energy * ends;
}
