class_name ConditionSegments
extends RefCounted
## Shared condition drawing only; equipment owns wear and repair checkpoints.
static func draw(surface: CanvasItem, center: Vector2, radius: float, start: float,
		end: float, condition: float, steps: int, color: Color, background: Color,
		width: float) -> void:
	steps = clampi(steps, 1, 8)
	var gap := minf(.018, (end - start) / (steps * 5))
	for checkpoint in range(steps):
		var a := lerpf(start, end, float(checkpoint) / steps) + gap
		var b := lerpf(start, end, float(checkpoint + 1) / steps) - gap
		surface.draw_arc(center, radius, a, b, 12, background, width, true)
		var fill := clampf(condition * steps - checkpoint, 0, 1)
		if fill > 0:
			surface.draw_arc(center, radius, a, lerpf(a, b, fill), 12, color, width, true)
