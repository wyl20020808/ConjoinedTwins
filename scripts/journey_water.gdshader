shader_type spatial;
// 河面：解析波纹法线（两组方向、顺流向镜头流动）+ 菲涅尔 + 岸边白沫。
// 只是表现层；没有折射与屏幕空间反射，反射来自天空辐照度与主光高光。
render_mode cull_back, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.035, 0.105, 0.125);
uniform vec3 shallow : source_color = vec3(0.10, 0.27, 0.27);
uniform vec3 foam_color : source_color = vec3(0.82, 0.86, 0.84);
uniform float bank_near = 19.0;   // 靠路一侧河岸的 |x|
uniform float bank_far = 45.0;
uniform float flow = 1.4;         // 顺流速度（米/秒，朝 +z）
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world.x * 0.9 + TIME * 1.3) * sin(world.z * 0.7 + TIME * 1.7) * 0.025;
}

vec2 ripple(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(cos(p.x * 1.10 + p.y * 0.35 + t * 0.9), cos(p.y * 1.30 - t * flow * 1.3)) * 0.090;
	g += vec2(cos(p.x * 2.70 - p.y * 1.10 + t * 1.7), cos(p.y * 2.90 + p.x * 0.6 - t * flow * 2.6)) * 0.045;
	g += vec2(cos(p.x * 6.10 + p.y * 3.70 - t * 2.3), cos(p.y * 7.30 - p.x * 2.2 - t * flow * 5.0)) * 0.020;
	return g;
}

void fragment() {
	vec2 g = ripple(world.xz, TIME);
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float ax = abs(world.x);
	float edge = min(ax - bank_near, bank_far - ax);
	float depth = smoothstep(0.0, 7.0, edge);
	vec3 col = mix(shallow, deep, depth);
	// 岸边白沫：贴岸 0–1.2 米，用波纹相位打碎边界，随水流移动。
	float churn = 0.5 + 0.5 * sin(world.z * 2.3 - TIME * flow * 3.0 + g.x * 30.0);
	float foam = (1.0 - smoothstep(0.0, 1.2, edge)) * smoothstep(0.35, 0.8, churn);
	col = mix(col, foam_color, foam * 0.75);
	ALBEDO = col * (1.0 - fres * 0.35);
	ROUGHNESS = mix(0.05, 0.6, foam);
	SPECULAR = 0.6;
}
