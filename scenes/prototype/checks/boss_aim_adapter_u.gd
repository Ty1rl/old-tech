# CHECK-ONLY copy of jam-1-aim-adapter.patch. Production owner must apply it.
extends RefCounted

# Map a click near a visible raised part to its actual world position. Projecting
# that same click onto the floor instead can miss by an entire body length.
const Tuning = preload("res://scenes/prototype/tuning.gd")


static func target(screen: Vector2, camera: Camera3D, enemies: Array, tool: int, origin: Vector3) -> Variant:
	if tool not in [1, 2]:
		return null
	var result: Variant = null
	var pixel_scale := maxf(0.5, camera.get_viewport().get_visible_rect().size.y / 800.0)
	var nearest := float(Tuning.VIEW.blue_assist_pixels if tool == 1 else Tuning.VIEW.yellow_assist_pixels) * pixel_scale
	var max_range := float(Tuning.RING.range if tool == 1 else Tuning.BEAM.range)
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.health <= 0.0 or enemy.is_queued_for_deletion():
			continue
		var point: Vector3
		var distance: float
		if tool == 1:
			if not enemy.has_cuttable_part(): continue
			var points: Array = enemy.cable_world_points()
			if points.size() < 2: continue
			var paired: bool = enemy.has_method("lesson_state")
			var step := 2 if paired else 1
			distance = INF
			for i in range(0, points.size()-1, step):
				if camera.is_position_behind(points[i]) or camera.is_position_behind(points[i+1]): continue
				var start := camera.unproject_position(points[i])
				var finish := camera.unproject_position(points[i+1])
				var delta := finish - start
				var fraction := clampf((screen-start).dot(delta)/maxf(.001,delta.length_squared()),0,1)
				var candidate := screen.distance_to(start.lerp(finish,fraction))
				if candidate < distance:
					distance = candidate
					point = (points[i] as Vector3).lerp(points[i+1],fraction)
		else:
			if not enemy.is_core_exposed() or enemy.core_broken: continue
			var surface: Variant = null
			if enemy.has_method("visible_flash_aim"):
				surface = enemy.visible_flash_aim(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
			if surface != null:
				point = surface
				distance = 0.0 # Pointer intersects actual shown surface, no center snapping.
			else:
				point = enemy.core_world_position()
				if camera.is_position_behind(point): continue
				distance = screen.distance_to(camera.unproject_position(point))
		if distance > nearest or Vector2(point.x - origin.x, point.z - origin.z).length() > max_range:
			continue
		nearest = distance
		result = Vector3(point.x, 0, point.z)
	return result
