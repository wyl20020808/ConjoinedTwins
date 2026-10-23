shader_type spatial;
// 怪物蓄力预警：叠在怪物网格上的暖红边缘光，强度随蓄力进度上升并轻微脉动；只在预警阶段出现。
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float charge = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.25, 0.08);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	float pulse = 0.75 + 0.25 * sin(TIME * 18.0);
	ALBEDO = tint * rim * charge * pulse * 1.1;
}
