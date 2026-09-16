extends RefCounted
## Read-only prediction against the current physics world; no future target motion.

static func predict(space: PhysicsDirectSpaceState2D, origin: Vector2, velocity: Vector2, excluded: Array[RID], step: float) -> PackedVector2Array:
	var points := PackedVector2Array([origin])
	var query := PhysicsRayQueryParameters2D.create(origin, origin, Arrow.FLIGHT_COLLISION_MASK, excluded)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var count := ceili(Arrow.LIFETIME / step)
	for i in range(1, count + 1):
		var next := Arrow.flight_position(origin, velocity, minf(i * step, Arrow.LIFETIME))
		query.from = points[-1]
		query.to = next
		if not query.from.is_equal_approx(next):
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				points.append(hit.position)
				return points
		points.append(next)
	return points

static func length_of(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length

static func first_half(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var remaining := length_of(points) * 0.5
	var result := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if segment <= 0.000001:
			continue
		if segment >= remaining:
			result.append(points[i - 1].lerp(points[i], remaining / segment))
			break
		result.append(points[i])
		remaining -= segment
	return result

static func dots(points: PackedVector2Array, spacing := 8.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var traversed := 0.0
	var next_distance := 4.0
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if segment <= 0.000001:
			continue
		while next_distance <= traversed + segment:
			result.append(points[i - 1].lerp(points[i], (next_distance - traversed) / segment))
			next_distance += spacing
		traversed += segment
	# Preserve the exact cutoff, even for a very close impact.
	if points.size() > 1 and (result.is_empty() or result[-1].distance_to(points[-1]) > 0.01):
		result.append(points[-1])
	return result
