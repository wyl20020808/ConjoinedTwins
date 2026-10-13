extends RefCounted

# 独立于路线控制器：只接受键盘原始整数轴值，不接受近似方向或任意摇杆幅度。
static func legal(input: Array) -> bool:
	if input.size() != 6: return false
	for axis in range(4):
		var value: float = input[axis]
		if not is_finite(value) or value < -1 or value > 1 or value != roundf(value): return false
	return typeof(input[4]) == TYPE_BOOL and typeof(input[5]) == TYPE_BOOL
