extends RefCounted

# XZ floor footprints. The arena builds matching solid boxes for the player.
const RECTANGLES: Array[Rect2] = [Rect2(-6, -6, 2, 3), Rect2(4, -3, 2, 3)]

var rectangles: Array[Rect2] = RECTANGLES.duplicate()


func _init(initial_rectangles: Array = []) -> void:
	if not initial_rectangles.is_empty():
		set_rectangles(initial_rectangles)


func set_rectangles(new_rectangles: Array) -> void:
	var next: Array[Rect2] = []
	for item in new_rectangles:
		if item is Rect2:
			next.append(item)
	rectangles = next


func reset_rectangles() -> void:
	rectangles = RECTANGLES.duplicate()


func get_rectangles() -> Array[Rect2]:
	return rectangles.duplicate()


func intersects_circle(center: Vector3, radius: float = 0.0) -> bool:
	var pt := Vector2(center.x, center.z)
	var pad := maxf(0.0, radius)
	for rectangle in rectangles:
		if rectangle.grow(pad).has_point(pt):
			return true
	return false


# Deterministic swept segment against cover, optionally expanded by a radius.
# Empty space returns fraction=1; callers decide whether to stop or slide.
func clip_segment(start: Vector3, finish: Vector3, radius: float = 0.0) -> Dictionary:
	var result := {"blocked": false, "fraction": 1.0, "position": finish, "normal": Vector3.ZERO}
	var origin := Vector2(start.x, start.z)
	var movement := Vector2(finish.x - start.x, finish.z - start.z)
	for rectangle in rectangles:
		var hit := _entry(origin, movement, rectangle.grow(maxf(0, radius)))
		if hit.blocked and (not result.blocked or hit.fraction < result.fraction):
			result.blocked = true
			result.fraction = hit.fraction
			result.position = start.lerp(finish, hit.fraction)
			result.normal = Vector3(hit.normal.x, 0, hit.normal.y)
	return result


func _entry(origin: Vector2, movement: Vector2, rectangle: Rect2) -> Dictionary:
	var enter := 0.0
	var leave := 1.0
	var normal := Vector2.ZERO
	for axis in [0, 1]:
		var minimum: float = rectangle.position[axis]
		var maximum: float = rectangle.end[axis]
		if absf(movement[axis]) < 0.000001:
			if origin[axis] < minimum or origin[axis] > maximum:
				return {"blocked": false}
			continue
		var near_time: float = (minimum - origin[axis]) / movement[axis]
		var far_time: float = (maximum - origin[axis]) / movement[axis]
		var side := -1.0
		if near_time > far_time:
			var swap := near_time
			near_time = far_time
			far_time = swap
			side = 1.0
		if near_time > enter:
			enter = near_time
			normal = Vector2.ZERO
			normal[axis] = side
		leave = minf(leave, far_time)
		if enter > leave:
			return {"blocked": false}
	return {"blocked": true, "fraction": enter, "normal": normal}
