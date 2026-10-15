extends RefCounted

# 路面、角色支撑与绳索接触共用的解析地形。沿道路使用 x/y，垂直高度为 height。
const KINDS := ["slope", "steps", "tilt", "lift", "ferry", "drawbridge"]
const MOVING := ["lift", "ferry"]

static func sample(kind: String, rect: Rect2, spec: Dictionary, time: float, point: Vector2) -> Dictionary:
	var platform := rect
	var height := 0.0
	var velocity := Vector3.ZERO
	var phase: float = spec.get("phase", 0.0)
	var angle: float = TAU * time / spec.get("period", 3.2) + phase
	var amplitude: float = spec.get("amplitude", 28.0)
	if kind == "ferry":
		platform.position.x += sin(angle) * amplitude
		velocity.x = cos(angle) * amplitude * TAU / spec.get("period", 3.2)
	elif kind == "lift":
		height = (sin(angle) + 1.0) * amplitude * 0.5
		velocity.y = cos(angle) * amplitude * 0.5 * TAU / spec.get("period", 3.2)
	elif kind == "drawbridge":
		var opened: float = spec.get("opening", 0.0)
		height = (1.0-opened) * 100.0
	var normal := Vector3.UP
	if kind in ["slope", "steps"]:
		var t := clampf((point.y - rect.position.y) / rect.size.y, 0, 1)
		var ramp := minf(t, 1.0-t) * 2.0
		height = ramp * amplitude
		if kind == "steps": height = minf(amplitude, floor((ramp * 4.0 + 0.00001)) * 8.0)
		else: normal = Vector3(0, 1, -(1 if t < 0.5 else -1) * 2.0 * amplitude / rect.size.y).normalized()
	elif kind == "tilt":
		var fade := sin(PI * clampf((point.y-rect.position.y)/rect.size.y, 0, 1))
		height = (point.x-rect.get_center().x) / rect.size.x * amplitude * fade + amplitude * 0.5 * fade
		normal = Vector3(-amplitude / rect.size.x * fade, 1, 0).normalized()
	return {"rect": platform, "height": height, "normal": normal, "velocity": velocity,
		"friction": 0.8, "opening":spec.get("opening",0.0), "supported": platform.has_point(point) and (kind != "drawbridge" or spec.get("opening", 0.0) >= 0.999)}

static func mesh_height(kind: String, rect: Rect2, spec: Dictionary, time: float, point: Vector2) -> float:
	return sample(kind, rect, spec, time, point).height
