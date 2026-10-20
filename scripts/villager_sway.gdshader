shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 静态 Tripo 村民没有骨架；用按高度加权的极轻顶点摆动表现呼吸/重心变化，脚底保持不动。
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform float sway_amount = 0.022;
uniform float body_height = 1.0;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	float h = clamp(VERTEX.y / body_height, 0.0, 1.0);
	float t = TIME * 1.05 + phase;
	VERTEX.x += sin(t) * sway_amount * h;
	VERTEX.z += cos(t * 0.73) * sway_amount * 0.55 * h;
	VERTEX.y += sin(t * 0.5 + 1.3) * sway_amount * 0.3 * h;
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	if (has_albedo) ALBEDO *= texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.18;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}
