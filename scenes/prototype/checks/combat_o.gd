extends SceneTree
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const Visual = preload("res://scenes/prototype/pattern_visual.gd")
const Flow = preload("res://scenes/prototype/flow.gd")
var checks := 0
var failures: Array[String] = []
var arena: Node3D
var events: Array[Dictionary] = []
var metrics: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func cut(enemy: Node3D, index: int, already := false) -> void:
	var points: Array[Vector3] = enemy.cable_world_points()
	enemy.receive_attack(&"ring", 36, points[index * 2], {"segment_start": points[index * 2],
		"segment_end": points[index * 2 + 1], "radius": .01, "already_hit": already})
func button(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event
func fresh() -> void:
	arena.reset_arena()
	arena.director.clear()
	arena.cover.set_rectangles([])
	arena.player.position = Vector3(0, .55, 6)
	arena.time_controller.auto_advance = false
	arena.time_controller.begin_attempt()
	events.clear()
func tick(dt: float, aim := Vector3.ZERO, moving := true) -> void:
	arena.weapons.step(dt, arena.player, aim, arena.director.enemies, dt)
	arena.director.step(dt, arena.player if moving else null)
func arc(center: Vector3, start: float, finish: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(41):
		var angle := lerpf(start, finish, float(i) / 40)
		result.append(Vector3(center.x + cos(angle) * 2.12, 0, center.z + sin(angle) * 2.12))
	return result
func zigzag_path(target: CombatPatternEnemy, first: int, count: int, moving: bool) -> Array[Vector3]:
	var points := target.cable_world_points()
	var result: Array[Vector3] = []
	for i in range(first * 2, (first + count) * 2):
		result.append(points[i] + (Vector3.BACK * .35 if moving else Vector3.ZERO))
	return result
func launch(path: Array[Vector3], dt: float, moving := true) -> void:
	var weapon: WeaponController = arena.weapons
	weapon.select_tool(1)
	weapon.handle_event(button(true), arena.player, path[0])
	for point in path:
		var motion := InputEventMouseMotion.new()
		weapon.handle_event(motion, arena.player, point)
	weapon.handle_event(button(false), arena.player, path[-1])
	var frames := 0
	while weapon.ring.flight_phase != "idle" and frames < int(3 / dt):
		tick(dt, path[-1], moving)
		frames += 1
	expect(weapon.ring.flight_phase == "idle", "Actual cutter finishes arc, stroke and harmless return")
func shot(aim: Vector3, charged: bool, dt: float, moving := true) -> void:
	var weapon: WeaponController = arena.weapons
	weapon.select_tool(2)
	weapon.handle_event(button(true), arena.player, aim)
	weapon.step(.95 if charged else .01, arena.player, aim, arena.director.enemies, 0)
	weapon.handle_event(button(false), arena.player, aim)
	for i in range(int(.8 / dt)): tick(dt, aim, moving)
func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for item in value:
			if not values_only(item): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true
func run() -> void:
	var enemy := PatternEnemy.new()
	root.add_child(enemy)
	for mode: StringName in [&"loop", &"zigzag"]:
		enemy.configure(mode, Vector3.ZERO, 1)
		cut(enemy, 0)
		enemy.step_enemy(.5, null)
		var deadline: float = enemy.window_timer
		cut(enemy, 1)
		expect(enemy.link_mask == 3, "Fresh second launch retains first link: " + String(mode))
		expect(is_equal_approx(enemy.window_timer, deadline), "Second launch does not renew fixed deadline: " + String(mode))
		cut(enemy, 1)
		expect(is_equal_approx(enemy.window_timer, deadline), "Repeated link never renews deadline")
		expect(enemy.pattern_visual.link_sections[0].visible and enemy.pattern_visual.cut_ends[0].visible, "Partial cut leaves support and severed cable ends visible")
		var snap: Dictionary = enemy.capture_state()
		enemy.step_enemy(deadline + .01, null)
		expect(enemy.link_mask == 0 and enemy.window_timer == 0, "Slow attempt regenerates exactly once")
		enemy.step_enemy(1, null)
		expect(enemy.link_mask == 0 and enemy.pattern_visual.link_sections[0].visible, "Idle state cannot oscillate missing supports")
		enemy.restore_state(snap)
		expect(enemy.link_mask == 3 and enemy.window_timer == deadline, "Rewind retains partial links and original remaining deadline")
		for i in range(2, enemy.cable_world_points().size() / 2): cut(enemy, i, true)
		enemy.step_enemy(30, null)
		expect(enemy.pattern_open, "Successful multi-launch opening is permanent")
		enemy.configure(mode, Vector3.ZERO, 1)
		var points: Array[Vector3] = enemy.cable_world_points()
		var midpoint := points[0].lerp(points[1], .5)
		var tangent := (points[1] - points[0]).normalized()
		var offset := tangent.cross(Vector3.UP) * .25
		enemy.receive_attack(&"ring", 36, midpoint, {"segment_start": midpoint + offset - tangent * .15,
			"segment_end": midpoint + offset + tangent * .15, "radius": .01})
		expect(enemy.link_mask == 1, "Visible wider link accepts a reasonable quarter-meter near cut")
	enemy.free()
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	root.get_node("GameState").resume()
	arena.director.enemy_event.connect(func(kind, event, point, strength):
		events.append({"kind":kind, "event":event, "point":point, "strength":strength}))
	# Actual raw input and traveling cutter, including moving/turning target and
	# a human-sized gap between two independent launches. No path retargeting.
	for dt: float in [1.0 / 30, 1.0 / 60, 1.0 / 240]:
		for moving: bool in [false, true]:
			for mode: StringName in [&"loop", &"zigzag"]:
				fresh()
				var target: CombatPatternEnemy = arena.director.spawn(mode, Vector3.ZERO)
				launch(arc(target.position + (Vector3.BACK * .35 if moving else Vector3.ZERO), 0, TAU) if mode == &"loop" else zigzag_path(target, 0, 3, moving), dt, moving)
				expect(target.pattern_open, "One real stroke opens %s; moving=%s dt=%s" % [mode, moving, dt])
				fresh()
				target = arena.director.spawn(mode, Vector3.ZERO)
				launch(arc(target.position + (Vector3.BACK * .35 if moving else Vector3.ZERO), 0, PI) if mode == &"loop" else zigzag_path(target, 0, 2, moving), dt, moving)
				expect(target.link_mask != 0 and not target.pattern_open, "First real partial stroke leaves progress")
				for i in range(int(.8 / dt)): tick(dt, Vector3.ZERO, moving)
				var first_position := target.position
				launch(arc(target.position + (Vector3.BACK * .35 if moving else Vector3.ZERO), PI, TAU) if mode == &"loop" else zigzag_path(target, 2, 1, moving), dt, moving)
				expect(target.pattern_open, "Two real launches open %s; moving=%s dt=%s" % [mode, moving, dt])
				expect(arena.equipment.remaining(&"ring") == arena.equipment.capacity(&"ring") - 2, "Two independent launches spend exactly two condition units")
				metrics["two_cut_%s_%s_%s" % [mode, moving, dt]] = {"open":target.pattern_open,"second_launch_motion":target.position.distance_to(first_position)}
	# The two quick square sockets and exposed round charged core use real shots.
	fresh()
	var pair: CombatPatternEnemy = arena.director.spawn(&"sequence_boss", Vector3.ZERO)
	expect(pair.valve_world_position(0).distance_to(pair.valve_world_position(1)) >= 2.19, "A/B centers are physically separated")
	expect(pair.pattern_visual.valves[0].mesh is BoxMesh and pair.pattern_visual.core.mesh is SphereMesh, "Quick socket and charged core have different silhouettes")
	shot(pair.core_world_position(), false, 1.0 / 60, false)
	expect(pair.pair_progress == 1 and pair.pattern_visual.valve_gates[1].position.y > pair.pattern_visual.valve_gates[0].position.y, "Actual quick A opens the B shutter")
	shot(pair.core_world_position(), false, 1.0 / 60, false)
	expect(pair.pattern_open and pair.phase == 0, "Actual quick B opens steady central finisher")
	shot(pair.core_world_position(), true, 1.0 / 60, false)
	expect(pair.phase == 1, "Actual charged exposed-core hit advances boss")
	# Curved blue packs and yellow files remain moving opportunities with modest
	# variance, no snapping, cover crossings or forced surrounding of the player.
	for seed in range(3):
		fresh()
		var blues: Array = arena.director.spawn_formation(&"curve", [&"blue", &"blue", &"blue"], arena.player, seed * 4)
		for i in range(66): arena.director.step(1.0 / 60, arena.player)
		var raw: Array[Vector3] = []
		for node in blues:
			var cable: Array[Vector3] = node.cable_world_points()
			raw.append(cable[0].lerp(cable[1], .5).move_toward(arena.player.position, .35))
		raw.sort_custom(func(a: Vector3, b: Vector3): return a.x < b.x)
		launch(raw, 1.0 / 60)
		var cuts: int = 3 - arena.director.enemies.size()
		expect(cuts >= 2, "Real moving curved pack supports multi-cut, seed " + str(seed))
		metrics["blue_cuts_" + str(seed)] = cuts
		fresh()
		var yellows: Array = arena.director.spawn_formation(&"line", [&"yellow", &"yellow", &"yellow"], arena.player, seed * 4)
		for i in range(75): arena.director.step(1.0 / 60, arena.player)
		var before: Vector3 = yellows[0].position
		arena.director.step(1.0 / 60, arena.player)
		expect(yellows[0].position.distance_to(before) < .05, "Cohesion has no position snap")
		shot(yellows[-1].core_world_position(), true, 1.0 / 60)
		var kills: int = 3 - arena.director.enemies.size()
		expect(kills == 3, "Charged real pulse pierces moving varied file, seed " + str(seed))
		metrics["yellow_kills_" + str(seed)] = kills
	# A stroke starting in front of a wall must stop there; a piercing flash also
	# cannot reach the unchanged target behind it.
	fresh()
	arena.cover.set_rectangles([Rect2(-4, -3.5, 8, .5)])
	var behind: CombatEnemy = arena.director.spawn(&"blue", Vector3(0, 0, -6))
	launch([Vector3(0,0,0), Vector3(0,0,-8)], 1.0 / 60, false)
	expect(behind.health == behind.max_health and not behind.cable_cut, "Wall clips actual cutter before target")
	shot(behind.position, true, 1.0 / 60, false)
	expect(behind.health == behind.max_health, "Piercing never bypasses opaque cover")
	fresh()
	arena.cover.set_rectangles([Rect2(-2, -3, 4, 1)])
	var wide: CombatPatternEnemy = arena.director.spawn(&"loop", Vector3(0,0,-8))
	wide.apply_control(Vector3.BACK, 20, .3)
	var all_clear := true
	for i in range(180):
		arena.director.step(1.0 / 60, arena.player)
		all_clear = all_clear and not arena.cover.clip_segment(wide.position, wide.position, wide.movement_radius() - .01).blocked
	expect(all_clear, "Moving/shoved wide supports remain clear of walls through ordinary steering")
	for kind: StringName in [&"ranged", &"sequence_boss"]:
		fresh()
		var tracker: CombatEnemy = arena.director.spawn(kind, Vector3(0,0,-8))
		tracker.facing = Vector3.RIGHT
		arena.director.step(.05, arena.player)
		expect(tracker.attack_phase == &"approach" and tracker.facing.angle_to(Vector3.RIGHT) <= .121 and tracker.facing.angle_to(Vector3.RIGHT) > 0, "Shared approach tracking has gentle turn lag: " + String(kind))
		fresh()
		arena.player.position = Vector3.ZERO
		var shooter: CombatEnemy = arena.director.spawn(kind, Vector3(0, 0, -8))
		arena.director.step(.01, arena.player)
		var locked: Vector3 = shooter.ranged_aim
		var warning: Dictionary = arena.director.capture_state()
		var event_count := events.size()
		arena.player.position.x = 4
		arena.director.step(.5, arena.player)
		expect(shooter.ranged_aim == locked, "Shared warning remains locked during a dodge: " + String(kind))
		var frozen: Dictionary = arena.director.capture_state()
		arena.director.step(0, arena.player)
		expect(arena.director.capture_state() == frozen, "Freeze holds warning/state exactly")
		arena.director.step(.61 if kind == &"sequence_boss" else .46, arena.player)
		if kind == &"sequence_boss": arena.director.step(.19, arena.player)
		expect(shooter.attack_phase == &"recover", "Release commits recovery before any hit")
		expect(arena.director.projectiles.size() == (3 if kind == &"sequence_boss" else 1), "One actual release creates exactly the promised shot lanes")
		expect(events.filter(func(e): return e.event == &"warning").size() == 1 and events.filter(func(e): return e.event == &"attack").size() == 1, "One archetype warning and attack event per actual transition")
		var flying: Dictionary = arena.director.capture_state()
		arena.director.step(.1, arena.player)
		arena.director.restore_state(flying)
		expect(arena.director.capture_state() == flying and values_only(flying), "Rewind retains exact value-only projectile and pattern state")
		event_count = events.size()
		arena.director.restore_state(warning)
		expect(events.size() == event_count and event_count >= 2, "Snapshot restore never replays enemy barks")
	fresh()
	var hurt: CombatEnemy = arena.director.spawn(&"target", Vector3(0,0,-7))
	var living: Dictionary = arena.director.capture_state()
	for i in range(20): hurt.hit(1, hurt.position)
	expect(events.size() == 1 and events[0].event == &"hurt", "Rapid real contacts produce a bounded hurt bark")
	hurt.hit(1000, hurt.position)
	hurt.hit(1000, hurt.position)
	expect(events.size() == 2 and events[-1].event == &"death", "A killing transition emits death exactly once")
	arena.director.restore_state(living)
	expect(events.size() == 2, "Resurrection through replay emits no historical hurt/death")
	arena.director.enemies[0].hit(1, Vector3.ZERO)
	expect(events.size() == 3 and events[-1].kind == &"target", "Restored actors remain connected to one semantic relay")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks,"failures":failures,"metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
