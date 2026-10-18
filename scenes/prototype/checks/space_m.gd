extends SceneTree
const Flow = preload("res://scenes/prototype/flow.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")
const Director = preload("res://scenes/prototype/enemies.gd")
const PatternVisual = preload("res://scenes/prototype/pattern_visual.gd")
var checks := 0
var failures: Array[String] = []
var cases := 0
var min_cover_gap := INF
var max_layout_usec := 0
var samples: Array[Dictionary] = []
class Blocker extends Node3D:
	var health := 100.0
	var kind: StringName = &"loop"
	var radius := 1.0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 15: failures.append(message)
func independent_clearance(point: Vector3, extent: float, player: Vector3, rectangles: Array) -> bool:
	if maxf(absf(point.x), absf(point.z)) + extent > 19.4: return false
	if point.distance_to(player) < maxf(5, extent + 1.4) - 0.001: return false
	for rect: Rect2 in rectangles:
		if rect.grow(extent + .149).has_point(Vector2(point.x, point.z)): return false
	return true
func stroke_clear(point: Vector3, cover: RefCounted) -> bool:
	for i in range(32):
		var a := point + Vector3(cos(i * TAU / 32), 0, sin(i * TAU / 32)) * 3.0
		var b := point + Vector3(cos((i + 1) * TAU / 32), 0, sin((i + 1) * TAU / 32)) * 3.0
		if cover.clip_segment(a, b, .4).blocked: return false
	return true
func run() -> void:
	var cover := Cover.new()
	for def in Rooms.definitions():
		cover.set_rectangles(def.cover)
		for seed in range(16):
			for player in [Vector3(0, 0, 5), Vector3(0, 0, 0), Vector3(17, 0, 17), Vector3(-17, 0, -17)]:
				for spec: Array in [[&"loop"], [&"zigzag"], [&"loop_boss"], [&"sequence_boss"], [&"final_boss"], [&"loop", &"blue", &"yellow"], [&"zigzag", &"orange", &"pair"]]:
					var flow := Flow.new()
					var start := Time.get_ticks_usec()
					var slots := flow.layout(&"curve", spec, player, cover, seed, [])
					max_layout_usec = maxi(max_layout_usec, Time.get_ticks_usec() - start)
					cases += 1
					var label := "%s seed %d player %s %s" % [def.id, seed, player, str(spec)]
					expect(slots.size() == spec.size(), "Every queued member finds space: " + label)
					for i in range(slots.size()):
						var slot: Dictionary = slots[i]
						expect(independent_clearance(slot.position, slot.radius, player, def.cover), "Full footprint clear of cover/player/edge: " + label)
						if slot.kind in [&"loop", &"zigzag", &"loop_boss", &"sequence_boss", &"final_boss"]: expect(not cover.clip_segment(player, slot.position, .4).blocked, "Outbound launch lane clear: " + label)
						expect(slot.kind == spec[i], "Finite roster prefix/order preserved: " + label)
						if player == Vector3(0, 0, 5) and spec.size() == 1 and slot.radius > 3.0: expect(Flow.readable_from_player(slot.position, slot.radius, player), "Whole practice silhouette fits normal perspective: " + label)
						if slot.kind in [&"loop", &"loop_boss", &"final_boss"]: expect(stroke_clear(slot.position, cover), "Whole loop drawing lane clear: " + label)
						for j in range(i): expect(slot.position.distance_to(slots[j].position) >= slot.radius + slots[j].radius + .149, "Group silhouettes do not overlap: " + label)
					if seed == 0 and player == Vector3(0, 0, 5): samples.append({"room": def.id, "kinds": spec, "slots": str(slots)})
					if seed == 0: expect(slots == flow.layout(&"curve", spec, player, cover, seed, []), "Layout is deterministic: " + label)
	# A narrow connecting hall leads to a valid open pocket between the
	# standard formation radii. Only the bounded per-member fallback can fill it.
	cover.set_rectangles([Rect2(-20, -20, 40, 19), Rect2(-20, -1, 19, 3), Rect2(3, -1, 17, 3), Rect2(-20, 2, 19, 1), Rect2(10, 2, 10, 1), Rect2(-20, 3, 22, 7), Rect2(10, 3, 10, 7), Rect2(-20, 10, 40, 10)])
	var fallback := Flow.new().layout(&"curve", [&"loop"], Vector3.ZERO, cover, 0, [])
	expect(fallback.size() == 1 and fallback[0].position == Vector3(6, 0, 6), "Bounded fallback finds off-formation pocket instead of stalling")
	expect(Flow.placement_radius(&"side_guard") >= 2.1, "Borrowed Heart reservation includes the crawler's outer hands, not only the hose/body")
	# Occupied pattern units reserve their entire outer silhouette, never body only.
	cover.set_rectangles(Rooms.definitions()[2].cover)
	var blockers: Array = []
	for point in [Vector3(0, 0, -12), Vector3(0, 0, 8), Vector3(-13, 0, 0)]:
		var blocker := Blocker.new()
		root.add_child(blocker)
		blocker.position = point
		blockers.append(blocker)
	for seed in range(12):
		var flow := Flow.new()
		var slots := flow.layout(&"line", [&"loop", &"yellow"], Vector3.ZERO, cover, seed, blockers)
		expect(slots.size() == 2, "Blocked entrance offers usable alternate positions: %d" % seed)
		for slot: Dictionary in slots:
			for blocker in blockers: expect(slot.position.distance_to(blocker.position) >= slot.radius + Flow.placement_radius(blocker.kind) + .249, "Occupied whole silhouette respected")
	for blocker in blockers: blocker.free()
	# Actual director/configure must retain the chosen position and query anchors.
	var director := Director.new()
	director.cover = cover
	root.add_child(director)
	var player := Blocker.new()
	root.add_child(player)
	player.position = Vector3(0, 0, 5)
	for def in Rooms.definitions():
		cover.set_rectangles(def.cover)
		for kind: StringName in [&"loop", &"zigzag", &"loop_boss", &"final_boss"]:
			director.clear()
			var units: Array = director.spawn_formation(&"curve", [kind], player, 7)
			expect(units.size() == 1, "Actual director delivers " + String(kind))
			if units.is_empty(): continue
			var e: Node3D = units[0]
			expect(independent_clearance(e.position, Flow.placement_radius(kind), player.position, def.cover), "Configure does not reclamp reserved space")
			for phase in range(e.phase_count()):
				e.debug_set_phase(phase)
				var points: Array = e.cable_world_points()
				for i in range(points.size() / 2): expect(not cover.clip_segment(points[i * 2], points[i * 2 + 1], .4).blocked, "All current/future-phase physical blue spans clear of cover")
			expect(stroke_clear(e.position, cover), "Actual boss/practice has a full drawing ring")
	director.clear()
	director.free()
	player.free()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "cases": cases, "max_layout_usec": max_layout_usec, "samples": samples}))
	quit(0 if failures.is_empty() else 1)
