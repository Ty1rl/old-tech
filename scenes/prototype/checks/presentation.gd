extends SceneTree

var arena: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event

func fresh(location: Vector3) -> Node3D:
	arena.reset_arena()
	arena.director.clear()
	return arena.director.spawn(&"warden", location)

func flash(aim: Vector3) -> void:
	arena.weapons.select_tool(2)
	arena.weapons.handle_event(mouse(true), arena.player, aim)
	arena.weapons.step(0.9, arena.player, aim, arena.director.enemies, 0)
	arena.weapons.handle_event(mouse(false), arena.player, aim)
	arena.weapons.step(0.3, arena.player, aim, arena.director.enemies)

func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	var guard := fresh(Vector3(0, 0, -4))
	var uncut: Dictionary = arena.capture_state()
	var cable: Array = guard.cable_world_points()
	var cable_direction: Vector3 = (cable[2] - cable[1]).normalized()
	arena.weapons.select_tool(1)
	arena.weapons.handle_event(mouse(true), arena.player, cable[1] - cable_direction * 0.4)
	arena.weapons.handle_event(mouse(false), arena.player, cable[2] + cable_direction * 0.4)
	arena.weapons.step(1.0, arena.player, Vector3.ZERO, arena.director.enemies)
	expect(guard.cable_cut and guard.health < guard.max_health - 60, "Actual cutter severs protruding cable for substantial damage")
	expect(guard.is_core_exposed(), "Actual cut opens yellow core")
	var cues: int = arena.feedback.accepted_cues
	var cut: Dictionary = arena.capture_state()
	arena._restore_world(uncut, arena.player.slow_charge)
	expect(not guard.cable_cut and not guard.is_core_exposed(), "Rewind restores cable and shield")
	expect(arena.feedback.accepted_cues == cues, "Restoring mechanisms never replays hit or break cues")
	arena._restore_world(cut, arena.player.slow_charge)
	flash(guard.core_world_position())
	expect(guard.core_broken and guard.health <= 0, "Actual cut then charged aimed flash kills guard")

	guard = fresh(Vector3(0, 0, -4))
	cable = guard.cable_world_points()
	arena.weapons.select_tool(1)
	arena.weapons.handle_event(mouse(true), arena.player, Vector3(0, 0, -2))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	arena.weapons.handle_event(motion, arena.player, guard.position)
	arena.weapons.handle_event(motion, arena.player, cable[2])
	arena.weapons.handle_event(mouse(false), arena.player, cable[2] + Vector3(-1, 0, 0))
	arena.weapons.step(1, arena.player, Vector3.ZERO, arena.director.enemies)
	expect(guard.cable_cut, "A stroke that hits chassis first can still cut its cable later")
	expect(is_equal_approx(guard.max_health - guard.health, 36.0 * 0.35 + 65.0),
		"Body-first cable stroke deals one chassis hit plus one cable bonus")

	guard = fresh(Vector3(0, 0, -3))
	arena.weapons.select_tool(3)
	arena.weapons.handle_event(mouse(true), arena.player, guard.position)
	for tick in range(180):
		arena.weapons.step(1.0 / 60, arena.player, guard.position, arena.director.enemies)
		arena.director.step(1.0 / 60, arena.player)
		if guard.is_core_exposed():
			break
	arena.weapons.handle_event(mouse(false), arena.player, guard.position)
	expect(guard.is_core_exposed() and not guard.cable_cut, "Actual cone opens moving guard through heat")
	expect(guard.position.distance_to(arena.player.position) < 6, "Heavy guard stays within useful cone range despite shove")
	var before: float = guard.health
	flash(guard.core_world_position())
	expect(guard.core_broken and before - guard.health >= minf(before, 180), "Actual heat then charged flash severely damages exposed core")

	fresh(Vector3(0, 0, -5))
	for tick in range(30):
		arena.player.position.x = tick * 0.1
		arena.history.record(0.05, arena.capture_state)
	arena.weapons.select_tool(4)
	arena._begin_inspection()
	var present: Vector3 = arena.player.position
	cues = arena.feedback.accepted_cues
	arena._seek_inspection(0.75)
	var chosen: Vector3 = arena._preview.player.position
	expect(arena.scrub_view.active and arena.player.position.is_equal_approx(present), "Scrub begins from displayed pose instead of jumping immediately")
	arena._process(0.07)
	expect(arena.player.position.x < present.x and arena.player.position.x > chosen.x, "Scrub eases toward recorded pose")
	arena._seek_inspection(0.25)
	arena._process(0.03)
	arena._finish_inspection(true)
	expect(not arena.scrub_view.active and arena.player.position.x > chosen.x, "Fast scrub reversal commits exact chosen state")
	expect(arena.feedback.accepted_cues == cues, "Scrub motion and commit create no historical hit sounds")
	arena.feedback.cue(&"hit", arena.player.position, 1)
	expect(arena.feedback.accepted_cues == cues + 1, "Live feedback is immediately available after leaving preview")
	var spawn := InputEventKey.new()
	spawn.physical_keycode = KEY_F9
	spawn.pressed = true
	arena._unhandled_input(spawn)
	expect(arena.director.enemies.size() == 1 and arena.director.enemies[0].kind == &"warden", "F9 starts a clean guard showcase")

	fresh(Vector3(0, 0, -4))
	# Aim a shot through the solid wall toward an opened core behind it.
	guard = arena.director.enemies[0]
	guard.position = Vector3(-8, 0, -4)
	guard.cable_cut = true
	arena.player.position = Vector3(-2, 0.55, -4)
	before = guard.health
	flash(guard.core_world_position())
	expect(guard.health == before and not guard.core_broken, "Cover blocks weak-point shots as well as ordinary damage")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
