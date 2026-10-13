extends RefCounted

const LIMIT := 220.0
const SPEED := 180.0
const RADIUS := 12.0

static func free_at(p: Vector2, walls: Array) -> bool:
	for wall: Rect2 in walls:
		if wall.grow(RADIUS).has_point(p):
			return false
	return true

static func sweep(p: Vector2, motion: Vector2, walls: Array) -> Vector2:
	# Small axis-separated sweeps allow sliding without tunnelling.
	var result := p
	for axis in [Vector2(motion.x, 0), Vector2(0, motion.y)]:
		if free_at(result + axis, walls):
			result += axis
		else:
			var low := 0.0
			var high := 1.0
			for iteration in range(12):
				var middle := (low + high) * 0.5
				if free_at(result + axis * middle, walls):
					low = middle
				else:
					high = middle
			result += axis * low
	return result

static func advance(a: Node2D, b: Node2D, input_a: Vector2, input_b: Vector2, delta: float, walls: Array) -> void:
	var count := maxi(1, ceili(SPEED * delta / 2.0))
	var da := input_a.limit_length() * SPEED * delta / count
	var db := input_b.limit_length() * SPEED * delta / count
	for step in range(count):
		var pa := a.position
		var pb := b.position
		var ca := sweep(pa, da, walls)
		var cb := sweep(pb, db, walls)
		if ca.distance_to(cb) > LIMIT:
			var ma := ca.distance_to(pa)
			var mb := cb.distance_to(pb)
			var total := ma + mb
			if total > 0.00001:
				var correction := (ca - cb).normalized() * (ca.distance_to(cb) - LIMIT + 0.00001)
				var qa := ca - correction * ma / total
				var qb := cb + correction * mb / total
				# Corrections only modify this step's requested motion; never drag an idle twin.
				if free_at(qa, walls) and free_at(qb, walls) and qa.distance_to(pa) <= da.length() + 0.001 and qb.distance_to(pb) <= db.length() + 0.001:
					ca = qa
					cb = qb
				else:
					var low := 0.0
					var high := 1.0
					for iteration in range(16):
						var t := (low + high) / 2.0
						if pa.lerp(ca, t).distance_to(pb.lerp(cb, t)) <= LIMIT:
							low = t
						else:
							high = t
					ca = pa.lerp(ca, low)
					cb = pb.lerp(cb, low)
		a.position = ca
		b.position = cb
