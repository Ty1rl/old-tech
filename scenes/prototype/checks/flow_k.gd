extends SceneTree

const Flow = preload("res://scenes/prototype/flow.gd")
var arena: Node3D
var checks := 0
var failures: Array[String] = []
var peak_payload_bytes := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func fresh() -> void:
	arena.reset_arena()
	arena.director.clear()
	arena.player.position = Vector3(0, .55, 0)


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
	var director: Node3D = arena.director
	fresh()
	for formation: StringName in [&"curve", &"line", &"cluster", &"mixed"]:
		fresh()
		var kind: StringName = {&"curve":&"blue", &"line":&"yellow", &"cluster":&"orange"}.get(formation, &"side_guard")
		var nodes: Array = director.spawn_formation(formation, [kind, kind, kind, kind, kind], arena.player, 0)
		expect(nodes.size() == 5, "five formation members " + String(formation))
		var safe := true
		var open_lane := true
		for node in nodes:
			safe = safe and Flow.safe(node.position, node.radius, arena.player.position, director.cover)
			open_lane = open_lane and node.position.z < -5
		expect(safe and open_lane, "spawn clear of player and opaque cover, rear escape lane " + String(formation))
		var start: Vector3 = nodes[0].position
		director.step(.4, arena.player)
		expect(nodes[0].position.is_equal_approx(start), "warning allows a visible preparation interval " + String(formation))
		expect(director._arrival_mesh.get_surface_count() == 1, "arrival warning geometry present " + String(formation))
		if formation == &"line":
			var width := 0.0
			for node in nodes: width = maxf(width, absf(node.position.x))
			expect(width < .04 and nodes[0].position.distance_to(nodes[-1].position) > 7, "yellow loose radial line is pierceable")
		elif formation == &"curve":
			expect(nodes[0].position.distance_to(nodes[-1].position) > 6 and absf(nodes[0].position.z - nodes[2].position.z) > .3, "blue curve is wide and naturally bowed")
		elif formation == &"cluster":
			expect(nodes[0].position.distance_to(nodes[-1].position) < 5, "orange pack fits a compact cone opportunity")
		director.step(.6, arena.player)
		expect(nodes[0].position.distance_to(start) > .01 and director._arrival_mesh.get_surface_count() == 0, "arrival resumes native approach and clears warning " + String(formation))
	fresh()
	var first: Array = director.spawn_formation(&"curve", [&"blue", &"blue", &"blue"], arena.player)
	var second: Array = director.spawn_formation(&"line", [&"yellow", &"yellow", &"yellow"], arena.player)
	expect(first[1].position.z < -5 and second[0].position.x > 5, "successive arrivals alternate entrances")
	var snap: Dictionary = director.capture_state()
	expect(values_only(snap), "formation snapshot has no nodes, resources or callables")
	var warning: float = director.flow.cohorts[0].warning
	director.step(0, arena.player)
	expect(director.flow.cohorts[0].warning == warning, "frozen world leaves arrival state fixed")
	director.step(.1 * .18, arena.player)
	expect(is_equal_approx(director.flow.cohorts[0].warning, warning - .018), "arrival uses slowed world delta")
	director.step(2, arena.player)
	director.restore_state(snap)
	expect(is_equal_approx(director.flow.cohorts[0].warning, warning) and director._arrival_mesh.get_surface_count() == 1, "rewind restores pending arrivals and warnings")
	expect(director.capture_state().flow == snap.flow, "formation snapshot round-trips exactly")
	first = director.enemies.slice(0, 3)
	director.step(1.0, arena.player)
	first[0].position = arena.player.position + Vector3(0, 0, -2)
	first[0].position.y = 0
	director.step(.05, arena.player)
	expect(director.flow.cohorts.size() == 1, "near-contact cohort breaks up without holding native attacks")
	fresh()
	var stunned: Array = director.spawn_formation(&"line", [&"yellow", &"yellow"], arena.player)
	director.step(1, arena.player)
	stunned[0].apply_control(Vector3.RIGHT, 1, .8)
	var stagger: float = stunned[0].stagger_timer
	director.step(.1, arena.player)
	expect(director.flow.cohorts.is_empty() and stunned[0].stagger_timer < stagger, "control releases cohesion and native stagger still advances")
	fresh()
	var rushing: Array = director.spawn_formation(&"line", [&"yellow", &"yellow"], arena.player)
	var arrival_snapshot: Dictionary = director.capture_state()
	rushing[0].position = Vector3(0, 0, -2.5)
	director.step(0, arena.player)
	expect(director.capture_state().flow == arrival_snapshot.flow, "frozen world cannot break even a near-contact warning")
	director.step(.1, arena.player)
	expect(director.flow.cohorts.is_empty() and rushing[0].position.z > -2.5, "rushing a warning releases its hold and native chase immediately")
	fresh()
	# Test room-edge placements with occupied cover and deterministic seeds.
	for pos in [Vector3(17, 0, 17), Vector3(-17, 0, -17), Vector3(-5, 0, -1), Vector3(5, 0, 2)]:
		arena.player.position = pos
		var f: RefCounted = Flow.new()
		var slots: Array = f.layout(&"mixed", [&"blue", &"orange", &"yellow"], pos, director.cover, 7, [])
		expect(slots.size() == 3, "valid group found near room edge/cover " + str(pos))
		var safe := true
		for slot: Dictionary in slots: safe = safe and Flow.safe(slot.position, slot.radius, pos, director.cover)
		expect(safe, "room edge placement remains collision-safe " + str(pos))
		expect(slots == f.layout(&"mixed", [&"blue", &"orange", &"yellow"], pos, director.cover, 7, []), "formation layout deterministic for seed/player/cover")
	fresh()
	director.start_flow(arena.player, 3)
	expect(director.enemies.size() == 3 and director.flow.pressure_active, "bounded pressure begins with one visible blue cohort")
	director.step(4, arena.player)
	expect(director.enemies.size() == 3 and director.flow.cohorts.is_empty(), "first burst has a finite cohesion window then recovery")
	var pressure_snap: Dictionary = director.capture_state()
	director.step(4.05, arena.player)
	expect(director.enemies.size() == 6, "second pressure burst follows recovery")
	director.restore_state(pressure_snap)
	expect(director.enemies.size() == 3 and director.flow.pressure_index == 1, "pressure rewind does not duplicate next burst")
	director.step(4.05, arena.player)
	director.step(8, arena.player)
	expect(director.flow.pressure_index == 3 and not director.flow.pressure_active, "finite three-burst schedule stops spawning")
	var count: int = director.enemies.size()
	arena.time_controller.settings = arena.time_controller.settings.duplicate()
	arena.time_controller.settings.capacity = 10000
	arena.time_controller.begin_attempt()
	director.step(20, arena.player)
	expect(director.enemies.size() <= count, "no endless reinforcements after finite pressure")
	fresh()
	director.start_flow(arena.player)
	arena.time_controller.settings = arena.time_controller.settings.duplicate()
	arena.time_controller.settings.charges_per_attempt = 0
	arena.time_controller.begin_attempt()
	arena.time_controller.force_depletion()
	director.step(20, arena.player)
	expect(not director.flow.pressure_active and director.enemies.size() == 3, "defeat cancels future pressure bursts")
	fresh()
	director.start_flow(arena.player)
	arena.time_controller.settings = arena.time_controller.settings.duplicate()
	arena.time_controller.settings.capacity = 10000
	arena.time_controller.begin_attempt()
	director.step(30, arena.player)
	var overdue_count: int = director.enemies.size()
	director.step(.01, arena.player)
	expect(director.enemies.size() == overdue_count and director.flow.pressure_index == 2, "large world step cannot dump overdue bursts without recovery")
	fresh()
	for i in range(40): director.spawn(&"target", Vector3(0, 0, -15))
	var overflow: Array = director.spawn_formation(&"curve", [&"blue", &"blue"], arena.player)
	expect(director.enemies.size() == 32 and overflow.is_empty(), "formations preserve director live cap")
	director.clear()
	expect(director.flow.cohorts.is_empty() and not director.flow.pressure_active and director._arrival_mesh.get_surface_count() == 0, "clear removes formation/timer/warning state")
	# Exercise the existing history payload cap with actual worst-case local
	# formation state and all eight piercing pulses carrying a full hit ledger.
	fresh()
	var ids: Array[int] = []
	for group in range(8):
		var members: Array[Node3D] = []
		for i in range(4):
			var node: Node3D = director.spawn(&"front_guard", Vector3(float(group - 4) * 2, 0, -8 - float(i) * 2))
			members.append(node)
			ids.append(node.combat_id())
		director.flow.add(&"mixed", members)
	for i in range(8):
		arena.weapons.flash.pulses.append({"muzzle":Vector3(0, 1.2, 0), "pos":Vector3.ZERO, "dir":Vector2.UP,
			"speed":42.0, "remaining_range":35.0, "radius":.35, "damage":100.0, "charge":1.0, "piercing":true, "hit_ids":ids.duplicate()})
	var full_state: Dictionary = arena.capture_state()
	peak_payload_bytes = var_to_bytes(full_state).size()
	expect(director.flow.cohorts.size() == 8 and values_only(full_state), "max cohort/pulse state remains value-only")
	expect(peak_payload_bytes < arena.history.MAX_PAYLOAD_BYTES, "32 guards, 8 cohorts and 8 full pulse ledgers fit the existing history payload cap")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures, "peak_payload_bytes":peak_payload_bytes}))
	quit(0 if failures.is_empty() else 1)
