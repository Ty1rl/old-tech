extends SceneTree

const Presentation = preload("res://scenes/prototype/weapon_presentation.gd")
var arena: Node3D
var checks := 0
var failures: Array[String] = []
var fakes: Array[Node3D] = []
var hit_order: Array[int] = []


class Receiver extends Node3D:
	var health := 1000.0
	var radius := 0.65
	var rewind_id := 0
	var calls := 0
	var order: Array[int]
	var contexts: Array[Dictionary] = []
	var armor := false
	var pattern := false
	var progress := 0
	func combat_id() -> int: return rewind_id
	func attack_radius(_tool: StringName) -> float: return radius
	func lesson_state() -> Dictionary: return {"progress": progress}
	func receive_attack(tool: StringName, damage: float, _point: Vector3, context: Dictionary) -> Dictionary:
		calls += 1
		contexts.append(context.duplicate(true))
		order.append(rewind_id)
		if tool == &"ring" and pattern: progress += 1
		var amount := 0.0 if context.get("already_hit", false) else damage * (0.12 if armor else 1.0)
		health -= amount
		return {"connected": true, "dealt": amount, "armored": armor, "killed": false}


func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func button(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event


func fake(id: int, position3: Vector3, armor: bool = false) -> Receiver:
	var node := Receiver.new()
	node.rewind_id = id
	node.position = position3
	node.order = hit_order
	node.armor = armor
	arena.add_child(node)
	fakes.append(node)
	return node


func fresh() -> void:
	for node in fakes:
		arena.remove_child(node)
		node.queue_free()
	fakes.clear()
	hit_order.clear()
	arena.reset_arena()
	arena.director.clear()
	arena.player.position = Vector3(0, 0.55, 0)


func fire(charge: float, aim: Vector3 = Vector3(0, 0, -30)) -> void:
	arena.weapons.select_tool(2)
	arena.player.set_visual_tool(2)
	arena.weapons.handle_event(button(true), arena.player, aim)
	arena.weapons.step(charge * arena.weapons.flash.settings.charge_time, arena.player, aim, [], 0)
	arena.weapons.handle_event(button(false), arena.player, aim)


func tick(dt: float, nodes: Array, world_delta: float = -1.0) -> void:
	arena.weapons.step(dt, arena.player, Vector3(0, 0, -30), nodes, world_delta)


func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for v in value:
			if not values_only(v): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	fresh()
	var near := fake(1, Vector3(0, 0, -4))
	var middle := fake(2, Vector3(0.35, 0, -8), true)
	var far := fake(3, Vector3(0, 0, -12))
	var off_line := fake(4, Vector3(2.1, 0, -6))
	fire(1)
	expect(arena.weapons.flash.pulses[0].piercing, "full charge marks pulse piercing at release")
	tick(0.35, [far, off_line, middle, near])
	expect(hit_order == [1, 2, 3], "charged pulse hits actual intersected targets in geometric order")
	expect(near.calls == 1 and middle.calls == 1 and far.calls == 1 and off_line.calls == 0, "no chain, bounce or off-line target hits")
	expect(is_equal_approx(middle.health, 988), "armor keeps reduced ordinary body damage")
	var pulse: Dictionary = arena.weapons.flash.pulses[0]
	expect(pulse.hit_ids == [1, 2, 3] and pulse.pos.z < -14, "piercing keeps traveling and records stable hit IDs")
	# Re-enter the same body's volume on subsequent ticks, including after rewind.
	near.position = Vector3(0, 0, -14.9)
	var snapshot: Dictionary = arena.weapons.capture_state()
	expect(values_only(snapshot), "pulse snapshot has values only")
	tick(0.01, [near, middle, far])
	expect(near.calls == 1, "large surviving enemy is not hit twice across ticks")
	arena.weapons.restore_state(snapshot)
	tick(0.01, [near])
	expect(near.calls == 1, "rewind restores hit ledger before resuming flight")
	expect(snapshot.flash.pulses[0].hit_ids == [1, 2, 3], "snapshot hit ledger does not alias live pulse state")
	tick(2, [near, middle, far])
	expect(arena.weapons.flash.pulses.is_empty() and is_equal_approx(arena.weapons.flash.end_point.z, -35), "piercing stops at range")
	fresh()
	near = fake(7, Vector3(0, 0, -4))
	far = fake(8, Vector3(0, 0, -8))
	fire(1)
	tick(.15, [near, far])
	arena.weapons.flash.cooldown = 0
	fire(1)
	tick(.3, [near, far])
	expect(near.calls == 2 and far.calls == 2, "simultaneous pulses each hit each enemy once with separate hit ledgers")
	for charge in [0.0, 0.89]:
		fresh()
		near = fake(11, Vector3(0, 0, -4))
		far = fake(12, Vector3(0, 0, -8))
		fire(charge)
		tick(0.5, [far, near])
		expect(near.calls == 1 and far.calls == 0 and arena.weapons.flash.pulses.is_empty(), "tap/sub-threshold shot stops at first body %.2f" % charge)
	fresh()
	arena.weapons.flash.settings.pierce_threshold = 0.8
	near = fake(21, Vector3(0, 0, -4))
	far = fake(22, Vector3(0, 0, -8))
	fire(0.81)
	tick(0.3, [near, far])
	expect(near.calls == 1 and far.calls == 1, "local pierce threshold is configurable")
	arena.weapons.flash.settings.pierce_threshold = 0.9
	fresh()
	arena.player.position = Vector3(-5, .55, -1)
	near = fake(31, Vector3(-5, 0, -2))
	far = fake(32, Vector3(-5, 0, -8))
	fire(1, Vector3(-5, 0, -15))
	tick(0.5, [near, far])
	expect(near.calls == 1 and far.calls == 0 and arena.weapons.flash.pulses.is_empty(), "pierce hits before cover and stops without reaching behind wall")
	expect(is_equal_approx(arena.weapons.flash.end_point.z, -3), "pulse ends at actual solid cover")
	expect(is_equal_approx(near.contexts[0].segment_end.z, -3), "mechanism segment is clipped to wall, never raw end beyond cover")
	fresh()
	near = fake(41, Vector3(0, 0, -6))
	fire(1)
	var start: Vector3 = arena.weapons.flash.pulses[0].pos
	tick(1, [near], 0)
	expect(arena.weapons.flash.pulses[0].pos == start and near.calls == 0, "inspection freeze stops piercing flight/actions")
	tick(0.5, [near], .5 * .18)
	expect(is_equal_approx(arena.weapons.flash.pulses[0].pos.z, -3.78), "charged flight still follows slowed world delta")
	fresh()
	var yellow1: Node3D = arena.director.spawn(&"yellow", Vector3(0, 0, -4))
	var yellow2: Node3D = arena.director.spawn(&"yellow", Vector3(0, 0, -8))
	fire(1)
	tick(0.4, [yellow2, yellow1])
	expect(yellow1.core_broken and yellow2.core_broken and yellow1.health == 0 and yellow2.health == 0, "actual exposed yellow cores finish normally along charged pulse")
	fresh()
	var simple: Node3D = arena.director.spawn(&"yellow", Vector3(0, 0, -4))
	fire(0)
	tick(.2, [simple])
	expect(simple.core_broken, "quick shots still finish simple exposed yellow cores")
	fresh()
	var cues: Array[StringName] = []
	arena.weapons.combat_event.connect(func(kind, _p, _s): cues.append(kind))
	arena.weapons.select_tool(2)
	arena.player.set_visual_tool(2)
	arena.weapons.handle_event(button(true), arena.player, Vector3(0, 0, -12))
	tick(.9 * .9 + .001, [], 0)
	tick(.1, [], 0)
	expect(cues.count(&"flash_ready") == 1 and arena.weapons.presentation.pierce_ready, "ready cue fires once and aperture locks on")
	expect(arena.weapons.flash.pulses.is_empty() and arena.weapons.presentation.mesh.get_aabb().size.length() < .9, "ready feedback remains on aperture with no forward beam")
	arena.weapons.handle_event(button(false), arena.player, Vector3(0, 0, -12))
	expect(cues.count(&"flash_pierce") == 1 and cues.count(&"flash_fire") == 1, "charged release has semantic fire and pierce feedback")
	# Display smoothing preserves raw data, endpoints, turns and cover stops.
	var raw: Array[Vector3] = [Vector3(-2, 0, -8), Vector3(-1.7, 0, -7.98), Vector3(-1.4, 0, -8.03), Vector3(-1.1, 0, -8), Vector3(-1.1, 0, -7)]
	var original: Array[Vector3] = raw.duplicate()
	var shown := Presentation.stroke_display(raw)
	expect(raw == original and shown[0] == raw[0] and shown[-1] == raw[-1], "smoothing copies raw path and fixes both endpoints")
	expect(shown[3] == raw[3], "intentional right-angle corner is pinned")
	expect(shown[1] != raw[1] or shown[2] != raw[2], "mild sampling jitter is actually reduced")
	var bounded := true
	for i in range(raw.size()): bounded = bounded and shown[i].distance_to(raw[i]) <= .040001
	expect(bounded, "display displacement is capped at 0.04m")
	var wall: Array[Vector3] = [Vector3(-5, 0, -2), Vector3(-5.05, 0, -2.5), Vector3(-5, 0, -3)]
	var wall_display := Presentation.stroke_display(wall, arena.weapons.cover)
	expect(wall_display[1] == wall[1] and wall_display[-1] == wall[-1], "solid-cover entry and adjacent sample remain exact")
	var outcomes: Array = []
	for smooth in [false, true]:
		fresh()
		var blue: Node3D = arena.director.spawn(&"blue", Vector3(0, 0, -7))
		arena.weapons.ring.settings = arena.weapons.ring.settings.duplicate()
		arena.weapons.ring.settings.display_smoothing = smooth
		arena.weapons.select_tool(1)
		arena.weapons.handle_event(button(true), arena.player, Vector3(-2, 0, -7))
		for point in [Vector3(-1, 0, -6.98), Vector3(0, 0, -7.03), Vector3(1, 0, -7)]:
			var motion := InputEventMouseMotion.new()
			arena.weapons.handle_event(motion, arena.player, point)
		var sampled: Array[Vector3] = arena.weapons.ring.preview_points.duplicate()
		arena.weapons.rebuild_visuals(arena.player)
		expect(sampled == arena.weapons.ring.preview_points, "render does not mutate raw sampled cutter path")
		arena.weapons.handle_event(button(false), arena.player, Vector3(2, 0, -7))
		tick(.8, [blue])
		outcomes.append([blue.health, blue.cable_cut])
	expect(outcomes[0] == outcomes[1] and outcomes[0][1], "actual drawn stroke has identical successful cut outcome with smoothing on/off")
	fresh()
	var custom := fake(51, Vector3(0, 0, -4))
	custom.pattern = true
	arena.weapons.ring._sweep_segment(Vector3(-1, 0, -4), Vector3(1, 0, -4), [custom])
	arena.weapons.ring._sweep_segment(Vector3(1, 0, -4), Vector3(-1, 0, -4), [custom])
	expect(custom.progress == 2 and custom.health == 964 and custom.contexts[1].already_hit, "custom pattern receives later ring segments without duplicate body damage")
	fresh()
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
