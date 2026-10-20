shader_type sky;
render_mode use_debanding;

// 风格化黄昏天空：渐变天穹 + 太阳圆盘与光晕 + 一层缓慢漂移的云。
// 颜色由每章调色板驱动，避免 2K 全景照片被拉满天空后的模糊和粉紫一片。
uniform vec3 horizon_color : source_color = vec3(0.72, 0.71, 0.62);
uniform vec3 sky_color : source_color = vec3(0.35, 0.50, 0.60);
uniform vec3 zenith_color : source_color = vec3(0.20, 0.30, 0.38);
uniform vec3 ground_color : source_color = vec3(0.10, 0.12, 0.13);
uniform vec3 cloud_lit : source_color = vec3(0.96, 0.92, 0.84);
uniform vec3 cloud_shadow : source_color = vec3(0.46, 0.50, 0.54);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 sun_dir = vec3(0.0, 0.25, 1.0);
uniform float sun_energy = 2.0;
uniform float cloud_coverage = 0.42;
uniform float cloud_scale = 1.0;
uniform float cloud_speed = 0.0035;
uniform float haze = 0.45;
uniform float saturation = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += value_noise(p) * amplitude;
		p = p * 2.02 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return value;
}

// Godot 4.7 的天空着色器内置视线方向名是 EYEDIR（不是早期文档里的 EYE_DIR）。
void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 light = normalize(sun_dir);
	float up = clamp(dir.y, 0.0, 1.0);

	// 低空主色到天顶；暖色雾带只保留在最底部，避免整片天空被地平线颜色冲淡。
	vec3 col = mix(sky_color, zenith_color, pow(up, 0.65));
	float band = 1.0 - smoothstep(0.0, 0.18, up);
	col = mix(col, horizon_color, band * 0.85 * (0.6 + 0.4 * haze));
	// 太阳方位角的低空暖光：即使太阳圆盘在画面上方，消失点方向仍有金色层次。
	vec3 flat_dir = normalize(vec3(dir.x, 0.0, dir.z));
	vec3 flat_sun = normalize(vec3(light.x, 0.0, light.z));
	float azimuth = pow(max(dot(flat_dir, flat_sun), 0.0), 5.0);
	col += sun_color * azimuth * 0.18 * (1.0 - up);

	float sun_dot = max(dot(dir, light), 0.0);
	float disk = smoothstep(0.99972, 0.99992, sun_dot);
	float glow = pow(sun_dot, 28.0) * 0.45 + pow(sun_dot, 5.0) * 0.10;
	col += sun_color * sun_energy * (disk * 6.0 + glow);

	// 云层投影到高空平面；在地平线附近淡出，避免径向拉丝。
	float cloud_fade = smoothstep(0.02, 0.22, up);
	if (cloud_fade > 0.001) {
		vec2 uv = dir.xz / max(dir.y, 0.06);
		uv = uv * (0.55 * cloud_scale) + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		float n = fbm(uv * 1.35);
		float cover = smoothstep(1.0 - cloud_coverage, 1.16 - cloud_coverage, n);
		cover *= cloud_fade;
		float lit = pow(max(dot(dir, light), 0.0), 2.0);
		vec3 cloud = mix(cloud_shadow, cloud_lit, 0.25 + 0.75 * lit);
		cloud *= 0.9 + 0.1 * sun_energy;
		col = mix(col, cloud, cover * 0.9);
	}

	if (dir.y < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, 0.12, -dir.y));
	}

	float luminance = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luminance), col, saturation);
	float dither = (hash21(dir.xz * 713.0 + vec2(dir.y * 149.0)) - 0.5) / 255.0;
	COLOR = max(col + dither, vec3(0.0));
}
