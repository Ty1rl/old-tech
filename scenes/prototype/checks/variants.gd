extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")
var arena: Node3D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)


func fresh(kind: StringName, point: Vector3 = Vector3(0, 0, -4)) -> Node3D:
	arena.reset_arena()
	arena.director.clear()
	return arena.director.spawn(kind, point)


func cut(enemy: Node3D) -> Dictionary:
	var points: Array = enemy.cable_world_points()
	var middle: Vector3 = (points[0] + points[-1]) * 0.5
	var across: Vector3 = enemy.facing
	if enemy.part_layout() == &"front": across = Vector3(across.z, 0, -across.x)
	return enemy.receive_attack(&"ring", 36, middle, {"segment_start": middle - across, "segment_end": middle + across, "radius": 0.1})


func shoot(enemy: Node3D) -> Dictionary:
	return enemy.receive_attack(&"beam", 30, enemy.position, {
		"segment_start": Vector3.ZERO, "segment_end": enemy.core_world_position(), "radius": 0.35, "charge": 0.0})


func heat(enemy: Node3D) -> void:
	for tick in range(80):
		enemy.receive_attack(&"cone", 16.0 / 60, enemy.position, {"dt": 1.0 / 60})
		enemy.step_enemy(1.0 / 60, null)
		if enemy.plate_broken: break


func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	arena._unhandled_input(event)


func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event


func launch_through(enemies: Array) -> void:
	arena.weapons.select_tool(1)
	var path: Array[Vector3] = []
	for enemy in enemies:
		var cable: Array = enemy.cable_world_points()
		path.append((cable[0] + cable[-1]) * 0.5)
	var direction := (path[1] - path[0]).normalized()
	arena.weapons.handle_event(mouse(true), arena.player, path[0] - direction)
	for point in path:
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		arena.weapons.handle_event(motion, arena.player, point)
	arena.weapons.handle_event(mouse(false), arena.player, path[-1] + direction)
	arena.weapons.step(0.8, arena.player, path[-1], arena.director.enemies)


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	for kind: StringName in [&"blue", &"yellow", &"orange", &"side_guard", &"front_guard"]:
		for tool: StringName in [&"ring", &"beam", &"cone"]:
			var enemy := fresh(kind)
			var before: float = enemy.health
			var result: Dictionary = enemy.receive_attack(tool, 30, enemy.position)
			expect(enemy.health < before and enemy.health > 0 and result.armored, "Body hit progresses inefficiently: " + String(kind) + "/" + String(tool))
			for tick in range(180):
				enemy.receive_attack(tool, 30, enemy.position)
				if enemy.health <= 0: break
			expect(enemy.health <= 0, "Every tool can eventually kill: " + String(kind) + "/" + String(tool))
	var enemy := fresh(&"blue")
	expect(cut(enemy).killed and enemy.cable_cut, "Blue connector cut kills immediately")
	enemy = fresh(&"yellow")
	expect(shoot(enemy).killed and enemy.core_broken, "Quick accurate yellow shot kills exposed yellow-only target")
	enemy = fresh(&"orange")
	heat(enemy)
	expect(enemy.health <= 0 and enemy.plate_broken, "Sustained heat destroys orange-only enemy")
	for kind: StringName in [&"side_guard", &"front_guard"]:
		for route in ["cut", "heat"]:
			enemy = fresh(kind)
			var intact: Dictionary = enemy.capture_state()
			if route == "cut": cut(enemy)
			else: heat(enemy)
			expect(enemy.health > 0 and enemy.is_core_exposed(), "Opening exposes a surviving core: " + String(kind) + "/" + route)
			expect(shoot(enemy).killed, "Quick yellow cleanup kills opened enemy: " + String(kind) + "/" + route)
			enemy.restore_state(intact)
			expect(not enemy.is_core_exposed() and not enemy.cable_cut and not enemy.plate_broken, "Rewind restores intact parts: " + String(kind) + "/" + route)
	for kind: StringName in [&"orange", &"side_guard", &"front_guard"]:
		enemy = fresh(kind)
		arena.weapons.select_tool(3)
		arena.weapons.handle_event(mouse(true), arena.player, enemy.position)
		for tick in range(150):
			arena.weapons.step(1.0 / 60, arena.player, enemy.position, arena.director.enemies)
			arena.director.step(1.0 / 60, arena.player)
			if enemy.plate_broken: break
		arena.weapons.handle_event(mouse(false), arena.player, enemy.position)
		expect(enemy.plate_broken, "Real cone heats moving braced carrier without ejecting it from range: " + String(kind))
		if kind != &"orange":
			arena.weapons.select_tool(2)
			arena.weapons.handle_event(mouse(true), arena.player, enemy.core_world_position())
			arena.weapons.step(0.03, arena.player, enemy.core_world_position(), arena.director.enemies, 0)
			arena.weapons.handle_event(mouse(false), arena.player, enemy.core_world_position())
			arena.weapons.step(0.2, arena.player, enemy.core_world_position(), arena.director.enemies)
			expect(enemy.health <= 0, "Real quick flash cleans up heated core: " + String(kind))
	enemy = fresh(&"blue")
	for shot in range(10): enemy.receive_attack(&"beam", 100, enemy.position)
	expect(enemy.health > enemy.max_health * 0.5, "Ten maximum body shots do not efficiently remove a blue target")

	fresh(&"target")
	arena.director.clear()
	var pack: Array = []
	for point in [Vector3(-3, 0, -8), Vector3(0, 0, -9), Vector3(3, 0, -8)]:
		pack.append(arena.director.spawn(&"blue", point))
	launch_through(pack)
	expect(pack.all(func(e): return e.health <= 0), "One real curved cutter launch kills three blue connectors: " + str(pack.map(func(e): return [e.health,e.cable_cut])) + " " + arena.weapons.last_feedback)
	expect(arena.equipment.remaining(&"ring") == arena.equipment.capacity(&"ring") - 1, "Multi-kill costs one cutter launch, not one per target")
	expect(arena.feedback.metrics().effects >= 4, "Every broken connector produces visual feedback even when simultaneous sounds are coalesced")

	fresh(&"target")
	arena.director.clear()
	pack = []
	for index in range(3):
		pack.append(arena.director.spawn(&"blue" if index == 0 else &"side_guard", Vector3(-3 + index * 3, 0, -8)))
	launch_through(pack)
	expect(pack[0].health <= 0 and pack[1].is_core_exposed() and pack[2].is_core_exposed(), "Same stroke kills a blue and exposes multiple guards without returning on impact: " + str(pack.map(func(e): return [e.health,e.cable_cut])) + " " + arena.weapons.last_feedback)

	fresh(&"target")
	arena.director.clear()
	arena.director._spawn_counter = 0
	pack = []
	for point in [Vector3(-2, 0, -12), Vector3(0, 0, -7), Vector3(2, 0, -10)]:
		pack.append(arena.director.spawn(&"blue", point))
	var targets: Array = pack.map(func(e): return e.pack_target(Vector3.ZERO, pack))
	var radii: Array = targets.map(func(p): return p.length())
	expect(absf(radii.max() - radii.min()) < 0.001 and targets[0].distance_to(targets[1]) > 1.5, "Blue pack seeks spaced slots on one smooth arc")
	var before_spread: float = pack[0].position.length() - pack[1].position.length()
	for tick in range(120): arena.director.step(1.0 / 60, arena.player)
	var after_spread: float = absf(pack[0].position.length() - pack[1].position.length())
	expect(after_spread < before_spread, "Actual movement reduces depth scatter in a blue pack")
	var saved: Dictionary = arena.capture_state()
	var desired: Vector3 = pack[1].pack_target(Vector3.ZERO, pack)
	arena.director.step(0.1, arena.player)
	arena._restore_world(saved, arena.player.slow_charge)
	expect(pack[1].pack_target(Vector3.ZERO, arena.director.enemies).is_equal_approx(desired), "Pack slots reconstruct exactly from restored stable IDs and positions")
	for tick in range(360): arena.director.step(1.0 / 60, arena.player)
	expect(arena.player.health < 100, "Curved packs release formation and actually attack instead of orbiting forever")

	enemy = fresh(&"blue", Vector3(0, 0, -1.1))
	var health: float = arena.player.health
	enemy.step_enemy(0.01, arena.player)
	expect(enemy.attack_phase == &"windup" and arena.player.health == health, "Contact begins a visible windup, not instant damage")
	var winding: Dictionary = enemy.capture_state()
	enemy.step_enemy(0.55, arena.player)
	expect(arena.player.health < health and enemy.attack_phase == &"recover", "Committed attack deals one hit then recovers")
	var after: float = arena.player.health
	enemy.step_enemy(1.0, arena.player)
	expect(arena.player.health == after and enemy.attack_phase == &"recover", "Recovery supplies a genuine gap in attacks")
	enemy.restore_state(winding)
	expect(enemy.attack_phase == &"windup" and is_equal_approx(enemy.attack_timer, winding.attack_timer), "Rewind restores windup and remaining time")
	enemy.apply_control(Vector3.FORWARD, 22, 0.85)
	expect(enemy.stagger_timer >= 2.0 and enemy.knockback_vel.length() > 22, "Cone gives light enemies a larger shove and two-second stun")
	enemy.step_enemy(1.5, arena.player)
	expect(enemy.stagger_timer > 0 and arena.player.health == after, "Cone interruption leaves an attack-free repair window")

	fresh(&"target")
	expect(arena.player.visual.scale.is_equal_approx(Vector3.ONE * 1.3), "Player visual is larger without changing collider or history root")
	arena.player.visual.step_visual(0.1, 4.0)
	expect(arena.player.visual.grip_error("L") < 0.025,
		"Skinned support arm reaches actual equipment handle while walking")
	key(KEY_1)
	arena.weapons.handle_event(mouse(true), arena.player, Vector3(0, 0, -5))
	key(KEY_TAB)
	expect(arena.weapons.selected_tool == 2 and not arena.weapons.ring_drawing, "Tab switches tools and cancels unfinished drawing")
	key(KEY_TAB, true)
	expect(arena.weapons.selected_tool == 1, "Shift-Tab cycles backward")
	key(KEY_TAB, true)
	expect(arena.weapons.selected_tool == 4, "Backward cycling wraps to clock")
	for code in [KEY_F2, KEY_F3, KEY_F4, KEY_F8]: key(code)
	var kinds: Array = arena.director.enemies.map(func(e): return e.kind)
	expect(kinds == [&"target", &"blue", &"yellow", &"orange", &"side_guard"], "Sandbox spawns only stationary targets and current part variants")
	key(KEY_F9)
	expect(arena.director.enemies.size() == 1 and arena.director.enemies[0].kind == &"front_guard", "F9 isolates front opening variant")
	arena.director.clear()
	for index in range(32):
		arena.director.spawn(&"side_guard", Vector3(index % 8 - 4, 0, -8 - index / 8))
	for tick in range(100): arena.history.record(0.05, arena.capture_state)
	expect(arena.history.snapshot_count == 100 and arena.history.rejected_count == 0,
		"Full history accepts 32 part-bearing enemies without exceeding snapshot cap")
	expect(arena.history.encoded_bytes <= 100 * 65536,
		"Part variants preserve the existing bounded rewind storage")

	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
