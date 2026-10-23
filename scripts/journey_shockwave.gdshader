shader_type spatial;
// 贴地冲击波环：加色、不受光、不写深度；progress 0→1 由特效池逐帧推进。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.7, 0.35);
uniform float progress = 0.0;
uniform float strength = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float r = progress;
	float w = mix(0.22, 0.05, progress);
	float ring = smoothstep(r - w, r, d) * (1.0 - smoothstep(r, r + w * 0.6, d));
	// 内圈一层很淡的冲击光，前 20% 时间可见。
	float core = (1.0 - smoothstep(0.0, r + 0.05, d)) * (1.0 - smoothstep(0.0, 0.2, progress)) * 0.6;
	float fade = 1.0 - progress;
	ALBEDO = tint * (ring * 3.0 + core) * fade * fade * strength;
}
