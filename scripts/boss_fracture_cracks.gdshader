shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec3 seeds[28];
uniform float strength = 0.0;
varying vec3 source_position;
void vertex() { source_position = VERTEX; }
void fragment() {
	float first = 100.0;
	float second = 100.0;
	for (int i = 0; i < 28; i++) {
		float d = distance(source_position, seeds[i]);
		if (d < first) { second = first; first = d; }
		else { second = min(second, d); }
	}
	float line = 1.0-smoothstep(0.001, 0.009, second-first);
	ALBEDO = vec3(1.0, 0.25, 0.025)*strength;
	ALPHA = line;
}
