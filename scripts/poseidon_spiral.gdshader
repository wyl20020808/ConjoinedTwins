shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D foam_texture : repeat_enable, filter_linear;
uniform float phase = 0.0;
uniform float strength = 0.0;
void vertex() {
	float taper = sin(UV.y * 3.14159265);
	float ripple = sin(UV.y * 33.0 - TIME * 3.4 + phase) * 0.12;
	ripple += sin(UV.y * 71.0 + UV.x * 5.0 - TIME * 5.0) * 0.055;
	VERTEX += NORMAL * ripple * taper;
	VERTEX.y += sin(UV.y * 22.0 - TIME * 2.6 + phase) * 0.18 * taper;
}
void fragment() {
	vec2 flow = vec2(UV.y * 5.0 - TIME * (0.35 + strength * 0.2), UV.x * 0.7);
	float a = texture(foam_texture, flow).r;
	float b = texture(foam_texture, flow * vec2(1.7, 1.3) + vec2(-TIME * 0.17, 0.31)).r;
	float foam = smoothstep(0.35, 0.85, a * 0.65 + b * 0.35);
	float border = smoothstep(0.0, 0.13, UV.x) * (1.0 - smoothstep(0.75, 1.0, UV.x));
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.8, 1.0, UV.y));
	float crest = smoothstep(0.62, 0.88, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	vec3 water = mix(vec3(0.025, 0.34, 0.46), vec3(0.12, 0.72, 0.86), a);
	ALBEDO = mix(water, vec3(0.7, 0.94, 1.0), foam * 0.7 + crest * a * 0.35);
	EMISSION = ALBEDO * (0.85 + strength * 0.35);
	ROUGHNESS = 0.16;
	SPECULAR = 0.8;
	NORMAL_MAP = normalize(vec3((a-b)*0.65, (a-0.5)*0.5, 1.0))*0.5+0.5;
	ALPHA = border * ends * (0.55 + foam * 0.35 + crest * 0.1);
}
